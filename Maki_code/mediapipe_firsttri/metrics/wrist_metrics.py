
import math
from statistics import mean, median, pstdev


# ==========================================================
# CONFIGURACIÓN
# ==========================================================

# Signo que representa la flexión.
#
# +1: la flexión produce desviaciones angulares positivas.
# -1: la flexión produce desviaciones angulares negativas.
#
# Este valor deberá verificarse experimentalmente según
# la posición de la webcam y la orientación de la mano.

FLEXION_SIGN = 1

MIN_VALID_SAMPLES = 5


# ==========================================================
# FUNCIONES AUXILIARES
# ==========================================================

def angular_difference(angle, reference):
    """
    Calcula la diferencia angular entre dos ángulos.

    El resultado está comprendido entre -180 y 180 grados.
    """

    return (angle - reference + 180) % 360 - 180


def calculate_reference_angle(baseline_samples):
    """
    Calcula el ángulo de referencia utilizando el promedio
    circular de los ángulos registrados durante el
    posicionamiento inicial.
    """

    valid_angles = [
        sample
        for sample in baseline_samples
        if sample is not None
    ]

    if len(valid_angles) < MIN_VALID_SAMPLES:
        return None

    sin_mean = mean(
        math.sin(math.radians(angle))
        for angle in valid_angles
    )

    cos_mean = mean(
        math.cos(math.radians(angle))
        for angle in valid_angles
    )

    if abs(sin_mean) < 1e-10 and abs(cos_mean) < 1e-10:
        return None

    reference = math.degrees(
        math.atan2(sin_mean, cos_mean)
    )

    return reference


# ==========================================================
# MÉTRICAS POR REPETICIÓN
# ==========================================================

def calculate_repetition_metrics(
    samples,
    baseline_samples,
    frames_total=None,
    frames_valid=None
):
    """
    Calcula las métricas de una repetición de movimiento
    de muñeca.

    Parámetros
    ----------
    samples:
        Lista de diccionarios:

        {
            "timestamp": 0.25,
            "hand_angle_deg": 42.5
        }

    baseline_samples:
        Lista de ángulos registrados durante
        el posicionamiento inicial.

    frames_total:
        Total de fotogramas capturados durante
        la ejecución.

    frames_valid:
        Fotogramas donde se detectó correctamente
        la mano y se calculó su orientación.
    """

    if frames_total is None:
        frames_total = len(samples)

    if frames_valid is None:
        frames_valid = len(samples)

    tracking_quality = (
        frames_valid / frames_total * 100
        if frames_total > 0 else 0
    )

    # ----------------------------------------------
    # Referencia inicial
    # ----------------------------------------------

    reference_angle = calculate_reference_angle(
        baseline_samples
    )

    if reference_angle is None:
        return {
            "valid": False,
            "message": "Datos insuficientes para establecer la referencia",
            "samples_count": 0,
            "tracking_quality_pct": round(tracking_quality, 2)
        }

    # ----------------------------------------------
    # Filtrar muestras válidas
    # ----------------------------------------------

    valid_samples = [
        sample
        for sample in samples
        if sample.get("hand_angle_deg") is not None
        and sample.get("timestamp") is not None
    ]

    valid_samples.sort(
        key=lambda sample: sample["timestamp"]
    )

    if len(valid_samples) < MIN_VALID_SAMPLES:
        return {
            "valid": False,
            "message": "Datos insuficientes durante la repetición",
            "samples_count": len(valid_samples),
            "reference_angle_deg": round(reference_angle, 2),
            "tracking_quality_pct": round(tracking_quality, 2)
        }

    # ----------------------------------------------
    # Desviaciones respecto al ángulo de referencia
    # ----------------------------------------------

    deviations = []

    for sample in valid_samples:

        deviation = angular_difference(
            sample["hand_angle_deg"],
            reference_angle
        )

        deviations.append(deviation)

    # ----------------------------------------------
    # Excursiones angulares
    # ----------------------------------------------

    max_deviation = max(deviations)
    min_deviation = min(deviations)

    # El signo de flexión debe verificarse
    # experimentalmente para la configuración utilizada.

    flexion_values = [
        deviation * FLEXION_SIGN
        for deviation in deviations
    ]

    flexion_excursion = max(
        0,
        max(flexion_values)
    )

    extension_excursion = max(
        0,
        -min(flexion_values)
    )

    projected_rom = (
        max_deviation - min_deviation
    )

    # ----------------------------------------------
    # Ángulo medio respecto a la referencia
    # ----------------------------------------------

    mean_absolute_deviation = mean(
        abs(value)
        for value in deviations
    )

    # ----------------------------------------------
    # Resultados
    # ----------------------------------------------

    return {
        "valid": True,

        "reference_angle_deg": round(
            reference_angle, 2
        ),

        "flexion_excursion_deg": round(
            flexion_excursion, 2
        ),

        "extension_excursion_deg": round(
            extension_excursion, 2
        ),

        "projected_rom_deg": round(
            projected_rom, 2
        ),

        "mean_absolute_deviation_deg": round(
            mean_absolute_deviation, 2
        ),

        "tracking_quality_pct": round(
            tracking_quality, 2
        ),

        "samples_count": len(valid_samples)
    }


# ==========================================================
# MÉTRICAS DE SESIÓN
# ==========================================================

def calculate_session_metrics(repetitions):
    """
    Calcula las métricas globales de una sesión
    de movimiento de muñeca.
    """

    valid_repetitions = [
        rep
        for rep in repetitions
        if rep.get("valid", False)
    ]

    if not valid_repetitions:
        return {
            "valid_repetitions": 0,
            "mean_projected_rom_deg": None,
            "consistency_cv_pct": None,
            "mean_flexion_excursion_deg": None,
            "mean_extension_excursion_deg": None,
            "mean_tracking_quality_pct": None
        }

    # ----------------------------------------------
    # Rango angular proyectado
    # ----------------------------------------------

    rom_values = [
        rep["projected_rom_deg"]
        for rep in valid_repetitions
    ]

    mean_rom = mean(rom_values)

    # ----------------------------------------------
    # Consistencia entre repeticiones
    # ----------------------------------------------

    if len(rom_values) >= 2 and mean_rom > 1e-6:

        std_rom = pstdev(rom_values)

        consistency_cv = (
            std_rom / mean_rom
        ) * 100

    else:
        consistency_cv = None

    # ----------------------------------------------
    # Excursiones de flexión y extensión
    # ----------------------------------------------

    flexion_values = [
        rep["flexion_excursion_deg"]
        for rep in valid_repetitions
    ]

    extension_values = [
        rep["extension_excursion_deg"]
        for rep in valid_repetitions
    ]

    tracking_values = [
        rep["tracking_quality_pct"]
        for rep in valid_repetitions
    ]

    # ----------------------------------------------
    # Resultados globales
    # ----------------------------------------------

    return {
        "valid_repetitions": len(valid_repetitions),

        "mean_projected_rom_deg": round(
            mean_rom, 2
        ),

        "consistency_cv_pct": (
            round(consistency_cv, 2)
            if consistency_cv is not None
            else None
        ),

        "mean_flexion_excursion_deg": round(
            mean(flexion_values), 2
        ),

        "mean_extension_excursion_deg": round(
            mean(extension_values), 2
        ),

        "mean_tracking_quality_pct": round(
            mean(tracking_values), 2
        )
    }
