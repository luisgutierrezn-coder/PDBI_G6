from gnd.exercise_base import ExerciseBase
from auxx.biomech import *


class OpenCloseExercise(ExerciseBase):

    def __init__(self):
        super().__init__()

        self.instruction = (
            "Cierra completamente la mano formando un puño y luego extiende todos los dedos."
        )
    
    def get_instruction(self):
        return self.instruction
    
    def process(self, landmarks, timestamp):

        dip_thumb = landmarks[4]
        dip_index = landmarks[8]
        dip_middle = landmarks[12]
        dip_ring = landmarks[16]
        dip_pinky = landmarks[20]

        d_1 = raw_distance(dip_thumb,dip_index)
        d_2 = raw_distance(dip_index,dip_middle)
        d_3 = raw_distance(dip_middle,dip_ring)
        d_4 = raw_distance(dip_ring,dip_pinky)

        measurements = {
            "timestamp": timestamp,
            "distances": {
                "thumb_index": d_1,
                "index_middle": d_2,
                "middle_ring": d_3,
                "ring_pinky": d_4
            }
        }

        self.data.append(measurements)

        return measurements

    def calculate_metrics(self):

        results = {}

        return results