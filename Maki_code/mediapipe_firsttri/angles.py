
import cv2
import mediapipe as mp
import time
import math
import csv
import matplotlib.pyplot as plt

# =========================================
# CONFIGURACION
# =========================================
DURATION = 20  # duracion de la medicion en segundos

BaseOptions = mp.tasks.BaseOptions
HandLandmarker = mp.tasks.vision.HandLandmarker
Options = mp.tasks.vision.HandLandmarkerOptions
RunningMode = mp.tasks.vision.RunningMode

options = Options(
    base_options=BaseOptions(
        model_asset_path="hand_landmarker.task"
    ),
    running_mode=RunningMode.VIDEO,
    num_hands=1
)


# =========================================
# CALCULAR ANGULO ENTRE TRES PUNTOS 3D
# =========================================
def calculate_angle(a, b, c):
    v1 = [a[i] - b[i] for i in range(3)]
    v2 = [c[i] - b[i] for i in range(3)]

    dot = sum(v1[i] * v2[i] for i in range(3))
    norm1 = math.sqrt(sum(x * x for x in v1))
    norm2 = math.sqrt(sum(x * x for x in v2))

    if norm1 == 0 or norm2 == 0:
        return float("nan")

    cosine = dot / (norm1 * norm2)
    cosine = max(-1.0, min(1.0, cosine))

    return math.degrees(math.acos(cosine))


# =========================================
# PREPARAR CAMARA
# =========================================
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    raise RuntimeError("No se pudo abrir la camara.")

times = []
pip_angles = []
dip_angles = []
knuckle_angles = []

# =========================================
# PREPARAR GRAFICAS EN TIEMPO REAL
# =========================================
plt.ion()

fig, axes = plt.subplots(
    3, 1,
    figsize=(9, 7),
    sharex=True
)

fig.suptitle("Angulos del dedo indice en tiempo real")

line_dip, = axes[0].plot([], [], color="blue")
line_pip, = axes[1].plot([], [], color="red")
line_knuckle, = axes[2].plot([], [], color="green")

axes[0].set_title("Articulacion DIP (landmarks 6-7-8)")
axes[0].set_ylabel("Angulo (grados)")
axes[0].set_ylim(0, 180)
axes[0].set_xlim(0, DURATION)
axes[0].grid(True)

axes[1].set_title("Articulacion PIP (landmarks 5-6-7)")
axes[1].set_ylabel("Angulo (grados)")
axes[1].set_ylim(0, 180)
axes[1].set_xlim(0, DURATION)
axes[1].grid(True)

axes[2].set_title("Articulacion knuckle (landmarks 0-5-6)")
axes[2].set_ylabel("Angulo (grados)")
axes[2].set_ylim(0, 180)
axes[2].set_xlim(0, DURATION)
axes[2].grid(True)
axes[2].set_xlabel("Tiempo (s)")

fig.tight_layout()
fig.show()
fig.canvas.draw()

start_time = time.perf_counter()
prev_timestamp_ms = -1

try:
    with HandLandmarker.create_from_options(options) as detector:

        while True:
            success, frame = cap.read()

            if not success:
                print("No se pudo leer el fotograma.")
                break

            frame = cv2.flip(frame, 1)

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            image = mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=rgb
            )

            elapsed = time.perf_counter() - start_time

            timestamp_ms = int(elapsed * 1000)
            timestamp_ms = max(
                timestamp_ms, prev_timestamp_ms + 1
            )
            prev_timestamp_ms = timestamp_ms

            result = detector.detect_for_video(
                image, timestamp_ms
            )

            # Medir durante los primeros 20 segundos
            if elapsed <= DURATION:
                pip = float("nan")
                dip = float("nan")
                knuckle = float("nan")

                if result.hand_world_landmarks:
                    hand = result.hand_world_landmarks[0]

                    p0 = (hand[0].x, hand[0].y, hand[0].z)
                    p5 = (hand[5].x, hand[5].y, hand[5].z)
                    p6 = (hand[6].x, hand[6].y, hand[6].z)
                    p7 = (hand[7].x, hand[7].y, hand[7].z)
                    p8 = (hand[8].x, hand[8].y, hand[8].z)

                    dip = calculate_angle(p6, p7, p8)
                    pip = calculate_angle(p5, p6, p7)
                    knuckle = calculate_angle(p0, p5, p6)

                times.append(elapsed)
                pip_angles.append(pip)
                dip_angles.append(dip)
                knuckle_angles.append(knuckle)

                # Actualizar las curvas
                line_pip.set_data(times, pip_angles)
                line_dip.set_data(times, dip_angles)
                line_knuckle.set_data(times, knuckle_angles)

                # Mantener el eje horizontal en 0-20 segundos
                axes[0].set_xlim(0, DURATION)
                axes[1].set_xlim(0, DURATION)

                # Actualizar la ventana de graficas
                fig.canvas.draw_idle()
                fig.canvas.flush_events()
                plt.pause(0.001)

            # Dibujar puntos del indice en la camara
            if result.hand_landmarks:
                hand_2d = result.hand_landmarks[0]
                h, w, _ = frame.shape

                points = [
                    (int(p.x * w), int(p.y * h))
                    for p in hand_2d
                ]

                for idx in [0, 5, 6, 7, 8]:
                    cv2.circle(
                        frame, points[idx], 7,
                        (0, 255, 0), -1
                    )

                for a, b in [(0, 5), (5, 6), (6, 7), (7, 8)]:
                    cv2.line(
                        frame, points[a], points[b],
                        (255, 0, 0), 3
                    )

            remaining = max(0, DURATION - elapsed)

            cv2.putText(
                frame,
                f"Tiempo restante: {remaining:.1f} s",
                (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7, (0, 255, 255), 2
            )

            cv2.imshow("Seguimiento del dedo indice", frame)

            # Salir si se presiona Q en la ventana de la camara
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

            # Terminar medicion al llegar a 20 segundos
            if elapsed >= DURATION:
                break

finally:
    cap.release()
    cv2.destroyAllWindows()

    # Guardar datos medidos
    with open(
        "angulos_indice.csv",
        "w",
        newline="",
        encoding="utf-8"
    ) as file:

        writer = csv.writer(file)
        writer.writerow([
            "tiempo_s",
            "angulo_PIP_grados",
            "angulo_DIP_grados",
            "angulo_knuckle_grados"
        ])

        for t, pip, dip, knuckles in zip(
            times, pip_angles, dip_angles,knuckle_angles
        ):
            writer.writerow([t, pip, dip,knuckles])

    # Dejar las graficas abiertas al terminar
    plt.ioff()

    if times:
        plt.show()
    else:
        plt.close("all")

print("Medicion finalizada.")
print("Datos guardados en angulos_indice.csv")
