
# uvicorn server:app --host 127.0.0.1 --port 8000

import asyncio
import json
import time

import cv2

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from camera_manager import CameraManager
from hand_tracker import HandTracker
from gnd.exercise_manager import ExerciseManager


# ==========================================
# CONFIGURACIÓN
# ==========================================

MODEL_PATH = "hand_landmarker.task"

app = FastAPI()

# Permitir solicitudes desde Flutter Web, si se utiliza Chrome.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

camera_manager = CameraManager()
exercise_manager = ExerciseManager()

tracker_1 = None
tracker_2 = None

server_start_time = time.perf_counter()

camera_windows = {
    "camera_1": False,
    "camera_2": False,
}

active_exercise = None


# ==========================================
# MODELOS PARA SOLICITUDES HTTP
# ==========================================

class CameraConfig(BaseModel):
    source: str


# ==========================================
# MAPEO DE EJERCICIOS
# ==========================================

EXERCISE_ALIASES = {
    "open_close": "open_close",
    "pincer_grasp": "pincer_grasp",
    "fist_my_bump": "fist_my_bump",
    "wrist": "wrist",
}


# ==========================================
# INICIALIZACIÓN
# ==========================================

@app.on_event("startup")
async def startup():

    global tracker_1, tracker_2

    print("\nIniciando MaKi...")

    # Registrar las dos cámaras.
    # No se inicia ninguna captura automáticamente.

    camera_manager.add_camera("camera_1")
    camera_manager.add_camera("camera_2")

    print("Cámaras registradas.")
    print("Las cámaras están esperando configuración.")

    # Inicializar MediaPipe para ambas cámaras.
    print("Inicializando MediaPipe...")

    tracker_1 = HandTracker(
        model_path=MODEL_PATH,
        num_hands=1
    )

    tracker_2 = HandTracker(
        model_path=MODEL_PATH,
        num_hands=1
    )

    print("MediaPipe inicializado.")
    print("MaKi iniciado correctamente.\n")


# ==========================================
# APAGADO
# ==========================================

@app.on_event("shutdown")
async def shutdown():

    camera_manager.stop_all()

    if tracker_1 is not None:
        tracker_1.close()

    if tracker_2 is not None:
        tracker_2.close()

    cv2.destroyAllWindows()

    print("MaKi detenido.")


# ==========================================
# ESTADO DEL SERVIDOR
# ==========================================

@app.get("/health")
def health():

    elapsed = time.perf_counter() - server_start_time

    return {
        "status": "online",
        "message": "MaKi está funcionando.",
        "uptime_seconds": round(elapsed, 2)
    }


# ==========================================
# GESTIÓN DE DISPOSITIVOS
# ==========================================

@app.get("/devices")
def get_devices():

    return {
        "devices": camera_manager.get_all_status()
    }


@app.post("/devices/{camera_id}/configure")
def configure_camera(
    camera_id: str,
    config: CameraConfig
):

    if camera_id not in ("camera_1", "camera_2"):
        raise HTTPException(
            status_code=404,
            detail="Identificador de cámara no válido."
        )

    source = config.source.strip()

    if not source:
        raise HTTPException(
            status_code=400,
            detail="La dirección de la cámara está vacía."
        )

    try:
        camera_manager.configure_camera(
            camera_id,
            source
        )

        return {
            "success": True,
            "message": f"{camera_id} configurada correctamente.",
            "camera": camera_manager.get_status(camera_id)
        }

    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=str(error)
        )


@app.post("/devices/{camera_id}/check")
def check_camera(camera_id: str):

    if camera_id not in ("camera_1", "camera_2"):
        raise HTTPException(
            status_code=404,
            detail="Identificador de cámara no válido."
        )

    status = camera_manager.get_status(camera_id)

    if status is None:
        raise HTTPException(
            status_code=404,
            detail="Cámara no registrada."
        )

    # Si ya está capturando, no abrimos una segunda conexión.
    if status["streaming"]:
        return {
            "success": True,
            "available": True,
            "message": "La cámara ya está capturando."
        }

    available = camera_manager.check_camera(camera_id)

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

    for camera_id in ("camera_1", "camera_2"):

        status = camera_manager.get_status(camera_id)

        if status is None:
            results[camera_id] = False
            continue

        if status["streaming"]:
            results[camera_id] = True
        else:
            results[camera_id] = camera_manager.check_camera(
                camera_id
            )

    return {
        "success": True,
        "cameras": results,
        "all_available": all(results.values())
    }


@app.post("/devices/{camera_id}/start")
def start_camera(camera_id: str):

    if camera_id not in ("camera_1", "camera_2"):
        raise HTTPException(
            status_code=404,
            detail="Identificador de cámara no válido."
        )

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

    if camera_id not in ("camera_1", "camera_2"):
        raise HTTPException(
            status_code=404,
            detail="Identificador de cámara no válido."
        )

    camera_manager.stop_camera(camera_id)

    return {
        "success": True,
        "message": "Captura detenida."
    }


# ==========================================
# CONTROL DE CÁMARAS EN OPENCV
# ==========================================

def show_camera_1(frame):

    if frame is not None:
        cv2.imshow("MaKi - Camera 1", frame)
        camera_windows["camera_1"] = True


def show_camera_2(frame):

    if frame is not None:
        cv2.imshow("MaKi - Camera 2", frame)
        camera_windows["camera_2"] = True


def hide_cameras():

    cv2.destroyAllWindows()

    camera_windows["camera_1"] = False
    camera_windows["camera_2"] = False


# ==========================================
# CONTROL DE EJERCICIOS
# ==========================================

def start_exercise(exercise_name):

    global active_exercise

    exercise_name = EXERCISE_ALIASES.get(
        exercise_name,
        exercise_name
    )

    # Iniciar las cámaras que estén configuradas.
    camera_results = camera_manager.start_all()

    # Al menos una cámara debe iniciar correctamente.
    if not any(camera_results.values()):

        return {
            "success": False,
            "message": "No se pudo iniciar ninguna cámara.",
            "cameras": camera_results
        }

    try:

        exercise_manager.start_exercise(exercise_name)

        active_exercise = exercise_name

        print(f"Ejercicio iniciado: {exercise_name}")

        return {
            "success": True,
            "message": f"Ejercicio iniciado: {exercise_name}",
            "cameras": camera_results
        }

    except Exception as error:

        camera_manager.stop_all()

        return {
            "success": False,
            "message": str(error)
        }


def next_task():

    if hasattr(exercise_manager, "next_task"):

        exercise_manager.next_task()

        return {
            "success": True,
            "message": "Siguiente tarea."
        }

    current = getattr(
        exercise_manager,
        "current_exercise",
        None
    )

    if current is not None and hasattr(current, "next_task"):

        current.next_task()

        return {
            "success": True,
            "message": "Siguiente tarea."
        }

    return {
        "success": False,
        "message": "El ejercicio no tiene siguiente tarea configurada."
    }


def finish_exercise():

    global active_exercise

    results = exercise_manager.finish_exercise()

    finished_name = active_exercise
    active_exercise = None

    # Al finalizar el ejercicio, detener las cámaras.
    camera_manager.stop_all()

    hide_cameras()

    print(f"Ejercicio finalizado: {finished_name}")

    return {
        "exercise": finished_name,
        "results": results
    }


# ==========================================
# WEBSOCKET
# ==========================================

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):

    global active_exercise

    await websocket.accept()

    print("Flutter conectado.")

    receive_task = asyncio.create_task(
        websocket.receive_text()
    )

    try:

        while True:

            command_response = None
            finished_results = None

            # ----------------------------------
            # RECIBIR COMANDOS DE FLUTTER
            # ----------------------------------

            if receive_task.done():

                try:

                    message = receive_task.result()
                    command = json.loads(message)

                    action = command.get("command")

                    if action == "start_exercise":

                        exercise_name = command.get("exercise")

                        command_response = start_exercise(
                            exercise_name
                        )

                    elif action == "next_task":

                        command_response = next_task()

                    elif action == "finish_exercise":

                        finished_results = finish_exercise()

                        command_response = {
                            "success": True,
                            "message": "Ejercicio finalizado."
                        }

                    # --------------------------
                    # VISUALIZACIÓN DE CÁMARAS
                    # --------------------------

                    elif action == "show_camera_1":

                        camera_windows["camera_1"] = True
                        camera_windows["camera_2"] = False

                        command_response = {
                            "success": True,
                            "message": "Mostrando cámara 1."
                        }

                    elif action == "show_camera_2":

                        camera_windows["camera_1"] = False
                        camera_windows["camera_2"] = True

                        command_response = {
                            "success": True,
                            "message": "Mostrando cámara 2."
                        }

                    elif action == "show_both":

                        camera_windows["camera_1"] = True
                        camera_windows["camera_2"] = True

                        command_response = {
                            "success": True,
                            "message": "Mostrando ambas cámaras."
                        }

                    elif action == "hide_cameras":

                        hide_cameras()

                        command_response = {
                            "success": True,
                            "message": "Cámaras ocultas."
                        }

                except WebSocketDisconnect:
                    break

                except Exception as error:

                    print(f"Error procesando comando: {error}")

                    command_response = {
                        "success": False,
                        "message": str(error)
                    }

                receive_task = asyncio.create_task(
                    websocket.receive_text()
                )

            # ----------------------------------
            # CAPTURA Y PROCESAMIENTO
            # ----------------------------------

            frame_1 = camera_manager.get_frame("camera_1")
            frame_2 = camera_manager.get_frame("camera_2")

            hands_1 = []
            hands_2 = []

            display_frame_1 = None
            display_frame_2 = None

            elapsed = time.perf_counter() - server_start_time

            timestamp_ms = int(elapsed * 1000)

            # Procesar cámara 1.
            if frame_1 is not None and tracker_1 is not None:

                display_frame_1, hands_1 = tracker_1.process(
                    frame_1,
                    timestamp_ms
                )

            # Procesar cámara 2.
            if frame_2 is not None and tracker_2 is not None:

                display_frame_2, hands_2 = tracker_2.process(
                    frame_2,
                    timestamp_ms
                )

            # ----------------------------------
            # PROCESAMIENTO DEL EJERCICIO
            # ----------------------------------

            exercise_data = {}
            instruction = None

            # Por ahora, la cámara 1 es la referencia
            # para procesar los ejercicios.
            if active_exercise is not None and len(hands_1) > 0:

                result = exercise_manager.process_frame(
                    hands_1[0],
                    elapsed
                )

                if isinstance(result, dict):

                    exercise_data = result

                    instruction = result.get("instruction")

            # ----------------------------------
            # MOSTRAR CÁMARAS
            # ----------------------------------

            if camera_windows["camera_1"]:

                if display_frame_1 is not None:
                    show_camera_1(display_frame_1)

            if camera_windows["camera_2"]:

                if display_frame_2 is not None:
                    show_camera_2(display_frame_2)

            cv2.waitKey(1)

            # ----------------------------------
            # DATOS PARA FLUTTER
            # ----------------------------------

            payload = {
                "type": "measurement",

                "time": elapsed,

                "active_exercise": active_exercise,

                "instruction": instruction,

                "camera1": {
                    "detected": len(hands_1) > 0
                },

                "camera2": {
                    "detected": len(hands_2) > 0
                },

                "exercise_data": exercise_data,

                "command_response": command_response,

                "finished_results": finished_results
            }

            await websocket.send_text(
                json.dumps(payload)
            )

            await asyncio.sleep(0.02)

    except WebSocketDisconnect:

        print("Flutter desconectado.")

    except Exception as error:

        print(f"Error en WebSocket: {error}")

    finally:

        if not receive_task.done():
            receive_task.cancel()

        print("Conexión WebSocket cerrada.")
