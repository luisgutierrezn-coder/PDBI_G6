import numpy as np
from scipy.signal import lfilter


# ==========================================================
# CADENA DEL FIRMWARE (para cuando la placa envíe el ADC crudo)
# ==========================================================

FS = 1000
ALFA_OFFSET = 0.001
ALFA_RMS = 0.01
ALFA_LENTO = 0.004
MUESTRAS_OFFSET = 200

PASA_ALTOS_20 = (np.array([0.91496843, -1.82993686, 0.91496843]),
                 np.array([1, -1.82269350, 0.83718022]))
NOTCH_60 = (np.array([0.96449459, -1.79352877, 0.96449459]),
            np.array([1, -1.79352877, 0.92898917]))


def cadena_esp32(x_mV, notch=NOTCH_60):
    """Lo mismo que el loop del firmware con una señal a 1 kHz. Devuelve (rms, rms_lento)."""
    x = np.asarray(x_mV, dtype=float)
    offset0 = x[:MUESTRAS_OFFSET].mean()
    offset, _ = lfilter([ALFA_OFFSET], [1, ALFA_OFFSET - 1], x, zi=[(1 - ALFA_OFFSET) * offset0])
    emg = lfilter(*notch, lfilter(*PASA_ALTOS_20, x - offset))
    cuad = emg * emg
    media2 = lfilter([ALFA_RMS], [1, ALFA_RMS - 1], cuad)
    media2_lenta = lfilter([ALFA_LENTO], [1, ALFA_LENTO - 1], cuad)
    return np.sqrt(media2), np.sqrt(media2_lenta)


# ==========================================================
# CONFIGURACIÓN
# ==========================================================

EJERCICIOS_EMG = {
    "full_fist": {
        "gesto": "cerrar",
        "principal": ("flexores",),
        "antagonista": "extensores",
        "movimiento": "mean_flexion_excursion_deg"
    },
    "pinch_index": {
        "gesto": "pinza",
        "principal": ("muneca", "flexores"),
        "antagonista": None,
        "movimiento": "pinch_excursion"
    }
}

MIN_MUESTRAS = 5
SUELTO_MAX = 0.2          # más del 20 % del tramo con electrodo suelto: la repetición no cuenta
VECES_ACTIVO = 2          # como el firmware: activo si supera 2 veces el reposo


def ventana_estable(duracion):
    """MaKi_progreso usa de 1 a 4 s en repeticiones de 5 s: se descarta el primer y el último segundo."""
    if duracion >= 3:
        return 1.0, duracion - 1.0
    return 0.2 * duracion, 0.9 * duracion


# ==========================================================
# SEÑAL GRABADA
# ==========================================================

def series_por_canal(datos_placas):
    """datos_placas: {ip: {"canales", "muestras": [(t_recibido, ms, {canal: mV}, sueltos)], "calibracion"}}.

    Cada placa tiene su propio reloj (ms). Se pasa al reloj de la laptop con el menor desfase visto,
    así los datos que llegan en ráfagas por Wi-Fi quedan otra vez cada 20 ms.
    """
    series, calibracion = {}, {}

    for placa in datos_placas.values():
        muestras = placa.get("muestras") or []
        calibracion.update(placa.get("calibracion") or {})

        if not muestras:
            continue

        recibido = np.array([m[0] for m in muestras], dtype=float)
        ms = np.array([m[1] for m in muestras], dtype=float) / 1000.0
        t = ms + np.min(recibido - ms)
        sueltos = np.array([m[3] for m in muestras], dtype=float)

        for canal in placa.get("canales", []):
            valores = np.array([m[2].get(canal, np.nan) for m in muestras], dtype=float)
            series[canal] = (t, valores, sueltos)

    return series, calibracion


def _tramo(serie, inicio, fin):
    t, v, sueltos = serie
    sel = (t >= inicio) & (t < fin) & np.isfinite(v)
    return v[sel], sueltos[sel], t[sel]


# ==========================================================
# MÉTRICAS POR REPETICIÓN
# ==========================================================

def metricas_repeticion(series, segmento, principal, antagonista, reposo, umbral, mvc):
    duracion = segmento["fin"] - segmento["inicio"]
    v0, v1 = ventana_estable(duracion)
    v, sueltos, _ = _tramo(series[principal], segmento["inicio"] + v0, segmento["inicio"] + v1)

    if len(v) < MIN_MUESTRAS:
        return {"valid": False, "motivo": "pocas muestras de EMG"}

    if np.mean(sueltos > 0) > SUELTO_MAX:
        return {"valid": False, "motivo": "electrodo suelto"}

    amplitud = float(np.mean(v))

    r = {
        "valid": True,
        "amplitud_mv": round(amplitud, 2),
        "cv": round(float(np.std(v) / amplitud), 4) if amplitud > 0 else None,
        "veces_reposo": round(amplitud / reposo, 2) if reposo else None,
        "activo": bool(reposo and amplitud >= VECES_ACTIVO * reposo),
        "pct_mvc": None,
        "t_activacion_s": None,
        "antagonista_mv": None
    }

    if mvc and reposo is not None and mvc > reposo:
        r["pct_mvc"] = round(max(amplitud - reposo, 0) / (mvc - reposo) * 100, 1)

    # Tiempo desde que empieza la fase hasta que el músculo pasa su umbral (toda la fase)
    if umbral:
        todo, _, t = _tramo(series[principal], segmento["inicio"], segmento["fin"])
        arriba = np.flatnonzero(todo > umbral)
        if arriba.size:
            r["t_activacion_s"] = round(float(t[arriba[0]] - segmento["inicio"]), 2)

    if antagonista and antagonista in series:
        va, _, _ = _tramo(series[antagonista], segmento["inicio"] + v0, segmento["inicio"] + v1)
        if len(va) >= MIN_MUESTRAS:
            r["antagonista_mv"] = round(float(np.mean(va)), 2)

    return r


def _mediana(valores):
    v = [x for x in valores if x is not None and np.isfinite(x)]
    return float(np.median(v)) if v else None


def _redondo(v, n=2):
    return round(v, n) if v is not None else None


# ==========================================================
# MÉTRICAS DEL EJERCICIO
# ==========================================================

def calcular(exercise, datos_placas, segmentos, movimiento_por_rep=None):
    """Métricas de EMG de un ejercicio completo.

    segmentos: [{"fase": "posicionamiento"|"ejecucion", "rep": n, "inicio": t, "fin": t}] (reloj de la laptop)
    movimiento_por_rep: {n: movimiento de la cámara en esa repetición}, para la eficiencia.
    """
    cfg = EJERCICIOS_EMG.get(exercise)

    if cfg is None:
        return {"disponible": False, "motivo": "ejercicio sin métricas de EMG por ahora"}

    series, calibracion = series_por_canal(datos_placas)
    principal = next((c for c in cfg["principal"] if c in series), None)

    if principal is None:
        return {"disponible": False, "motivo": "no hay datos del canal necesario"}

    segmentos = [s for s in segmentos if s.get("fin") is not None]
    cal = calibracion.get(principal, {})
    reposo, umbral, mvc = cal.get("reposo_mv"), cal.get("umbral_mv"), cal.get("mvc_mv")
    origen = "calibracion"

    if not reposo:
        # Sin calibración: el reposo sale del posicionamiento (mano relajada)
        medias = []
        for s in segmentos:
            if s["fase"] == "posicionamiento":
                v, _, _ = _tramo(series[principal], s["inicio"], s["fin"])
                if len(v) >= MIN_MUESTRAS:
                    medias.append(float(np.mean(v)))
        reposo = _mediana(medias)
        umbral = VECES_ACTIVO * reposo if reposo else None
        mvc = None
        origen = "posicionamiento"

    movimiento_por_rep = movimiento_por_rep or {}
    repeticiones = []

    for s in segmentos:
        if s["fase"] != "ejecucion":
            continue

        r = metricas_repeticion(series, s, principal, cfg["antagonista"], reposo, umbral, mvc)
        r["numero"] = s["rep"]

        movimiento = movimiento_por_rep.get(s["rep"])
        if r["valid"] and movimiento is not None and r.get("pct_mvc"):
            r["eficiencia"] = round(movimiento / r["pct_mvc"], 4)

        repeticiones.append(r)

    validas = [r for r in repeticiones if r["valid"]]
    activas = [r for r in validas if r["activo"]]
    gesto = cfg["gesto"]

    resumen = {
        "gesto": gesto,
        "canal": principal,
        "repeticiones_validas": len(validas),
        "repeticiones_activas": len(activas),
        "reposo_mv": _redondo(reposo),
        "mvc_mv": _redondo(mvc),
        "origen_reposo": origen,
        "senal_veces_reposo": _redondo(_mediana([r["veces_reposo"] for r in validas])),
        # Como MaKi_progreso: un gesto que no llega a 2 veces el reposo no cuenta como activación
        "activacion_mv": _redondo(_mediana([r["amplitud_mv"] for r in activas])),
        "activacion_pct_mvc": _redondo(_mediana([r["pct_mvc"] for r in activas]), 1),
        "inestabilidad": _redondo(_mediana([r["cv"] for r in activas]), 4),
        "reaccion_s": _redondo(_mediana([r["t_activacion_s"] for r in activas])),
        "eficiencia": _redondo(_mediana([r.get("eficiencia") for r in activas]), 4),
        "cocontraccion": None
    }

    if cfg["antagonista"]:
        cociente = [
            r["antagonista_mv"] / r["amplitud_mv"]
            for r in activas
            if r.get("antagonista_mv") is not None and r["amplitud_mv"] > 0
        ]
        resumen["cocontraccion"] = _redondo(_mediana(cociente), 4)

    return {
        "disponible": True,
        "repeticiones": repeticiones,
        "resumen": resumen
    }


def indicadores(resultado_emg):
    """Pasa el resumen de un ejercicio a los nombres de indicador de la evolución (emg_progreso.py),
    junto con los valores por repetición (para el ruido propio del paciente)."""
    if not resultado_emg or not resultado_emg.get("disponible"):
        return {}, {}

    r = resultado_emg["resumen"]
    g = r["gesto"]
    activas = [x for x in resultado_emg["repeticiones"] if x.get("valid") and x.get("activo")]

    valores = {
        f"activacion_{g}_mv": r["activacion_mv"],
        f"activacion_{g}_pct_mvc": r["activacion_pct_mvc"],
        f"inestabilidad_{g}": r["inestabilidad"],
        f"eficiencia_{g}": r["eficiencia"],
        f"reaccion_{g}_s": r["reaccion_s"],
        f"senal_{g}_veces": r["senal_veces_reposo"]
    }
    por_rep = {
        f"activacion_{g}_mv": [x["amplitud_mv"] for x in activas],
        f"activacion_{g}_pct_mvc": [x["pct_mvc"] for x in activas],
        f"inestabilidad_{g}": [x["cv"] for x in activas],
        f"eficiencia_{g}": [x.get("eficiencia") for x in activas],
        f"reaccion_{g}_s": [x["t_activacion_s"] for x in activas]
    }

    if r.get("cocontraccion") is not None:
        valores[f"cocontraccion_{g}"] = r["cocontraccion"]
        por_rep[f"cocontraccion_{g}"] = [
            x["antagonista_mv"] / x["amplitud_mv"]
            for x in activas
            if x.get("antagonista_mv") is not None and x["amplitud_mv"] > 0
        ]

    valores = {k: v for k, v in valores.items() if v is not None}
    por_rep = {k: [x for x in v if x is not None] for k, v in por_rep.items()}
    return valores, por_rep
