
from gnd.exercise_base import ExerciseBase
from auxx.biomech import *


class PincerGraspExercise(ExerciseBase):

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
        self.tasks = {
            "index": {
                "instruction": "Toca la punta del dedo indice con el pulgar",
                "landmarks": (4, 8)
            },
            "middle": {
                "instruction": "Toca la punta del dedo medio con el pulgar",
                "landmarks": (4, 12)
            },
            "ring": {
                "instruction": "Toca la punta del dedo anular con el pulgar",
                "landmarks": (4, 16)
            },
            "pinky": {
                "instruction": "Toca la punta del dedo menique con el pulgar",
                "landmarks": (4, 20)
            }
        }

        self.task_names = list(self.tasks.keys())
        self.current_task_index = 0

    # Obtener la tarea actual
    def get_current_task(self):

        if self.current_task_index >= len(self.task_names):
            return None

        task_name = self.task_names[self.current_task_index]

        return {
            "name": task_name,
            **self.tasks[task_name]
        }

    # Obtener la instruccion para el paciente
    def get_instruction(self):

        task = self.get_current_task()

        if task is None:
            return "Ejercicio completado"

        return task["instruction"]

    # Procesar los landmarks de la tarea actual
    def process(self, landmarks, timestamp):

        if landmarks is None or len(landmarks) < 21:
            return None

        task = self.get_current_task()

        if task is None:
            return None

        point1_index, point2_index = task["landmarks"]

        point1 = landmarks[point1_index]
        point2 = landmarks[point2_index]

        distance = raw_distance(point1, point2)

        measurements = {
            "timestamp": timestamp,
            "task": task["name"],
            "distance": distance
        }

        self.data.append(measurements)

        return measurements

    # Avanzar a la siguiente tarea
    def next_task(self):

        if self.current_task_index < len(self.task_names):
            self.current_task_index += 1

        return self.get_current_task()

    # Verificar si el ejercicio termino
    def is_completed(self):

        return self.current_task_index >= len(self.task_names)

    # Reiniciar el ejercicio
    def reset(self):

        super().reset()
        self.current_task_index = 0

    # Obtener resultados
    def calculate_metrics(self):

        return {
            "measurements": self.data
        }

    def get_phases(self):
            return self.phases