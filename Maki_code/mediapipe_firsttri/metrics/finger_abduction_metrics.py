
from statistics import mean, median, pstdev


ABDUCTION_CHANNELS = (
    "thumb_index",
    "index_middle",
    "middle_ring",
    "ring_pinky",
)

MIN_VALID_SAMPLES = 5


def calculate_reference_abduction(baseline_samples):
    """
    Calcula la referencia de separación de cada par de dedos
    durante el posicionamiento inicial.
    """

    valid_samples = [
        sample for sample in baseline_samples
        if sample
        and isinstance(sample.get("normalized"), dict)
        and sample.get("global_opening") is not None
    ]

    if len(valid_samples) < MIN_VALID_SAMPLES:
        return None

    reference = {}

    for channel in ABDUCTION_CHANNELS:
        values = [
            sample["normalized"][channel]
            for sample in valid_samples
            if channel in sample["normalized"]
        ]

        if len(values) < MIN_VALID_SAMPLES:
            return None

        reference[channel] = round(median(values), 4)

    global_values = [
        sample["global_opening"]
        for sample in valid_samples
    ]

    reference["global_opening"] = round(
        median(global_values), 4
    )

    return reference


def calculate_repetition_metrics(
    samples,
    baseline,
    frames_total=None,
    frames_valid=None
):
    """
    Calcula la apertura máxima alcanzada durante una repetición,
    respecto a la posición inicial de los dedos juntos.
    """

    if baseline is None:
        return {"valid": False, "reason": "Referencia no disponible"}

    if frames_total is None or frames_total <= 0:
        tracking_quality = 0.0
    else:
        valid_count = frames_valid or 0
        tracking_quality = (
            valid_count / frames_total
        ) * 100

    valid_samples = [
        sample for sample in samples
        if sample
        and isinstance(sample.get("normalized"), dict)
        and sample.get("global_opening") is not None
    ]

    if len(valid_samples) < MIN_VALID_SAMPLES:
        return {
            "valid": False,
            "reason": "Muestras insuficientes",
            "tracking_quality_pct": round(tracking_quality, 2),
            "samples_count": len(valid_samples),
        }

    valid_samples.sort(
        key=lambda sample: sample.get("timestamp", 0)
    )

    pair_excursions = {}

    for channel in ABDUCTION_CHANNELS:
        values = [
            sample["normalized"][channel]
            for sample in valid_samples
            if channel in sample["normalized"]
        ]

        if len(values) < MIN_VALID_SAMPLES:
            return {
                "valid": False,
                "reason": f"Muestras insuficientes para {channel}",
                "tracking_quality_pct": round(tracking_quality, 2),
                "samples_count": len(valid_samples),
            }

        excursion = max(
            0.0,
            max(values) - baseline[channel]
        )

        pair_excursions[channel] = round(excursion, 4)

    global_values = [
        sample["global_opening"]
        for sample in valid_samples
    ]

    global_excursion = max(
        0.0,
        max(global_values) - baseline["global_opening"]
    )

    return {
        "valid": True,
        "global_opening_excursion": round(global_excursion, 4),
        "pair_excursions": pair_excursions,
        "tracking_quality_pct": round(tracking_quality, 2),
        "samples_count": len(valid_samples),
    }


def calculate_session_metrics(repetitions):
    """
    Resume los resultados de las repeticiones válidas.
    """

    valid_repetitions = [
        rep for rep in repetitions
        if rep and rep.get("valid")
    ]

    if not valid_repetitions:
        return {
            "valid_repetitions": 0,
            "mean_global_opening_excursion": 0.0,
            "consistency_cv_pct": None,
            "mean_tracking_quality_pct": 0.0,
            "mean_pair_excursions": {
                channel: 0.0
                for channel in ABDUCTION_CHANNELS
            },
        }

    global_values = [
        rep["global_opening_excursion"]
        for rep in valid_repetitions
    ]

    global_mean = mean(global_values)

    if len(global_values) > 1 and global_mean != 0:
        consistency_cv = (
            pstdev(global_values) / abs(global_mean)
        ) * 100
    else:
        consistency_cv = 0.0

    mean_pair_excursions = {}

    for channel in ABDUCTION_CHANNELS:
        values = [
            rep["pair_excursions"][channel]
            for rep in valid_repetitions
        ]

        mean_pair_excursions[channel] = round(
            mean(values), 4
        )

    mean_tracking_quality = mean([
        rep["tracking_quality_pct"]
        for rep in valid_repetitions
    ])

    return {
        "valid_repetitions": len(valid_repetitions),
        "mean_global_opening_excursion": round(global_mean, 4),
        "consistency_cv_pct": round(consistency_cv, 2),
        "mean_tracking_quality_pct": round(
            mean_tracking_quality, 2
        ),
        "mean_pair_excursions": mean_pair_excursions,
    }
