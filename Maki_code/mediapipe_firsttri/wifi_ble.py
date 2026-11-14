import asyncio
import re
import subprocess
import sys
import threading
import time


UUID_RED = "6d616b69-0002-4b1e-9a10-6d616b690001"
UUID_ESTADO = "6d616b69-0003-4b1e-9a10-6d616b690001"
PREFIJO_BLE = "MaKi"
TROZO_BLE = 18


# ==================================================
# RED WI-FI DE LA LAPTOP (WINDOWS)
# ==================================================

def _netsh(comando):
    if not sys.platform.startswith("win"):
        return ""

    resultado = subprocess.run(
        f"netsh wlan {comando}",
        capture_output=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)
    )

    for codificacion in ("utf-8", "cp850", "mbcs"):
        try:
            return resultado.stdout.decode(codificacion)
        except (UnicodeDecodeError, LookupError):
            continue

    return resultado.stdout.decode(errors="replace")


def _campo(texto, *nombres):
    for nombre in nombres:
        m = re.search(rf"^\s*{nombre}\s*:\s*(.+?)\s*$", texto, re.MULTILINE | re.IGNORECASE)
        if m:
            return m.group(1)
    return None


def red_de_la_laptop():
    interfaces = _netsh("show interfaces")
    ssid = _campo(interfaces, "SSID")

    if not ssid:
        return None

    canal = _campo(interfaces, "Channel", "Canal")
    banda_5ghz = canal is not None and canal.isdigit() and int(canal) > 14

    perfil = _netsh(f'show profile name="{ssid}" key=clear')
    clave = _campo(perfil, "Key Content", "Contenido de la clave", "Contenido de clave")

    return {
        "ssid": ssid,
        "clave": clave,
        "canal": canal,
        "banda_5ghz": banda_5ghz
    }


# ==================================================
# BLUETOOTH (bleak)
# ==================================================

def _bleak():
    try:
        import bleak
        return bleak
    except ImportError:
        raise RuntimeError(
            "Falta la librería de Bluetooth. Instálala con: pip install bleak"
        )


async def _buscar(espera):
    bleak = _bleak()
    dispositivos = await bleak.BleakScanner.discover(timeout=espera)

    return [
        {"address": d.address, "nombre": d.name}
        for d in dispositivos
        if (d.name or "").startswith(PREFIJO_BLE)
    ]


async def _configurar(address, ssid, clave, codigo, espera):
    bleak = _bleak()
    mensaje = f"MAKI\n{codigo}\n{ssid}\n{clave or ''}\nFIN\n".encode()

    async with bleak.BleakClient(address, timeout=15) as cliente:
        for i in range(0, len(mensaje), TROZO_BLE):
            await cliente.write_gatt_char(UUID_RED, mensaje[i:i + TROZO_BLE], response=True)

        fin = time.time() + espera
        ultimo = ""

        while time.time() < fin:
            try:
                ultimo = (await cliente.read_gatt_char(UUID_ESTADO)).decode(errors="replace")
            except Exception:
                # La placa apaga el Bluetooth unos segundos después de conectarse al Wi-Fi.
                return ultimo if ultimo.startswith("ok,") else "desconectada"

            if ultimo.startswith("ok,") or ultimo in ("error,codigo", "error,formato"):
                return ultimo

            await asyncio.sleep(0.7)

        return ultimo or "error,tiempo"


def _correr(funcion, *args):
    # bleak es asíncrono: se corre en un hilo propio por si ya hay un event loop activo.
    resultado = {}

    def hilo():
        try:
            resultado["valor"] = asyncio.run(funcion(*args))
        except Exception as error:
            resultado["error"] = error

    t = threading.Thread(target=hilo, daemon=True)
    t.start()
    t.join()

    if "error" in resultado:
        raise resultado["error"]

    return resultado["valor"]


def buscar_ble(espera=5.0):
    return _correr(_buscar, espera)


def configurar_wifi(address, ssid, clave, codigo, espera=25.0):
    return _correr(_configurar, address, ssid, clave, codigo, espera)
