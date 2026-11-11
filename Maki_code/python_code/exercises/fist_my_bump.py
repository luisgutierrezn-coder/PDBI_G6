
from gnd.exercise_base import ExerciseBase
from auxx.biomech import calculate_angle


class FistMyBumpExercise(ExerciseBase):

    def __init__(self):
        super().__init__()
        
        self.finger_landmarks = {
            "index": {
                "mcp": (0, 5, 6),
                "pip": (5, 6, 7),
                "dip": (6, 7, 8)
            },
            "middle": {
                "mcp": (0, 9, 10),
                "pip": (9, 10, 11),
                "dip": (10, 11, 12)
            },
            "ring": {
                "mcp": (0, 13, 14),
                "pip": (13, 14, 15),
                "dip": (14, 15, 16)
            },
            "pinky": {
                "mcp": (0, 17, 18),
                "pip": (17, 18, 19),
                "dip": (18, 19, 20)
            }
        }

        self.instruction = (
            "Cierra completamente la mano formando un puño y luego extiende todos los dedos."
        )

    def get_instruction(self):
        return self.instruction

    def process(self, landmarks, timestamp):

        # Verificar que se hayan detectado los 21 landmarks
        if landmarks is None or len(landmarks) < 21:
            return None

        measurements = {
            "timestamp": timestamp,
            "exercise": "fist_my_bump",
            "fingers": {}
        }

        # Calcular los ángulos de cada dedo
        for finger, joints in self.finger_landmarks.items():

            pip_points = joints["pip"]
            dip_points = joints["dip"]

            pip_angle = calculate_angle(
                landmarks[pip_points[0]],
                landmarks[pip_points[1]],
                landmarks[pip_points[2]]
            )

            dip_angle = calculate_angle(
                landmarks[dip_points[0]],
                landmarks[dip_points[1]],
                landmarks[dip_points[2]]
            )

            measurements["fingers"][finger] = {
                "pip": pip_angle,
                "dip": dip_angle
            }

        self.data.append(measurements)

        return measurements

    def calculate_metrics(self):
        return {
            "exercise": "fist_my_bump",
            "measurements": self.data
        }

    def reset(self):
        super().reset()
