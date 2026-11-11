import cv2
import mediapipe as mp

from mediapipe.tasks import python
from mediapipe.tasks.python import vision


class HandTracker:

    def __init__(self, model_path, num_hands=1):

        self.base_options = python.BaseOptions(
            model_asset_path=model_path
        )

        options = vision.HandLandmarkerOptions(
            base_options=self.base_options,
            running_mode=vision.RunningMode.VIDEO,
            num_hands=num_hands,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5
        )

        self.detector = vision.HandLandmarker.create_from_options(
            options
        )

        self.last_timestamp_ms = 0

    def process(self, frame, timestamp_ms):

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb_frame
        )

        timestamp_ms = max(
            timestamp_ms,
            self.last_timestamp_ms + 1
        )

        self.last_timestamp_ms = timestamp_ms

        results = self.detector.detect_for_video(
            mp_image,
            timestamp_ms
        )

        display_frame = frame.copy()
        hands = []

        if results.hand_landmarks:

            for hand_index, hand_landmarks in enumerate(
                results.hand_landmarks
            ):

                # Guardar los landmarks normalizados
                landmarks = [
                    {
                        "x": point.x,
                        "y": point.y,
                        "z": point.z
                    }
                    for point in hand_landmarks
                ]

                hands.append(landmarks)

                # Dibujar landmarks
                for point in hand_landmarks:
                    x = int(point.x * frame.shape[1])
                    y = int(point.y * frame.shape[0])

                    cv2.circle(
                        display_frame,
                        (x, y),
                        3,
                        (0, 255, 0),
                        -1
                    )

        return display_frame, hands

    def close(self):
        self.detector.close()