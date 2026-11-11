from gnd.exercise_base import ExerciseBase


class WristExercise(ExerciseBase):
    def __init__(self):
        super().__init__()
        self.phases = [
            {
                "phase": "preparation",
                "instruction": "Cierra los dedos por completo",
                "duration": 3
            },
            {
                "phase": "chamba",
                "instruction": "Abre lo más que puedas los dedos",
                "duration": 10
            },
            {
                "phase": "calma",
                "instruction": "Cierra los dedos",
                "duration": 5
            }
        ]