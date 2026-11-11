from abc import ABC, abstractmethod


class ExerciseBase(ABC):

    def __init__(self):
        self.data = []
        self.repetitions = []

    @abstractmethod
    def process(self, landmarks, timestamp):
        pass

    @abstractmethod
    def calculate_metrics(self):
        pass

    def reset(self):
        self.data = []
        self.repetitions = []

    def get_results(self):
        return self.calculate_metrics()