
import cv2
import math
import mediapipe as mp

from mediapipe.tasks import python
from mediapipe.tasks.python import vision


class HandTracker:

    # Conexiones anatómicas de los 21 landmarks
    HAND_CONNECTIONS = [
        # Pulgar
        (0, 1), (1, 2), (2, 3), (3, 4),

        # Índice
        (0, 5), (5, 6), (6, 7), (7, 8),

        # Medio
        (5, 9), (9, 10), (10, 11), (11, 12),

        # Anular
        (9, 13), (13, 14), (14, 15), (15, 16),

        # Meñique
        (13, 17), (17, 18), (18, 19), (19, 20),

        # Palma
        (0, 17)
    ]

    def __init__(self, model_path="hand_landmarker.task"):
        # Parámetros del filtro EMA
        self.alpha = 0.25
        # Ángulo proyectado de orientación de la mano
        self.last_hand_angle_deg = None
        self.smoothed_hand_angle_deg = None
        

        # Almacenar las distancias filtradas
        self.smoothed_pinch_distances = {}
        self.smoothed_full_fist_angles = {}
        base_options = python.BaseOptions(
            model_asset_path=model_path
        )
        # Distancias filtradas para finger_abduction
        self.smoothed_abduction_distances = {}

        options = vision.HandLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5
        )

        self.detector = vision.HandLandmarker.create_from_options(
            options
        )

        self.last_timestamp = -1

    # ==================================================
    # CÁLCULO DE ÁNGULOS
    # ==================================================

    @staticmethod
    def calculate_angle(a, b, c):

        ba = [a.x - b.x, a.y - b.y]
        bc = [c.x - b.x, c.y - b.y]

        dot_product = (
            ba[0] * bc[0] +
            ba[1] * bc[1]
        )

        magnitude_ba = math.sqrt(
            ba[0] ** 2 + ba[1] ** 2
        )

        magnitude_bc = math.sqrt(
            bc[0] ** 2 + bc[1] ** 2
        )

        if magnitude_ba == 0 or magnitude_bc == 0:
            return None

        cosine = dot_product / (
            magnitude_ba * magnitude_bc
        )

        cosine = max(-1, min(1, cosine))

        angle = math.degrees(math.acos(cosine))

        return round(angle, 2)

    
    @staticmethod
    def calculate_hand_orientation(landmarks, frame_shape):
        """
        Calcula la orientación proyectada de la mano
        utilizando los landmarks 0 (muñeca) y 9 (MCP medio).

        Retorna un ángulo entre -180 y 180 grados.
        """

        h, w = frame_shape[:2]

        wrist = landmarks[0]
        middle_mcp = landmarks[9]

        dx = (middle_mcp.x - wrist.x) * w
        dy = (middle_mcp.y - wrist.y) * h

        if math.sqrt(dx**2 + dy**2) < 1e-6:
            return None

        angle = math.degrees(
            math.atan2(dy, dx)
        )

        return round(angle, 2)

    def smooth_hand_orientation(self, angle):
        """
        Aplica un filtro EMA circular para suavizar
        el ángulo sin generar saltos en +/-180 grados.
        """

        if angle is None:
            self.smoothed_hand_angle_deg = None
            return None

        if self.smoothed_hand_angle_deg is None:

            self.smoothed_hand_angle_deg = angle

        else:

            previous = self.smoothed_hand_angle_deg

            difference = (
                (angle - previous + 180) % 360
            ) - 180

            filtered = previous + self.alpha * difference

            self.smoothed_hand_angle_deg = (
                (filtered + 180) % 360
            ) - 180

        return round(self.smoothed_hand_angle_deg, 2)


    @staticmethod
    def calculate_non_target_finger_angles(landmarks):
        """
        Calcula los ángulos PIP de los dedos que no participan
        directamente en el pinzamiento.
        """

        return {
            "middle": HandTracker.calculate_angle(
                landmarks[9],
                landmarks[10],
                landmarks[11]
            ),
            "ring": HandTracker.calculate_angle(
                landmarks[13],
                landmarks[14],
                landmarks[15]
            ),
            "pinky": HandTracker.calculate_angle(
                landmarks[17],
                landmarks[18],
                landmarks[19]
            )
        }

    @staticmethod
    def calculate_angle_pixels(a, b, c, frame_shape):

        h, w = frame_shape[:2]

        ax, ay = a.x * w, a.y * h
        bx, by = b.x * w, b.y * h
        cx, cy = c.x * w, c.y * h

        ba = (ax - bx, ay - by)
        bc = (cx - bx, cy - by)

        dot_product = ba[0] * bc[0] + ba[1] * bc[1]

        mag_ba = math.hypot(*ba)
        mag_bc = math.hypot(*bc)

        if mag_ba == 0 or mag_bc == 0:
            return None

        cosine = dot_product / (mag_ba * mag_bc)
        cosine = max(-1, min(1, cosine))

        return round(math.degrees(math.acos(cosine)), 2)


    @staticmethod
    def calculate_full_fist_angles(landmarks, frame_shape):

        return {
            "thumb": HandTracker.calculate_angle_pixels(
                landmarks[2], landmarks[3], landmarks[4],
                frame_shape
            ),
            "index": HandTracker.calculate_angle_pixels(
                landmarks[5], landmarks[6], landmarks[7],
                frame_shape
            ),
            "middle": HandTracker.calculate_angle_pixels(
                landmarks[9], landmarks[10], landmarks[11],
                frame_shape
            ),
            "ring": HandTracker.calculate_angle_pixels(
                landmarks[13], landmarks[14], landmarks[15],
                frame_shape
            ),
            "pinky": HandTracker.calculate_angle_pixels(
                landmarks[17], landmarks[18], landmarks[19],
                frame_shape
            )
        }
    # ==================================================
    # CONVERTIR LANDMARKS A DATOS NUMÉRICOS
    # ==================================================

    @staticmethod
    def extract_landmarks(landmarks):

        if landmarks is None:
            return None

        points = []

        for index, landmark in enumerate(landmarks):

            points.append({
                "id": index,
                "x": round(landmark.x, 6),
                "y": round(landmark.y, 6),
                "z": round(landmark.z, 6)
            })

        return points

    # ==================================================
    # CALCULAR DISTANCIAS ENTRE DEDOS
    # ==================================================

    @staticmethod
    def calculate_pinch_distances(landmarks, frame_shape):

        h, w = frame_shape[:2]

        # Puntas de los dedos
        thumb = landmarks[4]
        index = landmarks[8]
        middle = landmarks[12]
        ring = landmarks[16]
        pinky = landmarks[20]

        # Referencias para calcular el ancho de la palma
        index_mcp = landmarks[5]
        pinky_mcp = landmarks[17]

        def pixel_distance(point_a, point_b):

            dx = (point_a.x - point_b.x) * w
            dy = (point_a.y - point_b.y) * h

            return math.sqrt(dx**2 + dy**2)

        palm_width = pixel_distance(
            index_mcp,
            pinky_mcp
        )

        if palm_width < 1:
            return None

        distances = {
            "thumb_index": pixel_distance(thumb, index),
            "thumb_middle": pixel_distance(thumb, middle),
            "thumb_ring": pixel_distance(thumb, ring),
            "thumb_pinky": pixel_distance(thumb, pinky)
        }

        # Normalizar las distancias respecto al ancho de la palma
        normalized_distances = {}

        for name, distance in distances.items():

            normalized_distances[name] = round(
                distance / palm_width,
                4
            )

        return {
            "pixel": {
                name: round(distance, 2)
                for name, distance in distances.items()
            },
            "normalized": normalized_distances,
            "palm_width_px": round(palm_width, 2)
        }
        # ==================================================
    # MOSTRAR DISTANCIAS DE PINCH
    # ==================================================

    @staticmethod
    def draw_pinch_distances(frame, distances,last_hand_angle_deg):

        if distances is None:
            return

        values = distances["normalized"]

        labels = [
            ("Pulgar-Indice", "thumb_index"),
            ("Pulgar-Medio", "thumb_middle"),
            ("Pulgar-Anular", "thumb_ring"),
            ("Pulgar-Menique", "thumb_pinky")
        ]
        cv2.putText(
            frame,
            f"Hand angle: {last_hand_angle_deg if last_hand_angle_deg is not None else '--'}",
            (20, 140),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 0),
            2
        )
        y_position = 170

        for label, key in labels:

            value = values[key]

            text = f"{label}: {value:.3f}"

            cv2.putText(
                frame,
                text,
                (20, y_position),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 255, 255),
                2
            )

            y_position += 30

    
    # ==================================================
    # MOSTRAR DISTANCIAS DE ABDUCCIÓN
    # ==================================================

    @staticmethod
    def draw_abduction_distances(frame, distances):

        if distances is None:
            return

        values = distances["normalized"]

        labels = [
            ("Pulgar-Indice", "thumb_index"),
            ("Indice-Medio", "index_middle"),
            ("Medio-Anular", "middle_ring"),
            ("Anular-Menique", "ring_pinky")
        ]

        y_position = 260

        for label, key in labels:

            value = values[key]

            cv2.putText(
                frame,
                f"{label}: {value:.3f}",
                (20, y_position),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (255, 150, 0),
                2
            )

            y_position += 27

        cv2.putText(
            frame,
            f"Apertura global: {distances['global_opening']:.3f}",
            (20, y_position + 5),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 255, 255),
            2
        )
    @staticmethod
    def draw_full_fist_angles(frame, angles):

        if angles is None:
            return

        labels = {
            "thumb": "Pulgar IP",
            "index": "Indice PIP",
            "middle": "Medio PIP",
            "ring": "Anular PIP",
            "pinky": "Menique PIP"
        }

        y_position = 260

        for key, label in labels.items():

            value = angles.get(key)

            text = (
                f"{label}: {value:.1f} deg"
                if value is not None
                else f"{label}: --"
            )

            cv2.putText(
                frame,
                text,
                (20, y_position),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 255, 255),
                2
            )

            y_position += 27

    # ==================================================
    # CALCULAR DISTANCIAS DE ABDUCCIÓN
    # ==================================================

    @staticmethod
    def calculate_abduction_distances(landmarks, frame_shape):

        h, w = frame_shape[:2]

        # Puntas de los cinco dedos
        thumb = landmarks[4]
        index = landmarks[8]
        middle = landmarks[12]
        ring = landmarks[16]
        pinky = landmarks[20]

        # Referencias para normalización
        index_mcp = landmarks[5]
        pinky_mcp = landmarks[17]

        def pixel_distance(point_a, point_b):

            dx = (point_a.x - point_b.x) * w
            dy = (point_a.y - point_b.y) * h

            return math.sqrt(dx**2 + dy**2)

        # Ancho de la palma
        palm_width = pixel_distance(
            index_mcp,
            pinky_mcp
        )

        if palm_width < 1:
            return None

        # Distancias entre puntas consecutivas
        distances = {
            "thumb_index": pixel_distance(thumb, index),
            "index_middle": pixel_distance(index, middle),
            "middle_ring": pixel_distance(middle, ring),
            "ring_pinky": pixel_distance(ring, pinky)
        }

        # Normalización
        normalized = {
            name: round(distance / palm_width, 4)
            for name, distance in distances.items()
        }

        # Índice global de apertura
        global_opening = sum(
            normalized.values()
        ) / len(normalized)

        return {
            "pixel": {
                name: round(distance, 2)
                for name, distance in distances.items()
            },

            "normalized": normalized,

            "global_opening": round(
                global_opening,
                4
            ),

            "palm_width_px": round(
                palm_width,
                2
            )
        }

        # ==================================================
    # PROCESAMIENTO PRINCIPAL
    # ==================================================

    def process(self, frame, timestamp_ms):

        if frame is None:
            return frame, None, None, None, None

        timestamp_ms = max(
            int(timestamp_ms),
            self.last_timestamp + 1
        )

        self.last_timestamp = timestamp_ms

        rgb_frame = cv2.cvtColor(
            frame,
            cv2.COLOR_BGR2RGB
        )

        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb_frame
        )

        results = self.detector.detect_for_video(
            mp_image,
            timestamp_ms
        )

        display_frame = frame.copy()

        pip = None
        dip = None
        landmarks_data = None
        pinch_distances = None

        if results.hand_landmarks:

            landmarks = results.hand_landmarks[0]

            # Calcular orientación proyectada de la mano
            raw_hand_angle = self.calculate_hand_orientation(
                landmarks,
                display_frame.shape
            )

            self.last_hand_angle_deg = self.smooth_hand_orientation(
                raw_hand_angle
            )

            # Extraer los 21 landmarks
            landmarks_data = self.extract_landmarks(
                landmarks
            )

            # Calcular ángulos del índice
            pip = self.calculate_angle(
                landmarks[5],
                landmarks[6],
                landmarks[7]
            )

            dip = self.calculate_angle(
                landmarks[6],
                landmarks[7],
                landmarks[8]
            )

            # ==========================================
            # DISTANCIAS DE PINZAMIENTO
            # ==========================================

            pinch_distances = self.calculate_pinch_distances(
                landmarks,
                display_frame.shape
            )

            pinch_distances = self.smooth_pinch_distances(
                pinch_distances
            )

            # ==========================================
            # DISTANCIAS DE ABDUCCIÓN
            # ==========================================

            abduction_distances = self.calculate_abduction_distances(
                landmarks,
                display_frame.shape
            )

            abduction_distances = self.smooth_abduction_distances(
                abduction_distances
            )

            # Calcular ángulos PIP de los dedos no objetivo
            finger_angles = self.calculate_non_target_finger_angles(
                landmarks
            )

            # ==========================================
            # ÁNGULOS DE FLEXIÓN PARA FULL FIST
            # ==========================================

            full_fist_angles = self.calculate_full_fist_angles(
                landmarks,
                display_frame.shape
            )

            full_fist_angles = self.smooth_full_fist_angles(
                full_fist_angles
            )

            # Incorporar los ángulos a los datos de pinch
            # Incorporar información adicional
            if pinch_distances is not None:
                pinch_distances["full_fist_angles"] = full_fist_angles

                pinch_distances["finger_angles"] = finger_angles

                pinch_distances["hand_angle_deg"] = (
                    self.last_hand_angle_deg
                )

                pinch_distances["abduction"] = abduction_distances

            # Dibujar landmarks
            self.draw_landmarks(
                display_frame,
                landmarks
            )

            cv2.putText(
                display_frame,
                "MANO DETECTADA",
                (20, 35),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 255, 0),
                2
            )

            # Mostrar distancias
            self.draw_pinch_distances(
                display_frame,
                pinch_distances,
                self.last_hand_angle_deg
            )

            """
            self.draw_abduction_distances(
                display_frame,
                abduction_distances
            )
            """

            self.draw_full_fist_angles(
                display_frame,
                full_fist_angles
            )
            

        else:
            self.smooth_pinch_distances(None)
            self.smooth_abduction_distances(None)
            self.smooth_full_fist_angles(None)

            self.smoothed_hand_angle_deg = None
            self.last_hand_angle_deg = None

            cv2.putText(
                display_frame,
                "NO SE DETECTA UNA MANO",
                (20, 35),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 0, 255),
                2
            )

        # Mostrar ángulos del índice
        '''
        cv2.putText(
            display_frame,
            f"PIP: {pip if pip is not None else '--'}",
            (20, 70),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 255, 0),
            2
        )
        '''

        cv2.putText(
            display_frame,
            f"DIP: {dip if dip is not None else '--'}",
            (20, 100),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 255, 0),
            2
        )

        return (
            display_frame,
            pip,
            dip,
            landmarks_data,
            pinch_distances
        )
    # ==================================================
    # DIBUJAR LOS 21 LANDMARKS
    # ==================================================

    def draw_landmarks(self, frame, landmarks):

        h, w, _ = frame.shape

        points = {}

        # Convertir coordenadas normalizadas a píxeles
        for index, landmark in enumerate(landmarks):

            x = int(landmark.x * w)
            y = int(landmark.y * h)

            points[index] = (x, y)

        # Dibujar conexiones
        for start, end in self.HAND_CONNECTIONS:

            cv2.line(
                frame,
                points[start],
                points[end],
                (255, 120, 0),
                2
            )

        # Dibujar landmarks y números
        for index, (x, y) in points.items():

            cv2.circle(
                frame,
                (x, y),
                5,
                (0, 255, 0),
                -1
            )

            cv2.putText(
                frame,
                str(index),
                (x + 6, y - 6),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.4,
                (255, 255, 255),
                1
            )
    # ==================================================
# FILTRO EMA PARA DISTANCIAS
# ==================================================

    def smooth_pinch_distances(self, distances):

        if distances is None:
            self.smoothed_pinch_distances = {}
            return None

        normalized = distances["normalized"]

        smoothed = {}

        for name, value in normalized.items():

            if name not in self.smoothed_pinch_distances:

                # Primera medición
                self.smoothed_pinch_distances[name] = value

            else:

                previous = self.smoothed_pinch_distances[name]

                filtered = (
                    self.alpha * value +
                    (1 - self.alpha) * previous
                )

                self.smoothed_pinch_distances[name] = filtered

            smoothed[name] = round(
                self.smoothed_pinch_distances[name],
                4
            )

        # Crear una copia para no modificar los datos originales
        result = distances.copy()

        result["normalized"] = smoothed

        return result
    
    # ==================================================
    # FILTRO EMA PARA ABDUCCIÓN
    # ==================================================

    def smooth_abduction_distances(self, distances):

        if distances is None:
            self.smoothed_abduction_distances = {}
            return None

        normalized = distances["normalized"]

        smoothed = {}

        for name, value in normalized.items():

            if name not in self.smoothed_abduction_distances:

                self.smoothed_abduction_distances[name] = value

            else:

                previous = self.smoothed_abduction_distances[name]

                filtered = (
                    self.alpha * value +
                    (1 - self.alpha) * previous
                )

                self.smoothed_abduction_distances[name] = filtered

            smoothed[name] = round(
                self.smoothed_abduction_distances[name],
                4
            )

        result = distances.copy()

        result["normalized"] = smoothed

        result["global_opening"] = round(
            sum(smoothed.values()) / len(smoothed),
            4
        )

        return result

    def smooth_full_fist_angles(self, angles):

        if angles is None:
            self.smoothed_full_fist_angles = {}
            return None

        smoothed = {}

        for name, value in angles.items():

            if value is None:
                smoothed[name] = None
                continue

            if name not in self.smoothed_full_fist_angles:
                self.smoothed_full_fist_angles[name] = value

            else:
                previous = self.smoothed_full_fist_angles[name]

                filtered = (
                    self.alpha * value +
                    (1 - self.alpha) * previous
                )

                self.smoothed_full_fist_angles[name] = filtered

            smoothed[name] = round(
                self.smoothed_full_fist_angles[name], 2
            )

        return smoothed
    # ==================================================
    # CIERRE
    # ==================================================

    def close(self):

        if self.detector is not None:

            self.detector.close()
            self.detector = None
