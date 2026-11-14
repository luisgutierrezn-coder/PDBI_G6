
from statistics import median, mean, pstdev
from math import sqrt


FINGERS = ("middle", "ring", "pinky")


def calculate_normalized_jerk(samples, excursion):
    """
    Calcula el Normalized Jerk de la distancia pulgar-índice.

    Menor valor = movimiento más fluido.
    Se aplica un suavizado de 3 muestras antes de derivar.
    """

    valid = [
        s for s in samples
        if s.get("pinch_distance") is not None
        and s.get("timestamp") is not None
    ]

    if len(valid) < 7 or excursion <= 1e-6:
        return None

    # Ordenar por tiempo
    valid = sorted(valid, key=lambda s: s["timestamp"])

    times = [float(s["timestamp"]) for s in valid]
    values = [float(s["pinch_distance"]) for s in valid]

    # Comprobar tiempos válidos
    if any(times[i] <= times[i - 1] for i in range(1, len(times))):
        return None

    duration = times[-1] - times[0]

    if duration <= 0:
        return None

    # Suavizado mediante promedio móvil de 3 puntos
    smooth_values = [
        mean(values[i - 1:i + 2])
        for i in range(1, len(values) - 1)
    ]

    smooth_times = [
        times[i]
        for i in range(1, len(times) - 1)
    ]

    # Velocidad entre muestras consecutivas
    velocities = []
    velocity_times = []

    for i in range(1, len(smooth_values)):
        dt = smooth_times[i] - smooth_times[i - 1]

        if dt <= 0:
            continue

        velocity = (
            smooth_values[i] - smooth_values[i - 1]
        ) / dt

        velocities.append(velocity)
        velocity_times.append(
            (smooth_times[i] + smooth_times[i - 1]) / 2
        )

    if len(velocities) < 3:
        return None

    # Aceleración
    accelerations = []
    acceleration_times = []

    for i in range(1, len(velocities)):
        dt = velocity_times[i] - velocity_times[i - 1]

        if dt <= 0:
            continue

        acceleration = (
            velocities[i] - velocities[i - 1]
        ) / dt

        accelerations.append(acceleration)
        acceleration_times.append(
            (velocity_times[i] + velocity_times[i - 1]) / 2
        )

    if len(accelerations) < 2:
        return None

    # Jerk: derivada de la aceleración
    jerk_values = []
    jerk_times = []

    for i in range(1, len(accelerations)):
        dt = acceleration_times[i] - acceleration_times[i - 1]

        if dt <= 0:
            continue

        jerk = (
            accelerations[i] - accelerations[i - 1]
        ) / dt

        jerk_values.append(jerk)
        jerk_times.append(
            (acceleration_times[i] + acceleration_times[i - 1]) / 2
        )

    if not jerk_values:
        return None

    # Integral aproximada de jerk² respecto al tiempo
    integral = 0.0

    for i in range(1, len(jerk_values)):
        dt = jerk_times[i] - jerk_times[i - 1]

        if dt <= 0:
            continue

        average_jerk_squared = (
            jerk_values[i] ** 2 + jerk_values[i - 1] ** 2
        ) / 2

        integral += average_jerk_squared * dt

    normalized_jerk = sqrt(
        (duration ** 5 / excursion ** 2) * integral
    )

    return normalized_jerk


def calculate_repetition_metrics(
    samples,
    baseline_samples,
    finger_angle_baseline_samples=None,
    frames_total=None,
    frames_valid=None
):
    """
    Calcula las métricas de una repetición de pinza pulgar-índice.
    """

    if finger_angle_baseline_samples is None:
        finger_angle_baseline_samples = []

    baseline_values = [
        x for x in baseline_samples if x is not None
    ]

    valid_samples = [
        s for s in samples
        if s.get("pinch_distance") is not None
    ]

    # ==========================================
    # CALIDAD DEL SEGUIMIENTO
    # ==========================================

    tracking_quality = None

    if frames_total is not None and frames_total > 0:
        if frames_valid is None:
            frames_valid = len(valid_samples)

        tracking_quality = (
            frames_valid / frames_total
        ) * 100

    tracking_metrics = {
        "tracking_quality_pct": (
            round(tracking_quality, 2)
            if tracking_quality is not None else None
        ),
        "tracking_valid_frames": frames_valid,
        "tracking_total_frames": frames_total
    }

    if len(baseline_values) < 5 or len(valid_samples) < 5:
        return {
            "valid": False,
            "message": "Datos insuficientes",
            "samples_count": len(valid_samples),
            **tracking_metrics
        }

    baseline = median(baseline_values)

    distances = [
        s["pinch_distance"] for s in valid_samples
    ]

    min_distance = min(distances)
    excursion = max(0, baseline - min_distance)

    # ==========================================
    # VELOCIDADES DE CIERRE Y APERTURA
    # ==========================================

    closing_velocities = []
    opening_velocities = []

    for i in range(1, len(valid_samples)):

        previous = valid_samples[i - 1]
        current = valid_samples[i]

        dt = current["timestamp"] - previous["timestamp"]

        if dt <= 0:
            continue

        delta = (
            current["pinch_distance"] -
            previous["pinch_distance"]
        )

        velocity = delta / dt

        if velocity < 0:
            closing_velocities.append(abs(velocity))

        elif velocity > 0:
            opening_velocities.append(velocity)

    # ==========================================
    # ÁNGULOS DEL ÍNDICE
    # ==========================================

    pip_values = [
        s["pip_angle"] for s in valid_samples
        if s.get("pip_angle") is not None
    ]

    dip_values = [
        s["dip_angle"] for s in valid_samples
        if s.get("dip_angle") is not None
    ]

    pip_rom = (
        max(pip_values) - min(pip_values)
        if len(pip_values) >= 2 else None
    )

    dip_rom = (
        max(dip_values) - min(dip_values)
        if len(dip_values) >= 2 else None
    )

    # ==========================================
    # MOVIMIENTO COMPENSATORIO
    # ==========================================

    finger_baselines = {}

    for finger in FINGERS:

        values = [
            sample.get(finger)
            for sample in finger_angle_baseline_samples
            if sample and sample.get(finger) is not None
        ]

        if len(values) >= 5:
            finger_baselines[finger] = median(values)

    finger_movements = {}

    for finger in FINGERS:

        if finger not in finger_baselines:
            finger_movements[finger] = None
            continue

        deviations = []

        for sample in valid_samples:

            angles = sample.get("finger_angles") or {}
            current_angle = angles.get(finger)

            if current_angle is None:
                continue

            deviation = abs(
                current_angle - finger_baselines[finger]
            )

            deviations.append(deviation)

        finger_movements[finger] = (
            round(mean(deviations), 2)
            if deviations else None
        )

    available_movements = [
        value
        for value in finger_movements.values()
        if value is not None
    ]

    mean_compensatory_movement = (
        round(mean(available_movements), 2)
        if available_movements else None
    )

    # ==========================================
    # 2. SUAVIDAD DEL MOVIMIENTO
    # ==========================================

    normalized_jerk = calculate_normalized_jerk(
        valid_samples,
        excursion
    )

    # ==========================================
    # 3. ESTABILIDAD DURANTE EL PINZAMIENTO
    # ==========================================

    pinch_stability_std = None
    pinch_stability_samples = []

    if excursion > 1e-6:

        # Seleccionar muestras cercanas a la distancia mínima
        stability_threshold = min_distance + (0.10 * excursion)

        pinch_stability_samples = [
            distance for distance in distances
            if distance <= stability_threshold
        ]

        if len(pinch_stability_samples) >= 5:
            pinch_stability_std = pstdev(
                pinch_stability_samples
            )

    return {
        "valid": True,
        "samples_count": len(valid_samples),

        "baseline_distance": round(baseline, 4),
        "minimum_distance": round(min_distance, 4),
        "pinch_excursion": round(excursion, 4),

        "maximum_closing_velocity": round(
            max(closing_velocities, default=0), 4
        ),

        "maximum_opening_velocity": round(
            max(opening_velocities, default=0), 4
        ),

        "pip_rom": round(pip_rom, 2) if pip_rom is not None else None,
        "dip_rom": round(dip_rom, 2) if dip_rom is not None else None,

        "finger_movement_deg": finger_movements,
        "mean_compensatory_movement_deg": mean_compensatory_movement,

        # Nuevas métricas
        "normalized_jerk": (
            round(normalized_jerk, 4)
            if normalized_jerk is not None else None
        ),

        "pinch_stability_std": (
            round(pinch_stability_std, 5)
            if pinch_stability_std is not None else None
        ),

        "pinch_stability_samples": len(pinch_stability_samples),

        **tracking_metrics
    }


def calculate_session_metrics(repetitions):
    """
    Calcula estadísticas generales de todas las repeticiones válidas.
    """

    valid_repetitions = [
        r for r in repetitions if r.get("valid")
    ]

    excursions = [
        r["pinch_excursion"] for r in valid_repetitions
    ]

    compensatory_movements = [
        r["mean_compensatory_movement_deg"]
        for r in valid_repetitions
        if r.get("mean_compensatory_movement_deg") is not None
    ]

    smoothness_values = [
        r["normalized_jerk"]
        for r in valid_repetitions
        if r.get("normalized_jerk") is not None
    ]

    stability_values = [
        r["pinch_stability_std"]
        for r in valid_repetitions
        if r.get("pinch_stability_std") is not None
    ]

    tracking_values = [
        r["tracking_quality_pct"]
        for r in repetitions
        if r.get("tracking_quality_pct") is not None
    ]

    if not excursions:
        return {
            "valid_repetitions": 0,
            "mean_excursion": None,
            "consistency_cv_pct": None,
            "mean_compensatory_movement_deg": None,
            "mean_normalized_jerk": None,
            "mean_pinch_stability_std": None,
            "mean_tracking_quality_pct": None
        }

    average = mean(excursions)
    std = pstdev(excursions) if len(excursions) > 1 else 0

    cv = (
        (std / average) * 100
        if average > 0 else None
    )

    return {
        "valid_repetitions": len(valid_repetitions),

        "mean_excursion": round(average, 4),
        "std_excursion": round(std, 4),

        "consistency_cv_pct": (
            round(cv, 2) if cv is not None else None
        ),

        "mean_compensatory_movement_deg": (
            round(mean(compensatory_movements), 2)
            if compensatory_movements else None
        ),

        "mean_normalized_jerk": (
            round(mean(smoothness_values), 4)
            if smoothness_values else None
        ),

        "mean_pinch_stability_std": (
            round(mean(stability_values), 5)
            if stability_values else None
        ),

        "mean_tracking_quality_pct": (
            round(mean(tracking_values), 2)
            if tracking_values else None
        )
    }
