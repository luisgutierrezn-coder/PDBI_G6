# uvicorn server:app --host 127.0.0.1 --port 8000
#python -m uvicorn server:app --host 127.0.0.1 --port 8000

import asyncio
import json
import time
import threading
import cv2
from concurrent.futures import ThreadPoolExecutor
from typing import Literal
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel, Field

from metrics.session_manager import SessionManager
from metrics import emg_metrics, emg_progreso
from camera_manager import CameraManager
from hand_tracking import HandTracker
from placas import GestorPlacas, buscar_placas, CODIGO_MAKI
import wifi_ble
from pydantic import BaseModel


# ==================================================
# CONFIGURACIÓN
# ==================================================

CAMERA_1_URL = 0
CAMERA_2_URL = "    :81/stream"

MODEL_PATH = "hand_landmarker.task"

WINDOW_1_NAME = "MaKi - Camara 1"
WINDOW_2_NAME = "MaKi - Camara 2"

CAMERA_2_ENABLED = False


# ==================================================
# VARIABLES GLOBALES
# ==================================================

app = FastAPI()

camera_manager = CameraManager()


def asignar_fuente(camera_id, url):
    if camera_manager.get_status(camera_id)["source"] != url:
        camera_manager.configure_camera(camera_id, url)


def video_de_placa(placa, url):
    if placa.camera_id:
        asignar_fuente(placa.camera_id, url)


gestor_placas = GestorPlacas(video_de_placa)

tracker_1 = None
tracker_2 = None

show_camera_1 = False
show_camera_2 = False

window_1_created = False
window_2_created = False

session_manager = SessionManager()

# ==================================================
# WEBCAM LOCAL PARA PRUEBAS
# ==================================================

webcam_thread = None
webcam_stop_event = None


rehab_positioning_event = threading.Event()

rehab_rep_event = threading.Event()

rehab_finish_event = threading.Event()

last_result = None

latest_tracking = {"pip": None, "dip": None, "detected": False}

WEBCAM_WINDOW_NAME = "MaKi - Prueba Webcam"
# ==================================================
# FUNCIONES PARA CERRAR VENTANAS
# ==================================================

def close_camera_1_window():

    global window_1_created

    if window_1_created:
        cv2.destroyWindow(WINDOW_1_NAME)
        window_1_created = False


def close_camera_2_window():

    global window_2_created

    if window_2_created:
        cv2.destroyWindow(WINDOW_2_NAME)
        window_2_created = False


def close_all_camera_windows():

    global window_1_created, window_2_created

    cv2.destroyAllWindows()

    window_1_created = False
    window_2_created = False


# ==================================================
# INICIALIZACIÓN
# ==================================================

@app.on_event("startup")
async def startup_event():

    global tracker_1, tracker_2

    print("Iniciando MaKi...")

    # Registrar cámaras ESP (la dirección se configura desde Dispositivos)
    camera_manager.add_camera("camera_1")
    camera_manager.add_camera("camera_2")

    # No Iniciar captura

    # Crear detectores independientes
    print("Inicializando MediaPipe para cámara 1...")

    tracker_1 = HandTracker(MODEL_PATH)

    if CAMERA_2_ENABLED:

        print("Inicializando MediaPipe para cámara 2...")

        tracker_2 = HandTracker(MODEL_PATH)

    print("MaKi iniciado correctamente.")


# ==================================================
# CIERRE
# ==================================================

@app.on_event("shutdown")
async def shutdown_event():

    global tracker_1, tracker_2

    detener_vista_previa()
    camera_manager.stop_all()
    gestor_placas.cerrar_todas()

    if tracker_1 is not None:
        tracker_1.close()
        tracker_1 = None

    if tracker_2 is not None:
        tracker_2.close()
        tracker_2 = None

    close_all_camera_windows()

    print("MaKi detenido.")


def wait_external_signal(
    signal_event,
    stop_event,
    callback=None
):

    while not signal_event.is_set():

        if stop_event.is_set():
            return False

        if callback is not None:
            callback()

        time.sleep(0.01)

    signal_event.clear()

    return True
# ==================================================
# WEBCAM LOCAL
# ==================================================

def webcam_capture_loop(
    stop_event,
    started_event,
    result,
    total_reps,
    exercise,
    source="webcam"
):
    global last_result

    cap = None
    tracker = None
    esp_tracker_2 = None
    grabador = None
    last_count = -1

    use_esp = source == "esp"

    is_wrist = exercise == "wrist_movement"
    is_abduction = exercise == "finger_abduction"
    is_full_fist = exercise == "full_fist"

    exercise_titles = {
        "pinch_index": "EJECUCION - PINZA INDICE",
        "wrist_movement": "EJECUCION - MOVIMIENTO DE MUÑECA",
        "finger_abduction": "EJECUCION - ABDUCCION DE DEDOS",
        "full_fist": "EJECUCION - CIERRE COMPLETO DE MANO"
    }

    try:
        if use_esp:
            print("Iniciando cámaras ESP...")

            gestor_placas.encender_video(CAMERA_IDS)

            if not camera_manager.start_camera("camera_1"):
                raise RuntimeError("No se pudo iniciar la Cámara 1 (ESP).")

            if camera_manager.is_configured("camera_2"):
                camera_manager.start_camera("camera_2")

            esp_tracker_2 = HandTracker(MODEL_PATH)

        else:
            print("Abriendo webcam de MaKi...")

            cap = cv2.VideoCapture(0)

            if not cap.isOpened():
                raise RuntimeError("No se pudo abrir la webcam.")

        tracker = HandTracker(MODEL_PATH)

        session_manager.start(total_reps, exercise=exercise)

        print(f"Webcam abierta. Ejercicio: {exercise}")

        started_event.set()

        grabador = GrabadorEMG()
        grabador.iniciar()

        camera_start = time.perf_counter()
        timestamp = 0

        # ==========================================
        # CAPTURAR FRAME
        # ==========================================

        def capture_frame():
            nonlocal timestamp, last_count

            if use_esp:
                count = camera_manager.get_frame_count("camera_1")

                if count == last_count:
                    time.sleep(0.005)
                    return None, None, None, None, None, None

                last_count = count
                frame = camera_manager.get_frame("camera_1")
                ret = frame is not None

            else:
                ret, frame = cap.read()

            if not ret:
                return None, None, None, None, None, None

            elapsed_ms = int(
                (time.perf_counter() - camera_start) * 1000
            )

            timestamp = max(elapsed_ms, timestamp + 1)

            display, pip, dip, landmarks, distances = (
                tracker.process(frame, timestamp)
            )

            latest_tracking.update(
                pip=pip,
                dip=dip,
                detected=landmarks is not None
            )

            return display, pip, dip, landmarks, distances, frame

        # ==========================================
        # MOSTRAR VENTANAS
        # ==========================================

        def show_frames(display):
            global window_1_created, window_2_created

            if not use_esp:
                cv2.imshow(WEBCAM_WINDOW_NAME, display)
                cv2.waitKey(1)
                return

            if show_camera_1:
                cv2.imshow(WINDOW_1_NAME, display)
                window_1_created = True
            else:
                close_camera_1_window()

            if show_camera_2:
                frame_2 = camera_manager.get_frame("camera_2")

                if frame_2 is not None:
                    elapsed_ms = int(
                        (time.perf_counter() - camera_start) * 1000
                    )
                    display_2 = esp_tracker_2.process(frame_2, elapsed_ms)[0]
                    cv2.imshow(WINDOW_2_NAME, display_2)
                    window_2_created = True
            else:
                close_camera_2_window()

            cv2.waitKey(1)

        # ==========================================
        # MOSTRAR ESTADO
        # ==========================================

        def show_status(frame, title, remaining, rep_text=""):
            cv2.rectangle(
                frame,
                (0, 0),
                (frame.shape[1], 125),
                (30, 30, 30),
                -1
            )

            cv2.putText(
                frame,
                title,
                (20, 35),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (255, 255, 255),
                2
            )

            cv2.putText(
                frame,
                f"Tiempo: {remaining}s",
                (20, 75),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 255, 255),
                2
            )

            if rep_text:
                cv2.putText(
                    frame,
                    rep_text,
                    (20, 110),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    (0, 255, 0),
                    2
                )

            cv2.imshow(WEBCAM_WINDOW_NAME, frame)

            if cv2.waitKey(1) & 0xFF == 27:
                stop_event.set()

        # ==========================================
        # OBTENER MUESTRA DE REFERENCIA
        # ==========================================

        
        def get_baseline_values(distances):

            # ------------------------------------------
            # WRIST MOVEMENT
            # ------------------------------------------

            if is_wrist:
                return {
                    "distance": None,
                    "finger_angles": None,
                    "hand_angle_deg": tracker.last_hand_angle_deg,
                    "abduction": None,
                    "full_fist_angles": None
                }

            # ------------------------------------------
            # FINGER ABDUCTION
            # ------------------------------------------

            if is_abduction:

                abduction = (
                    distances.get("abduction")
                    if distances is not None
                    else None
                )

                return {
                    "distance": None,
                    "finger_angles": None,
                    "hand_angle_deg": None,
                    "abduction": abduction,
                    "full_fist_angles": None
                }

            # ------------------------------------------
            # FULL FIST
            # ------------------------------------------

            if is_full_fist:

                full_fist_angles = (
                    distances.get("full_fist_angles")
                    if distances is not None
                    else None
                )

                return {
                    "distance": None,
                    "finger_angles": None,
                    "hand_angle_deg": None,
                    "abduction": None,
                    "full_fist_angles": full_fist_angles
                }

            # ------------------------------------------
            # PINCH INDEX
            # ------------------------------------------

            distance = (
                distances["normalized"]["thumb_index"]
                if distances is not None else None
            )

            return {
                "distance": distance,
                "finger_angles": (
                    distances.get("finger_angles")
                    if distances else None
                ),
                "hand_angle_deg": None,
                "abduction": None,
                "full_fist_angles": None
            }


        # ==========================================
        # OBTENER MUESTRA DE EJECUCIÓN
        # ==========================================

        def get_rep_sample(
            distances,
            pip,
            dip,
            elapsed_rep
        ):

            # ------------------------------------------
            # WRIST MOVEMENT
            # ------------------------------------------

            if is_wrist:

                hand_angle = tracker.last_hand_angle_deg

                if hand_angle is None:
                    return None

                return {
                    "timestamp": round(elapsed_rep, 4),
                    "hand_angle_deg": hand_angle
                }

            # ------------------------------------------
            # FINGER ABDUCTION
            # ------------------------------------------

            if is_abduction:

                abduction = (
                    distances.get("abduction")
                    if distances is not None
                    else None
                )

                if (
                    abduction is None
                    or abduction.get("global_opening") is None
                ):
                    return None

                return {
                    "timestamp": round(elapsed_rep, 4),
                    "normalized": abduction["normalized"].copy(),
                    "global_opening": abduction["global_opening"]
                }

            
            # ------------------------------------------
            # FULL FIST
            # ------------------------------------------

            if is_full_fist:

                full_fist_angles = (
                    distances.get("full_fist_angles")
                    if distances is not None
                    else None
                )

                if full_fist_angles is None:
                    return None

                # Verificar que estén disponibles los cinco dedos.
                if any(
                    full_fist_angles.get(finger) is None
                    for finger in (
                        "thumb",
                        "index",
                        "middle",
                        "ring",
                        "pinky"
                    )
                ):
                    return None

                return {
                    "timestamp": round(elapsed_rep, 4),
                    "thumb": full_fist_angles["thumb"],
                    "index": full_fist_angles["index"],
                    "middle": full_fist_angles["middle"],
                    "ring": full_fist_angles["ring"],
                    "pinky": full_fist_angles["pinky"]
                }


            # ------------------------------------------
            # PINCH INDEX
            # ------------------------------------------

            

            distance = (
                distances["normalized"]["thumb_index"]
                if distances is not None else None
            )

            if distance is None:
                return None

            return {
                "timestamp": round(elapsed_rep, 4),
                "pinch_distance": distance,
                "pip_angle": pip,
                "dip_angle": dip,
                "finger_angles": (
                    distances.get("finger_angles")
                    if distances else None
                )
            }
        # ==========================================
        # FASE DE POSICIONAMIENTO
        # ==========================================

        def run_positioning(title):

            session_manager.begin_positioning()
            grabador.marcar("posicionamiento")

            def process():

                display,pip,dip,landmarks,distances,frame = (
                    capture_frame()
                )

                if display is None:
                    return

                baseline = get_baseline_values(
                    distances
                )

                session_manager.add_baseline_sample(
                    distance=baseline["distance"],
                    finger_angles=baseline["finger_angles"],
                    hand_angle_deg=baseline["hand_angle_deg"],
                    abduction=baseline["abduction"],
                    full_fist_angles=
                        baseline["full_fist_angles"]
                )

                show_frames(display)

            return wait_external_signal(
                rehab_positioning_event,
                stop_event,
                process
            )
        # ==========================================
        # FASE 1: POSICIONAMIENTO INICIAL
        # ==========================================

        if is_wrist:

            initial_title = (
                "POSICIONAMIENTO INICIAL - MUÑECA NEUTRA"
            )

        elif is_abduction:

            initial_title = (
                "POSICIONAMIENTO INICIAL - DEDOS JUNTOS"
            )

        else:

            initial_title = (
                "POSICIONAMIENTO INICIAL - MANO ABIERTA"
            )

        if not run_positioning(initial_title):
            return

        # ==========================================
        # FASE 2: REPETICIONES
        # ==========================================

        def run_rep(rep):

            session_manager.begin_rep(rep)
            grabador.marcar("ejecucion", rep)

            rep_start = time.perf_counter()

            def process():

                display,pip,dip,landmarks,distances,frame = (
                    capture_frame()
                )

                if display is None:
                    return

                sample = get_rep_sample(
                    distances,
                    pip,
                    dip,
                    time.perf_counter() - rep_start
                )

                session_manager.add_frame(
                    valid=sample is not None
                )

                if sample is not None:
                    session_manager.add_rep_sample(
                        sample
                    )

                show_frames(display)

            ok = wait_external_signal(
                rehab_rep_event,
                stop_event,
                process
            )

            if ok:
                session_manager.finish_rep()
                grabador.marcar(None)

            return ok
        
        current_rep = 1

        while current_rep <= total_reps:

            if not run_rep(current_rep):
                return

            if current_rep < total_reps:

                if not run_positioning(
                    "REPOSICIONAMIENTO"
                ):
                    return

            current_rep += 1
        

        # ==========================================
        # FINALIZAR SESIÓN
        # ==========================================

        if not wait_external_signal(
            rehab_finish_event,
            stop_event
        ):
            return
        
        print("COMPLETANDO SESION")

        extra = {}

        if grabador.activo:
            datos_emg = grabador.detener()

            try:
                clave = emg_metrics.EJERCICIOS_EMG.get(exercise, {}).get("movimiento")
                movimiento = {
                    rep["number"]: rep.get("metrics", {}).get(clave)
                    for rep in session_manager.repetitions
                    if rep.get("metrics", {}).get("valid")
                }
                extra["emg"] = emg_metrics.calcular(
                    exercise, datos_emg, grabador.segmentos, movimiento
                )
            except Exception as error:
                print("Error calculando EMG:", error)
                extra["emg"] = {"disponible": False, "motivo": str(error)}

        session_manager.complete(extra)

        last_result = session_manager.snapshot()["result"]

        print("Prueba completada.")

    except Exception as e:
        result["error"] = str(e)

        session_manager.fail(str(e))

        # Evita que el endpoint espere hasta agotar el timeout
        # si ocurre un error antes de iniciar la sesión.
        started_event.set()

        print("Error en webcam:", e)

    finally:
        if grabador is not None and grabador.activo:
            grabador.detener()

        if cap is not None:
            cap.release()

        if tracker is not None:
            tracker.close()

        if esp_tracker_2 is not None:
            esp_tracker_2.close()

        if use_esp:
            camera_manager.stop_all()
            gestor_placas.apagar_video(CAMERA_IDS)
            close_camera_1_window()
            close_camera_2_window()
            cv2.waitKey(1)

        latest_tracking.update(pip=None, dip=None, detected=False)

        try:
            if cv2.getWindowProperty(
                WEBCAM_WINDOW_NAME,
                cv2.WND_PROP_VISIBLE
            ) >= 0:
                cv2.destroyWindow(WEBCAM_WINDOW_NAME)
                cv2.waitKey(1)

        except cv2.error:
            pass

        session_manager.cancel()

        print("Webcam detenida.")

class WebcamStartRequest(BaseModel):
    repetitions: int = Field(
        default=5,
        ge=1,
        le=20
    )

    exercise: Literal[
        "pinch_index",
        "wrist_movement",
        "finger_abduction",
        "full_fist"
    ] = "pinch_index"


class RehabilitationStartRequest(BaseModel):
    exercise: str
    repetitions: int
    source: Literal["webcam", "esp"] = "webcam"


class CameraConfig(BaseModel):
    source: str

# ==================================================
# ENDPOINTS DE PRUEBA
# ==================================================

@app.post("/rehabilitation/start")
async def rehabilitation_start(
    request: RehabilitationStartRequest
):
    global webcam_thread, webcam_stop_event, last_result

    if webcam_thread is not None and webcam_thread.is_alive():

        return {
            "status": "already_running",
            "message": "La webcam ya esta activa."
        }

    await asyncio.to_thread(detener_vista_previa)

    rehab_positioning_event.clear()
    rehab_rep_event.clear()
    rehab_finish_event.clear()
    last_result = None

    webcam_stop_event = threading.Event()

    started_event = threading.Event()
    result = {}

    webcam_thread = threading.Thread(
        target=webcam_capture_loop,
        args=(
            webcam_stop_event,
            started_event,
            result,
            request.repetitions,
            request.exercise,
            request.source
        ),
        daemon=True
    )

    webcam_thread.start()

    await asyncio.to_thread(
        started_event.wait,
        5
    )

    if not started_event.is_set():

        webcam_stop_event.set()

        return {
            "status": "running",
            "message": "Prueba iniciada.",
            "repetitions": request.repetitions,
            "exercise": request.exercise
        }


    if "error" in result:

        return {
            "status": "error",
            "message": result["error"]
        }

    return {
        "success": True,
            "message": "Sesión iniciada",
            "exercise": request.exercise,
            "repetitions": request.repetitions
    }
"""
    try:

        session_manager.start(
            exercise=request.exercise,
            total_reps=request.repetitions
        )

        return {
            "success": True,
            "message": "Sesión iniciada",
            "exercise": request.exercise,
            "repetitions": request.repetitions
        }

    except Exception as e:

        return {
            "success": False,
            "message": str(e)
        }
""";

@app.get("/rehabilitation/status")
async def rehabilitation_status():

    snapshot = session_manager.snapshot()

    return {
        "success": True,
        "status": snapshot["status"],
        "phase": snapshot["phase"],
        "current_rep": snapshot["current_rep"],
        "total_reps": snapshot["total_reps"]
    }



# ==================================================
# DISPOSITIVOS
# ==================================================

CAMERA_IDS = ("camera_1", "camera_2")


def comprobar_camara(camera_id):
    # Las placas MaKi apagan la cámara fuera de MEDIR: se enciende solo para la prueba.
    placa = gestor_placas.de_camara(camera_id)
    encendida_aqui = placa is not None and not placa.video_url

    if encendida_aqui:
        placa.encender_video()

    try:
        return camera_manager.check_camera(camera_id)
    finally:
        if encendida_aqui:
            placa.apagar_video()


def validate_camera_id(camera_id):

    if camera_id not in CAMERA_IDS:
        raise HTTPException(
            status_code=404,
            detail="Identificador de cámara no válido."
        )


@app.get("/health")
def health():

    return {
        "status": "online",
        "message": "MaKi está funcionando."
    }


@app.get("/devices")
def get_devices():

    return {
        "devices": camera_manager.get_all_status()
    }


@app.post("/devices/{camera_id}/configure")
def configure_camera(camera_id: str, config: CameraConfig):

    validate_camera_id(camera_id)

    source = config.source.strip()

    if not source:
        raise HTTPException(
            status_code=400,
            detail="La dirección de la cámara está vacía."
        )

    camera_manager.configure_camera(camera_id, source)

    return {
        "success": True,
        "message": f"{camera_id} configurada correctamente.",
        "camera": camera_manager.get_status(camera_id)
    }


@app.post("/devices/{camera_id}/check")
def check_camera(camera_id: str):

    validate_camera_id(camera_id)

    if camera_manager.get_status(camera_id)["streaming"]:
        return {
            "success": True,
            "available": True,
            "message": "La cámara ya está capturando."
        }

    available = comprobar_camara(camera_id)

    return {
        "success": True,
        "available": available,
        "message": (
            "Cámara disponible."
            if available
            else "No se pudo recibir video de la cámara."
        )
    }


@app.post("/devices/check-all")
def check_all_cameras():

    results = {}

    for camera_id in CAMERA_IDS:

        if camera_manager.get_status(camera_id)["streaming"]:
            results[camera_id] = True
        elif camera_manager.is_configured(camera_id):
            results[camera_id] = comprobar_camara(camera_id)
        else:
            results[camera_id] = False

    return {
        "success": True,
        "cameras": results,
        "all_available": all(results.values())
    }


@app.post("/devices/{camera_id}/start")
def start_camera(camera_id: str):

    validate_camera_id(camera_id)

    success = camera_manager.start_camera(camera_id)

    return {
        "success": success,
        "message": (
            "Captura iniciada."
            if success
            else "No se pudo iniciar la captura."
        )
    }


@app.post("/devices/{camera_id}/stop")
def stop_camera(camera_id: str):

    validate_camera_id(camera_id)

    camera_manager.stop_camera(camera_id)

    return {
        "success": True,
        "message": "Captura detenida."
    }


# ==================================================
# VISTA PREVIA DE CÁMARAS (POSICIONAR ANTES DE LA SESIÓN)
# ==================================================

preview_thread = None
preview_stop_event = threading.Event()

PREVIEW_NAMES = {
    "camera_1": "MaKi - Vista previa Camara 1",
    "camera_2": "MaKi - Vista previa Camara 2"
}


class PreviewRequest(BaseModel):
    camera_ids: list[str] | None = None


def vista_previa_loop(stop_event, camera_ids):
    trackers = {}
    ultimos = {}
    abiertas = set()
    activas = []
    inicio = time.perf_counter()

    try:
        gestor_placas.encender_video(camera_ids)

        for camera_id in camera_ids:
            if camera_manager.start_camera(camera_id):
                activas.append(camera_id)
                trackers[camera_id] = HandTracker(MODEL_PATH)

        while activas and not stop_event.is_set():
            for camera_id in activas:
                cuenta = camera_manager.get_frame_count(camera_id)

                if cuenta == ultimos.get(camera_id):
                    continue

                ultimos[camera_id] = cuenta
                frame = camera_manager.get_frame(camera_id)

                if frame is None:
                    continue

                ms = int((time.perf_counter() - inicio) * 1000)
                display, _, _, landmarks, _ = trackers[camera_id].process(frame, ms)

                detectada = landmarks is not None
                cv2.putText(
                    display,
                    "Mano detectada" if detectada else "No se detecta la mano",
                    (10, 25),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (0, 200, 0) if detectada else (0, 0, 255),
                    2
                )

                nombre = PREVIEW_NAMES[camera_id]
                cv2.imshow(nombre, display)
                abiertas.add(nombre)

            if cv2.waitKey(15) & 0xFF == 27:
                break

            # Si se cierra una ventana con la X, termina la vista previa
            cerrada = False
            for nombre in abiertas:
                try:
                    if cv2.getWindowProperty(nombre, cv2.WND_PROP_VISIBLE) < 1:
                        cerrada = True
                except cv2.error:
                    cerrada = True
            if cerrada:
                break

    except Exception as error:
        print("Error en la vista previa:", error)

    finally:
        for tracker in trackers.values():
            tracker.close()

        for camera_id in activas:
            camera_manager.stop_camera(camera_id)

        gestor_placas.apagar_video(camera_ids)

        for nombre in abiertas:
            try:
                cv2.destroyWindow(nombre)
            except cv2.error:
                pass

        cv2.waitKey(1)
        print("Vista previa cerrada.")


def vista_previa_activa():
    return preview_thread is not None and preview_thread.is_alive()


def detener_vista_previa():
    global preview_thread

    if preview_thread is None:
        return

    preview_stop_event.set()
    preview_thread.join(timeout=5)
    preview_thread = None


@app.get("/devices/preview")
def estado_vista_previa():

    return {
        "activa": vista_previa_activa()
    }


@app.post("/devices/preview/start")
def iniciar_vista_previa(datos: PreviewRequest):

    global preview_thread, preview_stop_event

    if webcam_thread is not None and webcam_thread.is_alive():
        return {
            "success": False,
            "message": "Hay una sesión en curso."
        }

    detener_vista_previa()

    camera_ids = datos.camera_ids or [
        camera_id for camera_id in CAMERA_IDS
        if camera_manager.is_configured(camera_id)
    ]

    for camera_id in camera_ids:
        validate_camera_id(camera_id)

    if not camera_ids:
        return {
            "success": False,
            "message": "No hay cámaras configuradas."
        }

    preview_stop_event = threading.Event()
    preview_thread = threading.Thread(
        target=vista_previa_loop,
        args=(preview_stop_event, camera_ids),
        daemon=True
    )
    preview_thread.start()

    return {
        "success": True,
        "camera_ids": camera_ids,
        "message": "Vista previa abierta en ventanas de Python. Esc o la X para cerrarla."
    }


@app.post("/devices/preview/stop")
def parar_vista_previa():

    detener_vista_previa()

    return {
        "success": True
    }


# ==================================================
# CALIBRACIÓN DEL EMG
# ==================================================

class CalibracionMvc(BaseModel):
    canal: str


def placas_emg():
    return [
        placa for placa in gestor_placas.placas.values()
        if placa.conectada and placa.canales
    ]


def preparar_calibracion():
    detener_vista_previa()

    for placa in placas_emg():
        placa.orden("PARAR", esperar=("ok,PARAR",), timeout=2)


class GrabadorEMG:
    """Graba el EMG de las placas durante un ejercicio y marca cuándo empieza y termina cada fase."""

    def __init__(self):
        self.placas = []
        self.segmentos = []
        self.activo = False

    def iniciar(self):
        for placa in placas_emg():
            try:
                placa.iniciar_grabacion()
                respuesta = placa.orden("MEDIR", esperar=("ok,MEDIR", "error,"))
            except ConnectionError:
                respuesta = None

            if respuesta and respuesta.startswith("ok"):
                self.placas.append(placa)
            else:
                placa.detener_grabacion()

        self.activo = bool(self.placas)

        if self.activo:
            print("Grabando EMG:", ", ".join(p.nombre for p in self.placas))

    def marcar(self, fase, rep=None):
        ahora = time.time()

        if self.segmentos and self.segmentos[-1]["fin"] is None:
            self.segmentos[-1]["fin"] = ahora

        if fase:
            self.segmentos.append({"fase": fase, "rep": rep, "inicio": ahora, "fin": None})

    def detener(self):
        self.marcar(None)
        datos = {}

        for placa in self.placas:
            try:
                placa.orden("PARAR", esperar=("ok,PARAR",), timeout=2)
            except ConnectionError:
                pass

            datos[placa.ip] = {
                "canales": list(placa.canales),
                "muestras": placa.detener_grabacion(),
                "calibracion": {k: dict(v) for k, v in placa.calibracion.items()}
            }

        self.activo = False
        return datos


@app.get("/calibracion/canales")
def canales_calibracion():

    placas = placas_emg()

    return {
        "placas": [
            {"ip": p.ip, "nombre": p.nombre, "canales": p.canales}
            for p in placas
        ],
        "canales": [canal for p in placas for canal in p.canales]
    }


@app.post("/calibracion/revisar")
def revisar_electrodos():

    preparar_calibracion()
    canales = {}

    for placa in placas_emg():
        for canal, lectura in placa.revisar_electrodos().items():
            nivel = lectura["nivel_mv"]

            if nivel < 300:
                estado = "sin_senal"
            elif nivel > 2800:
                estado = "saturado"
            elif lectura["suelto"]:
                estado = "suelto"
            else:
                estado = "ok"

            canales[canal] = {**lectura, "estado": estado}

    return {
        "success": bool(canales) and all(c["estado"] == "ok" for c in canales.values()),
        "canales": canales
    }


@app.post("/calibracion/reposo")
def calibrar_reposo():

    preparar_calibracion()
    placas = placas_emg()

    if not placas:
        return {
            "success": False,
            "errores": ["No hay placas EMG conectadas."]
        }

    def medir(placa):
        placa.calibracion = {}
        return placa.orden("REPOSO", esperar=("fin,REPOSO", "error,"), timeout=15)

    with ThreadPoolExecutor(len(placas)) as ejecutor:
        respuestas = list(ejecutor.map(medir, placas))

    errores = [
        f"{p.nombre}: {r or 'sin respuesta'}"
        for p, r in zip(placas, respuestas)
        if r is None or r.startswith("error")
    ]

    return {
        "success": not errores,
        "errores": errores,
        "canales": {
            canal: datos
            for p in placas
            for canal, datos in p.calibracion.items()
        }
    }


@app.post("/calibracion/mvc")
def calibrar_mvc(datos: CalibracionMvc):

    placa = next(
        (p for p in placas_emg() if datos.canal in p.canales),
        None
    )

    if placa is None:
        return {
            "success": False,
            "error": f"No hay una placa conectada con el canal {datos.canal}."
        }

    respuesta = placa.orden(
        f"MVC {datos.canal}",
        esperar=("fin,MVC", "error,"),
        timeout=10
    )

    return {
        "success": respuesta is not None and respuesta.startswith("fin"),
        "error": None if respuesta and respuesta.startswith("fin") else (respuesta or "sin respuesta"),
        "canal": datos.canal,
        "datos": placa.calibracion.get(datos.canal, {})
    }


# ==================================================
# EVOLUCIÓN DEL EMG (PROGRESO)
# ==================================================

class ProgresoEmgRequest(BaseModel):
    # De la sesión más antigua a la más nueva: cada una con el resultado "emg" de sus ejercicios
    sesiones: list[list[dict]]
    nivel: Literal["bajo", "medio_alto"] | None = None


@app.post("/progreso/emg")
def progreso_emg(datos: ProgresoEmgRequest):

    sesiones = []

    for ejercicios in datos.sesiones:
        valores, reps = {}, {}

        for resultado in ejercicios:
            v, r = emg_metrics.indicadores(resultado)
            valores.update(v)
            reps.update(r)

        sesiones.append({"valores": valores, "reps": reps})

    return {
        "success": True,
        **emg_progreso.evolucion(sesiones, datos.nivel)
    }


# ==================================================
# PLACAS MAKI (EMG + CÁMARA) Y WI-FI POR BLUETOOTH
# ==================================================

class PlacaConectar(BaseModel):
    ip: str
    camera_id: str | None = None


class PlacaOrden(BaseModel):
    orden: str


class WifiBluetooth(BaseModel):
    address: str
    ssid: str | None = None
    clave: str | None = None
    codigo: str = CODIGO_MAKI


def obtener_placa(ip):
    placa = gestor_placas.obtener(ip)

    if placa is None:
        raise HTTPException(
            status_code=404,
            detail="La placa no está conectada."
        )

    return placa


@app.get("/placas")
def listar_placas():

    return {
        "placas": gestor_placas.estado()
    }


@app.post("/placas/buscar")
def buscar_placas_red():

    return {
        "success": True,
        "encontradas": buscar_placas()
    }


@app.post("/placas/conectar")
def conectar_placa(datos: PlacaConectar):

    if datos.camera_id:
        validate_camera_id(datos.camera_id)

    try:
        placa = gestor_placas.conectar(datos.ip.strip(), datos.camera_id)
    except (OSError, ConnectionError) as error:
        return {
            "success": False,
            "message": f"No se pudo conectar con {datos.ip}: {error}"
        }

    if datos.camera_id:
        asignar_fuente(datos.camera_id, f"http://{placa.ip}/stream")

    return {
        "success": True,
        "placa": placa.estado()
    }


@app.post("/placas/{ip}/desconectar")
def desconectar_placa(ip: str):

    gestor_placas.desconectar(ip)

    return {
        "success": True
    }


@app.post("/placas/{ip}/orden")
def orden_placa(ip: str, datos: PlacaOrden):

    placa = obtener_placa(ip)
    texto = datos.orden.strip()

    if not texto or "\n" in texto or len(texto) > 100:
        raise HTTPException(
            status_code=400,
            detail="Orden no válida."
        )

    esperar = ("hola,",) if texto == "HOLA" else ("ok,", "error,", "inicio,", "crudo,")

    try:
        respuesta = placa.orden(texto, esperar=esperar)
    except ConnectionError as error:
        return {
            "success": False,
            "message": str(error)
        }

    return {
        "success": respuesta is not None and not respuesta.startswith("error"),
        "respuesta": respuesta,
        "placa": placa.estado()
    }


@app.get("/wifi/laptop")
def wifi_laptop():

    red = wifi_ble.red_de_la_laptop()

    if red is None:
        return {
            "success": False,
            "message": "La laptop no está conectada a una red Wi-Fi."
        }

    return {
        "success": True,
        "ssid": red["ssid"],
        "tiene_clave": bool(red["clave"]),
        "banda_5ghz": red["banda_5ghz"]
    }


@app.post("/ble/buscar")
def buscar_bluetooth():

    try:
        return {
            "success": True,
            "dispositivos": wifi_ble.buscar_ble()
        }
    except Exception as error:
        return {
            "success": False,
            "message": f"No se pudo buscar por Bluetooth: {error}"
        }


@app.post("/ble/configurar")
def configurar_por_bluetooth(datos: WifiBluetooth):

    ssid = datos.ssid
    clave = datos.clave
    red = wifi_ble.red_de_la_laptop() if not ssid or not clave else None

    if not ssid:
        if red is None:
            return {
                "success": False,
                "message": "La laptop no está conectada a una red Wi-Fi."
            }

        ssid = red["ssid"]

    if not clave and red is not None and red["ssid"] == ssid:
        clave = red["clave"]

    try:
        respuesta = wifi_ble.configurar_wifi(datos.address, ssid, clave, datos.codigo)
    except Exception as error:
        return {
            "success": False,
            "message": f"No se pudo configurar por Bluetooth: {error}"
        }

    mensajes = {
        "error,codigo": "La placa rechazó el código.",
        "error,formato": "La placa no entendió los datos enviados.",
        "error,red_no_encontrada": f"La placa no encuentra la red {ssid} (¿es de 5 GHz?).",
        "error,no_conecta": f"La placa no pudo conectarse a {ssid} (¿clave incorrecta?).",
        "desconectada": "La placa se desconectó del Bluetooth: probablemente ya entró a la red. Búscala en la red."
    }

    ok = respuesta.startswith("ok,") or respuesta == "desconectada"

    return {
        "success": ok,
        "respuesta": respuesta,
        "ssid": ssid,
        "ip": respuesta.split(",", 1)[1] if respuesta.startswith("ok,") else None,
        "message": mensajes.get(
            respuesta,
            f"Placa conectada a {ssid}." if ok else f"Respuesta de la placa: {respuesta}"
        )
    }


@app.post("/webcam/start")
async def start_webcam(request: WebcamStartRequest):

    global webcam_thread, webcam_stop_event

    if webcam_thread is not None and webcam_thread.is_alive():

        return {
            "status": "already_running",
            "message": "La webcam ya esta activa."
        }

    webcam_stop_event = threading.Event()

    started_event = threading.Event()
    result = {}

    webcam_thread = threading.Thread(
        target=webcam_capture_loop,
        args=(
            webcam_stop_event,
            started_event,
            result,
            request.repetitions,
            request.exercise
        ),
        daemon=True
    )

    webcam_thread.start()

    await asyncio.to_thread(
        started_event.wait,
        5
    )

    if not started_event.is_set():

        webcam_stop_event.set()

        return {
            "status": "running",
            "message": "Prueba iniciada.",
            "repetitions": request.repetitions,
            "exercise": request.exercise
        }


    if "error" in result:

        return {
            "status": "error",
            "message": result["error"]
        }

    return {
        "status": "running",
        "message": "Prueba iniciada.",
        "repetitions": request.repetitions
    }


@app.get("/webcam/status")
async def webcam_status():

    return session_manager.snapshot()


@app.get("/webcam/result")
async def webcam_result():

    data = session_manager.snapshot()

    return {
        "status": data["status"],
        "result": data["result"],
        "error": data["error"]
    }


@app.post("/webcam/stop")
async def stop_webcam():

    global webcam_thread, webcam_stop_event

    if webcam_thread is None or not webcam_thread.is_alive():

        return {
            "status": "not_running"
        }

    webcam_stop_event.set()

    await asyncio.to_thread(
        webcam_thread.join,
        3
    )

    return {
        "status": "stopped"
        if not webcam_thread.is_alive()
        else "stopping"
    }

# ==================================================
# WEBSOCKET
# ==================================================

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):

    global show_camera_1, show_camera_2
    global window_1_created, window_2_created

    await websocket.accept()

    print("Flutter conectado.")

    start_time = time.perf_counter()

    command_task = asyncio.create_task(
        websocket.receive_text()
    )

    timestamp_1 = 0
    timestamp_2 = 0

    try:

        while True:

            # --------------------------------------
            # 1. RECIBIR COMANDOS
            # --------------------------------------

            if command_task.done():

                try:

                    message = command_task.result()
                    command = json.loads(message)

                    command_name = command.get("command")

                    if command_name == "start_exercise":
                        exercise = command.get(
                            "exercise",
                            "pinch_index"
                        )

                        repetitions = command.get(
                            "repetitions",
                            3
                        )

                        session_manager.start(
                            repetitions,
                            exercise=exercise
                        )

                        print(
                            f"Ejercicio iniciado: "
                            f"{exercise} "
                            f"({repetitions} repeticiones)"
                        )

                    elif command_name == "start_cameras":

                        print("Iniciando captura de cámaras...")

                        await asyncio.to_thread(
                            camera_manager.start_camera,
                            "camera_1"
                        )

                        if CAMERA_2_ENABLED:
                            await asyncio.to_thread(
                                camera_manager.start_camera,
                                "camera_2"
                            )

                        print("Captura de cámaras iniciada.")

                    elif command_name == "stop_cameras":

                        print("Deteniendo captura de cámaras...")

                        await asyncio.to_thread(
                            camera_manager.stop_all
                        )

                        print("Captura de cámaras detenida.")

                    elif command_name == "show_camera_1":

                        show_camera_1 = True
                        show_camera_2 = False

                        print("Mostrando cámara 1.")

                    elif command_name == "show_camera_2":

                        show_camera_1 = False
                        show_camera_2 = True

                        print("Mostrando cámara 2.")

                    elif command_name == "show_both":

                        show_camera_1 = True
                        show_camera_2 = True

                        print("Mostrando ambas cámaras.")

                    elif command_name == "hide_cameras":

                        show_camera_1 = False
                        show_camera_2 = False

                        print("Ventanas ocultas.")

                    command_task = asyncio.create_task(
                        websocket.receive_text()
                    )

                except WebSocketDisconnect:
                    break

                except Exception as e:

                    print("Error recibiendo comando:", e)
                    break

            # --------------------------------------
            # 6. ENVIAR DATOS A FLUTTER
            # --------------------------------------

            snapshot = session_manager.snapshot()
            data = {
                "event": "tracking",

                "time": round(
                    time.perf_counter() - start_time,
                    2
                ),

                "camera1": dict(latest_tracking),

                "camera2": {
                    "pip": None,
                    "dip": None
                },

                "session": {
                    "status": snapshot["status"],
                    "phase": snapshot["phase"],
                    "current_rep": snapshot["current_rep"],
                    "total_reps": snapshot["total_reps"],
                    "baseline_samples": snapshot["baseline_samples"]
                }
            }
            snapshot = session_manager.snapshot()

            if snapshot["status"] == "COMPLETED":

                await websocket.send_text(
                    json.dumps({
                        "event": "exercise_completed",
                        "result": snapshot["result"]
                    })
                )

                session_manager.reset()
            await websocket.send_text(
                json.dumps(data)
            )

            await asyncio.sleep(0.03)

    except WebSocketDisconnect:

        print("Flutter desconectado.")

    except Exception as e:

        print("Error en WebSocket:", e)

    finally:

        command_task.cancel()

        try:
            await command_task
        except BaseException:
            pass

        show_camera_1 = False
        show_camera_2 = False

        print("Conexión WebSocket cerrada.")

@app.post("/rehabilitation/next-positioning")
async def next_positioning():

    rehab_positioning_event.set()

    return {
        "success": True
    }   

@app.post("/rehabilitation/next-repetition")
async def next_repetition():

    rehab_rep_event.set()

    return {
        "success": True
    }

@app.post("/rehabilitation/finish")
async def finish_rehabilitation():

    print("SEÑAL FIN RECIBIDA")

    rehab_finish_event.set()

    if webcam_thread is not None:
        await asyncio.to_thread(webcam_thread.join, 5)

    return {
        "success": last_result is not None,
        "result": last_result
    }
