"""MaKi · Evolución del EMG del paciente frente a su línea base.

Adaptado de MaKi_progreso (mejora.py y progreso.py):
  - valor de la sesión: el del ejercicio de esa sesión · línea base: sesiones 1 a 3
  - margen = 1.96 × σ × √(1 + 1/n); σ = el mayor entre el de sanos (GrabMyo) y el del propio paciente
  - "mejora" o "retroceso" solo si sale del margen dos sesiones seguidas ("posible ..." con una)
  - la activación se lee según el nivel (Hesam-Shariati et al., Front Neurol 2017;8:340):
    nivel bajo: activar más es mejora · medio_alto: solo se informa, decide la eficiencia
"""
import json
import os

import numpy as np

REFERENCIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "referencia_normal.json")
SESIONES_BASE = 3
Z = 1.96
SENAL_MIN_VECES = 5        # nivel bajo si el músculo no sube 5 veces su reposo (por confirmar con pacientes)

# sentido: +1 mayor es mejor · −1 menor es mejor · "nivel" depende del paciente
INDICADORES = {
    "activacion_cerrar_mv": {"nombre": "Activación de flexores al cerrar", "unidad": "mV",
                             "log": True, "sentido": "nivel", "sem_grabmyo": "amplitud_cerrar"},
    "activacion_cerrar_pct_mvc": {"nombre": "Fuerza usada al cerrar", "unidad": "% MVC",
                                  "log": False, "sentido": "nivel"},
    "eficiencia_cerrar": {"nombre": "Eficiencia al cerrar", "unidad": "° por % MVC",
                          "log": True, "sentido": 1},
    "cocontraccion_cerrar": {"nombre": "Co-contracción al cerrar", "unidad": "extensores / flexores",
                             "log": True, "sentido": -1, "sem_grabmyo": "cocontraccion_cerrar"},
    "inestabilidad_cerrar": {"nombre": "Variación de la fuerza al cerrar", "unidad": "CV",
                             "log": True, "sentido": -1, "sem_grabmyo": "inestabilidad_cerrar"},
    "reaccion_cerrar_s": {"nombre": "Tiempo de activación al cerrar", "unidad": "s",
                          "log": False, "sentido": -1},
    "activacion_pinza_mv": {"nombre": "Activación en la pinza", "unidad": "mV",
                            "log": True, "sentido": "nivel", "sem_grabmyo": "amplitud_pinza"},
    "activacion_pinza_pct_mvc": {"nombre": "Fuerza usada en la pinza", "unidad": "% MVC",
                                 "log": False, "sentido": "nivel"},
    "eficiencia_pinza": {"nombre": "Eficiencia en la pinza", "unidad": "excursión por % MVC",
                         "log": True, "sentido": 1},
    "inestabilidad_pinza": {"nombre": "Variación de la fuerza en la pinza", "unidad": "CV",
                            "log": True, "sentido": -1},
    "reaccion_pinza_s": {"nombre": "Tiempo de activación en la pinza", "unidad": "s",
                         "log": False, "sentido": -1},
}


def cargar_referencia(ruta=REFERENCIA):
    with open(ruta, encoding="utf-8") as f:
        return json.load(f)


def nivel(base):
    """base: lista de dicts (valores de las sesiones de la línea base). Devuelve (nivel, por qué)."""
    senal = []
    for clave in ("senal_cerrar_veces", "senal_pinza_veces"):
        v = [s[clave] for s in base if s.get(clave) is not None]
        if v:
            senal.append(float(np.median(v)))

    if not senal:
        return "sin_datos", "no hay datos de EMG en la línea base"

    if min(senal) < SENAL_MIN_VECES:
        return "bajo", f"el músculo sube {min(senal):.1f} veces su reposo (menos de {SENAL_MIN_VECES})"

    return "medio_alto", f"el músculo sube {min(senal):.1f} veces su reposo"


def _sentido(clave, niv):
    s = INDICADORES[clave]["sentido"]
    if s != "nivel":
        return s
    return 1 if niv == "bajo" else 0


def evolucion(sesiones, nivel_fijo=None, referencia=None):
    """sesiones: de la más antigua a la más nueva, cada una {"valores": {...}, "reps": {clave: [...]}}.

    Devuelve el nivel y, por indicador: serie, línea base, franja normal, cambio y estado.
    """
    referencia = referencia or cargar_referencia()
    valores = [s.get("valores") or {} for s in sesiones]
    # Línea base: las primeras sesiones que sí tienen EMG (puede haber sesiones solo con cámara)
    base = [v for v in valores if v][:SESIONES_BASE]

    niv, por_que = (nivel_fijo, "elegido por el terapeuta") if nivel_fijo else nivel(base)
    salida = {"nivel": niv, "nivel_por_que": por_que, "indicadores": {}}

    for clave, ind in INDICADORES.items():
        serie = [v.get(clave) for v in valores]
        puntos = [(i, x) for i, x in enumerate(serie) if x is not None and (x > 0 or not ind["log"])]

        if not puntos:
            continue

        ida = np.log if ind["log"] else (lambda x: x)
        vuelta = np.exp if ind["log"] else (lambda x: x)
        fila = {
            "nombre": ind["nombre"],
            "unidad": ind["unidad"],
            "serie": serie,
            "sentido": _sentido(clave, niv)
        }
        en_base = [float(ida(x)) for _, x in puntos[:SESIONES_BASE]]

        if len(puntos) <= SESIONES_BASE or not en_base:
            fila["estado"] = "armando línea base"
            salida["indicadores"][clave] = fila
            continue

        # Ruido propio: variación entre repeticiones de cada sesión (más conservador que entre tomas)
        propio = []
        for s in sesiones:
            reps = [float(ida(x)) for x in (s.get("reps") or {}).get(clave, []) if x is not None and (x > 0 or not ind["log"])]
            if len(reps) >= 2:
                propio.append((np.var(reps, ddof=1), len(reps) - 1))

        sigma_propio = (
            float(np.sqrt(sum(a * b for a, b in propio) / sum(b for _, b in propio)))
            if propio else 0.0
        )
        sem = referencia["indicadores"].get(ind.get("sem_grabmyo"), {}).get("sem", 0.0) if ind["log"] else 0.0
        sigma = max(sem, sigma_propio)
        linea = float(np.mean(en_base))
        fila["linea_base"] = float(vuelta(linea))

        if sigma == 0:
            fila["estado"] = "sin margen"
            salida["indicadores"][clave] = fila
            continue

        margen = Z * sigma * np.sqrt(1 + 1 / len(en_base))
        fila["franja"] = [float(vuelta(linea - margen)), float(vuelta(linea + margen))]
        fila["margen_origen"] = "sanos (GrabMyo)" if sem >= sigma_propio else "sus propias repeticiones (orientativo)"

        def fuera(x):
            d = ida(x) - linea
            return 0 if abs(d) <= margen else int(np.sign(d))

        ultimas = [x for _, x in puntos[-2:]]
        f_ult = fuera(ultimas[-1])
        f_ant = fuera(ultimas[0]) if len(ultimas) == 2 else 0
        d = float(ida(ultimas[-1]) - linea)

        if ind["log"]:
            fila["cambio"] = f"{'+' if d >= 0 else '−'}{abs(np.expm1(d) * 100):.0f}%"
        else:
            fila["cambio"] = f"{'+' if d >= 0 else '−'}{abs(d):.1f} {ind['unidad']}"

        s = fila["sentido"]
        if f_ult == 0:
            estado = "sin cambio claro"
        elif s == 0:
            estado = "subió" if f_ult > 0 else "bajó"
        else:
            bueno = f_ult * s > 0
            seguida = f_ant == f_ult
            if bueno:
                estado = "mejora" if seguida else "posible mejora"
            else:
                estado = "retroceso" if seguida else "posible retroceso"

        fila["estado"] = estado
        salida["indicadores"][clave] = fila

    return salida
