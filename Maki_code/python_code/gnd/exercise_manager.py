from exercises.open_close import OpenCloseExercise
from exercises.pincer_grasp import PincerGraspExercise
from exercises.fist_my_bump import FistMyBumpExercise
from exercises.wrist import WristExercise


class ExerciseManager:

    def __init__(self):

        self.exercises = {
            "open_close": OpenCloseExercise,
            "pincer_grasp": PincerGraspExercise,
            "fist_my_bump": FistMyBumpExercise,
            "wrist": WristExercise
        }
        self.current_exercise = None
        self.current_exercise_name = None

    def start_exercise(self, exercise_name):

        if exercise_name not in self.exercises:
            raise ValueError("Exercise not found")

        exercise_class = self.exercises[exercise_name]

        self.current_exercise = exercise_class()
        self.current_exercise_name = exercise_name

    def process_frame(self, landmarks, timestamp):

        if self.current_exercise is None:
            return None

        return self.current_exercise.process(
            landmarks,
            timestamp
        )

    def finish_exercise(self):

        if self.current_exercise is None:
            return None

        results = self.current_exercise.get_results()

        self.current_exercise = None
        self.current_exercise_name = None

        return results

    def get_current_exercise(self):
        return self.current_exercise_name
