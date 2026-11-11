
import cv2
import threading
import time


class Camera:
    def __init__(self, camera_id, source=None):
        self.camera_id = camera_id
        self.source = source

        self.cap = None
        self.frame = None

        self.running = False
        self.connected = False

        self.lock = threading.Lock()
        self.thread = None

    # ------------------------------------------
    # CONFIGURACIÓN
    # ------------------------------------------

    def configure(self, source):
        """
        Guarda la fuente de video sin iniciar la captura.
        Puede ser un índice (0) o una URL (http://.../stream).
        """
        self.stop()
        self.source = source

        print(f"[{self.camera_id}] Fuente configurada: {source}")
        return True

    def is_configured(self):
        return self.source is not None and self.source != ""

    # ------------------------------------------
    # COMPROBAR CONEXIÓN
    # ------------------------------------------

    def check_connection(self):
        """
        Comprueba si la cámara puede entregar imágenes.
        Abre el stream temporalmente y lo cierra al terminar.
        No deja la cámara transmitiendo.
        """

        if not self.is_configured():
            print(f"[{self.camera_id}] No hay una fuente configurada.")
            return False

        if isinstance(self.source, str) and self.source.startswith("http"):
            test_cap = cv2.VideoCapture(self.source, cv2.CAP_FFMPEG)
        else:
            test_cap = cv2.VideoCapture(self.source)
        
        test_cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        success = False

        try:
            if test_cap.isOpened():
                # Algunos streams necesitan unos instantes
                # antes de entregar el primer frame.
                for _ in range(10):
                    ret, frame = test_cap.read()

                    if ret and frame is not None:
                        success = True
                        break

                    time.sleep(0.2)

        finally:
            test_cap.release()

        print(
            f"[{self.camera_id}] "
            f"{'Conexión verificada.' if success else 'No se pudo verificar la conexión.'}"
        )

        return success

    # ------------------------------------------
    # INICIAR CAPTURA
    # ------------------------------------------

    
    def start(self):
        """
        Inicia la captura continua.
        Se utiliza al comenzar una sesión de rehabilitación.
        """

        if self.running:
            return True

        if not self.is_configured():
            print(f"[{self.camera_id}] No hay una fuente configurada.")
            return False

        try:
            if isinstance(self.source, str) and self.source.startswith("http"):
                self.cap = cv2.VideoCapture(self.source, cv2.CAP_FFMPEG)
            else:
                self.cap = cv2.VideoCapture(self.source)

            self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

            if not self.cap.isOpened():
                print(f"[{self.camera_id}] No se pudo iniciar la captura.")
                self.cap.release()
                self.cap = None
                self.connected = False
                return False

            self.connected = True
            self.running = True

            self.thread = threading.Thread(
                target=self._capture_loop,
                daemon=True
            )
            self.thread.start()

            print(f"[{self.camera_id}] Captura iniciada.")
            return True

        except Exception as error:
            print(f"[{self.camera_id}] Error al iniciar: {error}")

            if self.cap is not None:
                self.cap.release()
                self.cap = None

            self.connected = False
            self.running = False
            return False


    def _capture_loop(self):
        while self.running:
            if self.cap is None:
                break

            ret, frame = self.cap.read()

            if not ret or frame is None:
                time.sleep(0.01)
                continue

            with self.lock:
                self.frame = frame

    # ------------------------------------------
    # OBTENER IMÁGENES
    # ------------------------------------------

    def get_frame(self):
        with self.lock:
            if self.frame is None:
                return None

            return self.frame.copy()

    # ------------------------------------------
    # ESTADO
    # ------------------------------------------

    def get_status(self):
        return {
            "id": self.camera_id,
            "configured": self.is_configured(),
            "connected": self.connected,
            "streaming": self.running,
            "source": str(self.source) if self.source is not None else None
        }

    # ------------------------------------------
    # DETENER / DESCONECTAR
    # ------------------------------------------

    def stop(self):
        """
        Detiene la captura, pero conserva la configuración.
        """

        self.running = False

        if self.thread is not None:
            self.thread.join(timeout=2)

        if self.cap is not None:
            self.cap.release()
            self.cap = None

        if self.thread is not None:
            self.thread = None

        self.connected = False

        with self.lock:
            self.frame = None

        print(f"[{self.camera_id}] Captura detenida.")

    def disconnect(self):
        """
        Detiene la captura y elimina la fuente configurada.
        """

        self.stop()
        self.source = None

        print(f"[{self.camera_id}] Cámara desconectada.")


# ==============================================
# CAMERA MANAGER
# ==============================================

class CameraManager:

    def __init__(self):
        self.cameras = {}

    def add_camera(self, camera_id, source=None):
        if camera_id in self.cameras:
            raise ValueError(
                f"La cámara {camera_id} ya está registrada."
            )

        self.cameras[camera_id] = Camera(camera_id, source)

    def configure_camera(self, camera_id, source):
        camera = self.cameras[camera_id]
        return camera.configure(source)

    def check_camera(self, camera_id):
        camera = self.cameras[camera_id]
        return camera.check_connection()

    def start_camera(self, camera_id):
        camera = self.cameras[camera_id]
        return camera.start()

    def stop_camera(self, camera_id):
        camera = self.cameras[camera_id]
        camera.stop()

    def disconnect_camera(self, camera_id):
        camera = self.cameras[camera_id]
        camera.disconnect()

    def get_frame(self, camera_id):
        camera = self.cameras[camera_id]
        return camera.get_frame()

    def get_status(self, camera_id):
        camera = self.cameras[camera_id]
        return camera.get_status()

    def stop_all(self):
        for camera in self.cameras.values():
            camera.stop()

    
    def get_all_status(self):
        return {
            camera_id: camera.get_status()
            for camera_id, camera in self.cameras.items()
        }

    def start_all(self):
        results = {}

        for camera_id, camera in self.cameras.items():
            if camera.is_configured():
                results[camera_id] = camera.start()
            else:
                results[camera_id] = False

        return results
