
from statistics import mean, median, pstdev


FINGERS = (
    "thumb",
    "index",
    "middle",
    "ring",
    "pinky",
)

MIN_VALID_SAMPLES = 5


def calculate_reference_angles(baseline_samples):
    """
    Calcula el ángulo de referencia de cada dedo
    durante el posicionamiento inicial con la mano abierta.
    """

    valid_samples = [
        sample for sample in baseline_samples
        if sample and isinstance(sample, dict)
    ]

    reference = {}

    for finger in FINGERS:

        values = [
            sample[finger]
            for sample in valid_samples
            if sample.get(finger) is not None
        ]

        if len(values) < MIN_VALID_SAMPLES:
            return None

        reference[finger] = round(median(values), 2)

    return reference


def calculate_repetition_metrics(
    samples,
    baseline,
    frames_total=None,
    frames_valid=None
):
    """
    Calcula la excursión de flexión de cada dedo
    durante una repetición de cierre de puño.
    """

    if baseline is None:
        return {
            "valid": False,
            "reason": "Referencia no disponible"
        }

    if frames_total is None or frames_total <= 0:
        tracking_quality = 0.0
    else:
        tracking_quality = (
            (frames_valid or 0) / frames_total
        ) * 100

    valid_samples = [
        sample for sample in samples
        if sample and isinstance(sample, dict)
    ]

    if len(valid_samples) < MIN_VALID_SAMPLES:
        return {
            "valid": False,
            "reason": "Muestras insuficientes",
            "tracking_quality_pct": round(tracking_quality, 2),
            "samples_count": len(valid_samples),
        }

    finger_excursions = {}
    minimum_angles = {}

    for finger in FINGERS:

        values = [
            sample[finger]
            for sample in valid_samples
            if sample.get(finger) is not None
        ]

        if len(values) < MIN_VALID_SAMPLES:
            return {
                "valid": False,
                "reason": f"Muestras insuficientes para {finger}",
                "tracking_quality_pct": round(tracking_quality, 2),
                "samples_count": len(valid_samples),
            }

        minimum_angle = min(values)

        excursion = max(
            0.0,
            baseline[finger] - minimum_angle
        )

        minimum_angles[finger] = round(minimum_angle, 2)
        finger_excursions[finger] = round(excursion, 2)

    mean_excursion = mean(finger_excursions.values())

    return {
        "valid": True,
        "minimum_angles": minimum_angles,
        "finger_excursions": finger_excursions,
        "mean_flexion_excursion_deg": round(mean_excursion, 2),
        "tracking_quality_pct": round(tracking_quality, 2),
        "samples_count": len(valid_samples),
    }


def calculate_session_metrics(repetitions):
    """
    Resume las métricas de las repeticiones válidas.
    """

    valid_repetitions = [
        rep for rep in repetitions
        if rep and rep.get("valid")
    ]

    if not valid_repetitions:
        return {
            "valid_repetitions": 0,
            "mean_flexion_excursion_deg": 0.0,
            "consistency_cv_pct": None,
            "mean_tracking_quality_pct": 0.0,
            "mean_finger_excursions": {
                finger: 0.0 for finger in FINGERS
            },
        }

    repetition_values = [
        rep["mean_flexion_excursion_deg"]
        for rep in valid_repetitions
    ]

    overall_mean = mean(repetition_values)

    if len(repetition_values) > 1 and overall_mean != 0:
        consistency_cv = (
            pstdev(repetition_values) / abs(overall_mean)
        ) * 100
    else:
        consistency_cv = 0.0

    mean_finger_excursions = {}

    for finger in FINGERS:

        values = [
            rep["finger_excursions"][finger]
            for rep in valid_repetitions
        ]

        mean_finger_excursions[finger] = round(
            mean(values), 2
        )

    mean_tracking_quality = mean([
        rep["tracking_quality_pct"]
        for rep in valid_repetitions
    ])

    return {
        "valid_repetitions": len(valid_repetitions),
        "mean_flexion_excursion_deg": round(overall_mean, 2),
        "consistency_cv_pct": round(consistency_cv, 2),
        "mean_tracking_quality_pct": round(
            mean_tracking_quality, 2
        ),
        "mean_finger_excursions": mean_finger_excursions,
    }
