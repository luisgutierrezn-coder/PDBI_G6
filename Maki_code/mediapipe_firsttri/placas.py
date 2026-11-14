import socket
import threading
import time
from collections import deque


PUERTO_ORDENES = 8766
PUERTO_BUSCAR = 8767
CODIGO_MAKI = "246810"


# ==================================================
# BUSCAR PLACAS EN LA RED (UDP)
# ==================================================

def _direcciones_broadcast():
    destinos = {"255.255.255.255"}

    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                destinos.add(ip.rsplit(".", 1)[0] + ".255")
    except OSError:
        pass

    return destinos


def buscar_placas(espera=1.5):
    encontradas = {}

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(0.25)

    try:
        s.bind(("", 0))

        for _ in range(2):
            for destino in _direcciones_broadcast():
                try:
                    s.sendto(b"MAKI_BUSCAR", (destino, PUERTO_BUSCAR))
                except OSError:
                    pass

        fin = time.time() + espera

        while time.time() < fin:
            try:
                datos, origen = s.recvfrom(256)
            except socket.timeout:
                continue

            texto = datos.decode(errors="replace").strip()

            if texto.startswith("MAKI,placa,"):
                encontradas[origen[0]] = {
                    "ip": origen[0],
                    "nombre": texto.split(",", 2)[2]
                }
    finally:
        s.close()

    return list(encontradas.values())


# ==================================================
# UNA PLACA CONECTADA (TCP)
# ==================================================

class PlacaMaki:

    def __init__(self, ip, camera_id=None, al_cambiar_video=None, codigo=CODIGO_MAKI):
        self.ip = ip
        self.camera_id = camera_id
        self.codigo = codigo
        self.al_cambiar_video = al_cambiar_video

        self.nombre = None
        self.canales = []
        self.video_url = None
        self.calibracion = {}
        self.ultimo_mv = None
        self.ultimo_error = None
        self.diagnostico = {}
        self.crudo = {}
        self.mensajes = deque(maxlen=60)
        self.mv = deque(maxlen=3000)

        self._sock = None
        self._hilo = None
        self._activa = False
        self._lock = threading.Lock()
        self._esperas = []
        self._video_listo = threading.Event()
        self._grabacion = None

    # ------------------------------------------
    # CONEXIÓN
    # ------------------------------------------

    def conectar(self, timeout=4):
        sock = socket.create_connection((self.ip, PUERTO_ORDENES), timeout=timeout)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.sendall(f"MAKI {self.codigo}\n".encode())

        sock.settimeout(timeout)
        buffer = b""

        while b"\n" not in buffer:
            trozo = sock.recv(256)
            if not trozo:
                break
            buffer += trozo

        linea, _, resto = buffer.partition(b"\n")
        linea = linea.decode(errors="replace").strip()

        if not linea.startswith("puente,ok"):
            sock.close()
            motivo = {
                "puente,clave": "código incorrecto",
                "puente,ocupado": "la placa ya tiene otra app conectada"
            }.get(linea, linea or "sin respuesta")
            raise ConnectionError(f"La placa {self.ip} rechazó la conexión: {motivo}.")

        self.nombre = linea.split(",", 2)[2] if linea.count(",") >= 2 else self.ip

        sock.settimeout(0.5)
        self._sock = sock
        self._activa = True
        self._hilo = threading.Thread(target=self._leer, args=(resto,), daemon=True)
        self._hilo.start()

        self.orden("HOLA", esperar=("hola,",))
        return self

    def cerrar(self):
        self._activa = False

        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

        if self._hilo is not None:
            self._hilo.join(timeout=2)
            self._hilo = None

    @property
    def conectada(self):
        return self._activa

    # ------------------------------------------
    # ÓRDENES
    # ------------------------------------------

    def enviar(self, texto):
        if not self._activa or self._sock is None:
            raise ConnectionError(f"La placa {self.ip} no está conectada.")
        self._sock.sendall((texto.strip() + "\n").encode())

    def orden(self, texto, esperar=("ok,", "error,"), timeout=3.0):
        evento = threading.Event()
        resultado = {}
        espera = (tuple(esperar), evento, resultado)

        with self._lock:
            self._esperas.append(espera)

        try:
            self.enviar(texto)
            evento.wait(timeout)
        finally:
            with self._lock:
                if espera in self._esperas:
                    self._esperas.remove(espera)

        return resultado.get("linea")

    # ------------------------------------------
    # VIDEO
    # ------------------------------------------

    def encender_video(self, timeout=5.0):
        if self.video_url:
            return self.video_url

        self._video_listo.clear()
        respuesta = self.orden("VIDEO ON", esperar=("ok,VIDEO", "error,"))

        if respuesta is None or respuesta.startswith("error"):
            return None

        self._video_listo.wait(timeout)

        # Si la cámara se volvió a encender muy rápido, la placa no repite el enlace.
        if self.video_url is None:
            self.video_url = f"http://{self.ip}/stream"

        return self.video_url

    def apagar_video(self):
        try:
            respuesta = self.orden("VIDEO OFF", esperar=("ok,VIDEO", "error,"))
        except ConnectionError:
            return

        if respuesta and respuesta.startswith("ok,VIDEO"):
            self.video_url = None

    # ------------------------------------------
    # LECTURA DE MENSAJES
    # ------------------------------------------

    def _leer(self, inicial=b""):
        buffer = inicial

        while self._activa:
            while b"\n" in buffer:
                linea, _, buffer = buffer.partition(b"\n")
                texto = linea.decode(errors="replace").strip()
                if texto:
                    self._procesar(texto)

            try:
                trozo = self._sock.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break

            if not trozo:
                break

            buffer += trozo

        self._activa = False
        self.video_url = None

    def _procesar(self, linea):
        partes = linea.split(",")
        tipo = partes[0]

        if tipo == "mv":
            try:
                self.ultimo_mv = {
                    "ms": int(partes[1]),
                    "valores": dict(zip(self.canales, map(float, partes[2:-1]))),
                    "sueltos": int(partes[-1]),
                    "t": time.time()
                }
                self.mv.append(self.ultimo_mv)
                if self._grabacion is not None:
                    self._grabacion.append((
                        self.ultimo_mv["t"],
                        self.ultimo_mv["ms"],
                        self.ultimo_mv["valores"],
                        self.ultimo_mv["sueltos"]
                    ))
            except (ValueError, IndexError):
                pass
        else:
            self.mensajes.append({"t": time.time(), "linea": linea})

        if tipo == "hola":
            self.canales = partes[2:]

        elif tipo == "video" and len(partes) >= 2:
            self.video_url = linea.split(",", 1)[1]
            self._video_listo.set()
            if self.al_cambiar_video:
                self.al_cambiar_video(self, self.video_url)

        elif tipo == "aviso" and partes[1:3] == ["video", "apagado"]:
            self.video_url = None

        elif tipo == "aviso" and len(partes) >= 2 and partes[1] in ("emg", "video_fps"):
            self.diagnostico[partes[1]] = partes[2:]

        elif tipo == "reposo" and len(partes) >= 4:
            self.calibracion.setdefault(partes[1], {}).update(
                reposo_mv=float(partes[2]),
                umbral_mv=float(partes[3])
            )

        elif tipo == "mvc" and len(partes) >= 5:
            self.calibracion.setdefault(partes[1], {}).update(
                mvc_mv=float(partes[2]),
                mvc_veces_reposo=float(partes[3]),
                calidad=partes[4]
            )

        elif tipo == "crudo" and len(partes) >= 4:
            try:
                self.crudo[partes[1]] = {
                    "nivel_mv": float(partes[2]),
                    "suelto": partes[3] == "1"
                }
            except ValueError:
                pass

        elif tipo == "error":
            self.ultimo_error = linea

        with self._lock:
            for prefijos, evento, resultado in self._esperas:
                if not evento.is_set() and linea.startswith(prefijos):
                    resultado["linea"] = linea
                    evento.set()

    # ------------------------------------------
    # ESTADO
    # ------------------------------------------

    # ------------------------------------------
    # GRABACIÓN DEL EMG DURANTE UN EJERCICIO
    # ------------------------------------------

    def iniciar_grabacion(self):
        self._grabacion = []

    def detener_grabacion(self):
        grabacion = self._grabacion or []
        self._grabacion = None
        return grabacion

    def revisar_electrodos(self, espera=0.4):
        self.crudo = {}
        self.enviar("CRUDO")
        time.sleep(espera)
        return dict(self.crudo)

    def estado(self):
        return {
            "ip": self.ip,
            "nombre": self.nombre,
            "conectada": self._activa,
            "camera_id": self.camera_id,
            "canales": self.canales,
            "video_url": self.video_url,
            "calibracion": self.calibracion,
            "ultimo_mv": self.ultimo_mv,
            "ultimo_error": self.ultimo_error,
            "diagnostico": self.diagnostico,
            "mensajes": [m["linea"] for m in list(self.mensajes)[-15:]]
        }


# ==================================================
# TODAS LAS PLACAS
# ==================================================

class GestorPlacas:

    def __init__(self, al_cambiar_video=None):
        self.placas = {}
        self.al_cambiar_video = al_cambiar_video

    def conectar(self, ip, camera_id=None):
        anterior = self.placas.pop(ip, None)
        if anterior is not None:
            anterior.cerrar()

        if camera_id:
            for placa in self.placas.values():
                if placa.camera_id == camera_id:
                    placa.camera_id = None

        placa = PlacaMaki(ip, camera_id, self.al_cambiar_video).conectar()
        self.placas[ip] = placa
        return placa

    def desconectar(self, ip):
        placa = self.placas.pop(ip, None)
        if placa is not None:
            placa.cerrar()

    def obtener(self, ip):
        placa = self.placas.get(ip)
        if placa is None or not placa.conectada:
            return None
        return placa

    def de_camara(self, camera_id):
        for placa in self.placas.values():
            if placa.camera_id == camera_id and placa.conectada:
                return placa
        return None

    def encender_video(self, camera_ids):
        urls = {}
        for camera_id in camera_ids:
            placa = self.de_camara(camera_id)
            if placa is not None:
                urls[camera_id] = placa.encender_video()
        return urls

    def apagar_video(self, camera_ids):
        for camera_id in camera_ids:
            placa = self.de_camara(camera_id)
            if placa is not None:
                placa.apagar_video()

    def estado(self):
        return [placa.estado() for placa in self.placas.values()]

    def cerrar_todas(self):
        for placa in list(self.placas.values()):
            placa.cerrar()
        self.placas.clear()
