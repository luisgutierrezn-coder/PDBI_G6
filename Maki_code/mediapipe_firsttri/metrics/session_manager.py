
import threading
from statistics import median

from metrics.pinch_metrics import (
    calculate_repetition_metrics as calculate_pinch_repetition_metrics,
    calculate_session_metrics as calculate_pinch_session_metrics
)

from metrics.wrist_metrics import (
    calculate_repetition_metrics as calculate_wrist_repetition_metrics,
    calculate_session_metrics as calculate_wrist_session_metrics,
    calculate_reference_angle
)
from metrics.finger_abduction_metrics import (
    calculate_repetition_metrics as calculate_abduction_repetition_metrics,
    calculate_session_metrics as calculate_abduction_session_metrics,
    calculate_reference_abduction
)


from metrics.full_fist_metrics import (
    calculate_repetition_metrics as calculate_full_fist_repetition_metrics,
    calculate_session_metrics as calculate_full_fist_session_metrics,
    calculate_reference_angles
)



class SessionManager:

    def __init__(self):
        self.lock = threading.RLock()
        self.reset()

    # ==================================================
    # RESET
    # ==================================================

    def reset(self):

        with self.lock:

            self.status = "IDLE"
            self.phase = "IDLE"

            self.exercise = "pinch_index"

            self.total_reps = 0
            self.current_rep = 0

            # Variables de PINCH
            self.baseline_samples = []
            self.finger_angle_baseline_samples = []
            self.all_baseline_samples = []

            # Variables de MUÑECA
            self.wrist_baseline_samples = []
            self.all_wrist_baseline_samples = []
            # Variables de ABDUCCIÓN
            self.abduction_baseline_samples = []
            self.all_abduction_baseline_samples = []


            # Variables de FULL FIST
            self.full_fist_baseline_samples = []
            self.all_full_fist_baseline_samples = []


            self.repetitions = []

            self.result = None
            self.error = None

    # ==================================================
    # INICIAR SESIÓN
    # ==================================================

    def start(self, total_reps, exercise="pinch_index"):

        supported_exercises = [
            "pinch_index",
            "wrist_movement",
            "finger_abduction",
            "full_fist"
        ]

        if exercise not in supported_exercises:
            raise ValueError(
                f"Ejercicio no soportado: {exercise}"
            )

        with self.lock:

            self.status = "RUNNING"
            self.phase = "POSITIONING"

            self.exercise = exercise

            self.total_reps = total_reps
            self.current_rep = 0

            # PINCH
            self.baseline_samples = []
            self.finger_angle_baseline_samples = []
            self.all_baseline_samples = []

            # MUÑECA
            self.wrist_baseline_samples = []
            self.all_wrist_baseline_samples = []

            # ABDUCTION
            self.abduction_baseline_samples = []
            self.all_abduction_baseline_samples = []


            # FULL FIST
            self.full_fist_baseline_samples = []
            self.all_full_fist_baseline_samples = []


            self.repetitions = []

            self.result = None
            self.error = None

    # ==================================================
    # POSICIONAMIENTO
    # ==================================================

    def begin_positioning(self):

        with self.lock:

            if self.status != "RUNNING":
                return

            self.phase = "POSITIONING"

            if self.exercise == "pinch_index":

                self.baseline_samples = []
                self.finger_angle_baseline_samples = []

            elif self.exercise == "wrist_movement":

                self.wrist_baseline_samples = []

            elif self.exercise == "finger_abduction":

                self.abduction_baseline_samples = []

            elif self.exercise == "full_fist":

                self.full_fist_baseline_samples = []

    def add_baseline_sample(
        self,
        distance=None,
        finger_angles=None,
        hand_angle_deg=None,
        abduction=None,
        full_fist_angles=None
    ):

        """
        Registra muestras durante los 3 segundos
        de posicionamiento inicial.

        PINCH:
            distance
            finger_angles

        MUÑECA:
            hand_angle_deg
        """

        with self.lock:

            if self.phase != "POSITIONING":
                return

            # ------------------------------------------
            # PINCH INDEX
            # ------------------------------------------

            if self.exercise == "pinch_index":

                if distance is not None:

                    self.baseline_samples.append(distance)
                    self.all_baseline_samples.append(distance)

                if finger_angles is not None:

                    self.finger_angle_baseline_samples.append(
                        finger_angles.copy()
                    )

            # ------------------------------------------
            # WRIST MOVEMENT
            # ------------------------------------------

            elif self.exercise == "wrist_movement":

                if hand_angle_deg is not None:

                    self.wrist_baseline_samples.append(
                        hand_angle_deg
                    )

                    self.all_wrist_baseline_samples.append(
                        hand_angle_deg
                    )

            # ------------------------------------------
             # ABDUCTION MOVEMENT
            # ------------------------------------------

            elif self.exercise == "finger_abduction" and abduction is not None:

                sample = {
                    "normalized": abduction["normalized"].copy(),
                    "global_opening": abduction["global_opening"]
                }

                self.abduction_baseline_samples.append(sample)
                self.all_abduction_baseline_samples.append(sample)

            
            # ------------------------------------------
            # FULL FIST
            # ------------------------------------------

            elif self.exercise == "full_fist" and full_fist_angles is not None:

                sample = full_fist_angles.copy()

                self.full_fist_baseline_samples.append(sample)
                self.all_full_fist_baseline_samples.append(sample)


    # ==================================================
    # INICIAR REPETICIÓN
    # ==================================================

    def begin_rep(self, rep_number):

        with self.lock:

            if self.status != "RUNNING":
                return

            if self.phase != "POSITIONING":
                return

            self.current_rep = rep_number
            self.phase = "EXECUTING"

            repetition = {
                "number": rep_number,
                "samples": [],

                # Contadores de calidad del seguimiento
                "frames_total": 0,
                "frames_valid": 0
            }

            # ------------------------------------------
            # REFERENCIAS DE PINCH
            # ------------------------------------------

            if self.exercise == "pinch_index":

                repetition["baseline_samples"] = (
                    self.baseline_samples.copy()
                )

                repetition["finger_angle_baseline_samples"] = [
                    angles.copy()
                    for angles in self.finger_angle_baseline_samples
                ]

            # ------------------------------------------
            # REFERENCIA DE MUÑECA
            # ------------------------------------------

            elif self.exercise == "wrist_movement":

                repetition["baseline_samples"] = (
                    self.wrist_baseline_samples.copy()
                )

            # ------------------------------------------
            # REFERENCIA DE ABDUCCIÓN
            # ------------------------------------------

            elif self.exercise == "finger_abduction":

                repetition["baseline_samples"] = [
                    {
                        "normalized": sample["normalized"].copy(),
                        "global_opening": sample["global_opening"]
                    }
                    for sample in self.abduction_baseline_samples
                ]

            
            # ------------------------------------------
            # REFERENCIA DE FULL FIST
            # ------------------------------------------

            elif self.exercise == "full_fist":

                repetition["baseline_samples"] = [
                    sample.copy()
                    for sample in self.full_fist_baseline_samples
                ]


            self.repetitions.append(repetition)

    # ==================================================
    # CALIDAD DE SEGUIMIENTO
    # ==================================================

    def add_frame(self, valid):

        """
        Registra cada frame capturado correctamente
        durante la fase de ejecución, haya o no
        detección válida de la mano.
        """

        with self.lock:

            if (
                self.phase != "EXECUTING"
                or not self.repetitions
            ):
                return

            current = self.repetitions[-1]

            current["frames_total"] += 1

            if valid:
                current["frames_valid"] += 1

    # ==================================================
    # ALMACENAR MUESTRAS
    # ==================================================

    def add_rep_sample(self, sample):

        with self.lock:

            if (
                self.phase != "EXECUTING"
                or not self.repetitions
            ):
                return

            self.repetitions[-1]["samples"].append(sample)

    # ==================================================
    # FINALIZAR REPETICIÓN
    # ==================================================

    def finish_rep(self):

        with self.lock:

            if not self.repetitions:
                return

            current = self.repetitions[-1]

            # ------------------------------------------
            # MÉTRICAS DE PINCH
            # ------------------------------------------

            if self.exercise == "pinch_index":

                current["metrics"] = (
                    calculate_pinch_repetition_metrics(
                        current["samples"],
                        current["baseline_samples"],
                        current["finger_angle_baseline_samples"],
                        frames_total=current["frames_total"],
                        frames_valid=current["frames_valid"]
                    )
                )

            # ------------------------------------------
            # MÉTRICAS DE MUÑECA
            # ------------------------------------------

            elif self.exercise == "wrist_movement":

                current["metrics"] = (
                    calculate_wrist_repetition_metrics(
                        current["samples"],
                        current["baseline_samples"],
                        frames_total=current["frames_total"],
                        frames_valid=current["frames_valid"]
                    )
                )
            # ------------------------------------------
            # MÉTRICAS DE ABDUCCIÓN
            # ------------------------------------------

            elif self.exercise == "finger_abduction":

                reference = calculate_reference_abduction(
                    current["baseline_samples"]
                )

                current["reference_abduction"] = reference

                current["metrics"] = (
                    calculate_abduction_repetition_metrics(
                        current["samples"],
                        reference,
                        frames_total=current["frames_total"],
                        frames_valid=current["frames_valid"]
                    )
                )

            
            # ------------------------------------------
            # MÉTRICAS DE FULL FIST
            # ------------------------------------------

            elif self.exercise == "full_fist":

                reference = calculate_reference_angles(
                    current["baseline_samples"]
                )

                current["reference_angles"] = reference

                current["metrics"] = (
                    calculate_full_fist_repetition_metrics(
                        current["samples"],
                        reference,
                        frames_total=current["frames_total"],
                        frames_valid=current["frames_valid"]
                    )
                )


            self.phase = "WAITING_NEXT"

    # ==================================================
    # COMPLETAR SESIÓN
    # ==================================================

    def complete(self, extra=None):

        with self.lock:

            metrics = [
                rep.get("metrics", {"valid": False})
                for rep in self.repetitions
            ]

            # ------------------------------------------
            # PINCH INDEX
            # ------------------------------------------

            if self.exercise == "pinch_index":

                summary = calculate_pinch_session_metrics(
                    metrics
                )

                baseline_value = (
                    round(median(self.all_baseline_samples), 4)
                    if self.all_baseline_samples
                    else None
                )

                self.result = {
                    "exercise": self.exercise,

                    "total_repetitions": self.total_reps,

                    "baseline_distance": baseline_value,

                    "repetitions": [
                        {
                            "number": rep["number"],
                            **rep.get("metrics", {})
                        }
                        for rep in self.repetitions
                    ],

                    "summary": summary
                }

            # ------------------------------------------
            # WRIST MOVEMENT
            # ------------------------------------------

            elif self.exercise == "wrist_movement":

                summary = calculate_wrist_session_metrics(
                    metrics
                )

                baseline_angle = calculate_reference_angle(
                    self.all_wrist_baseline_samples
                )

                self.result = {
                    "exercise": self.exercise,

                    "total_repetitions": self.total_reps,

                    "baseline_angle_deg": (
                        round(baseline_angle, 2)
                        if baseline_angle is not None
                        else None
                    ),

                    "repetitions": [
                        {
                            "number": rep["number"],
                            **rep.get("metrics", {})
                        }
                        for rep in self.repetitions
                    ],

                    "summary": summary
                }

            # ------------------------------------------
            # FINGER ABDUCTION
            # ------------------------------------------

            elif self.exercise == "finger_abduction":

                summary = calculate_abduction_session_metrics(
                    metrics
                )

                baseline_abduction = calculate_reference_abduction(
                    self.all_abduction_baseline_samples
                )

                self.result = {
                    "exercise": self.exercise,

                    "total_repetitions": self.total_reps,

                    "baseline_abduction": baseline_abduction,

                    "repetitions": [
                        {
                            "number": rep["number"],
                            **rep.get("metrics", {})
                        }
                        for rep in self.repetitions
                    ],

                    "summary": summary
                }

            
            # ------------------------------------------
            # FULL FIST
            # ------------------------------------------

            elif self.exercise == "full_fist":

                summary = calculate_full_fist_session_metrics(
                    metrics
                )

                baseline_angles = calculate_reference_angles(
                    self.all_full_fist_baseline_samples
                )

                self.result = {
                    "exercise": self.exercise,

                    "total_repetitions": self.total_reps,

                    "baseline_angles": baseline_angles,

                    "repetitions": [
                        {
                            "number": rep["number"],
                            **rep.get("metrics", {})
                        }
                        for rep in self.repetitions
                    ],

                    "summary": summary
                }

            if extra and self.result is not None:
                self.result.update(extra)

            self.status = "COMPLETED"
            self.phase = "COMPLETED"

    # ==================================================
    # ERROR
    # ==================================================

    def fail(self, message):

        with self.lock:

            self.status = "ERROR"
            self.phase = "ERROR"
            self.error = message

    # ==================================================
    # CANCELAR
    # ==================================================

    def cancel(self):

        with self.lock:

            if self.status == "RUNNING":

                self.status = "CANCELLED"
                self.phase = "CANCELLED"

    # ==================================================
    # SNAPSHOT
    # ==================================================

    def snapshot(self):

        with self.lock:

            if self.exercise == "wrist_movement":

                baseline_count = len(
                    self.wrist_baseline_samples
                )

            elif self.exercise == "finger_abduction":

                baseline_count = len(
                    self.abduction_baseline_samples
                )

            
            elif self.exercise == "full_fist":

                baseline_count = len(
                    self.full_fist_baseline_samples
                )

            else:

                baseline_count = len(
                    self.baseline_samples
                )

            return {
                "status": self.status,
                "phase": self.phase,

                "exercise": self.exercise,

                "current_rep": self.current_rep,
                "total_reps": self.total_reps,

                "baseline_samples": baseline_count,

                "repetitions_completed": len(
                    self.repetitions
                ),

                "error": self.error,
                "result": self.result
            }
