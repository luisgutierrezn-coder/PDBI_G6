
import '../models/exercise.dart';

final Map<String, Exercise> exercises = {

  'finger_abduction': Exercise(
    id: 'finger_abduction',
    name: 'Finger Abduction',
    description: 'Abducción y aducción de los dedos.',
    phases: [
      ExercisePhase(
        title: 'Cerrar la mano',
        instruction: 'Junta los dedos de la mano lateralmente',
        duration: 5,
        image: 'assets/images/close.png',
      ),
      ExercisePhase(
        title: 'Abrir la mano',
        instruction: 'Extiende todos los dedos de la mano lateralmente.',
        duration: 5,
        image: 'assets/images/open.png',
      ),
      
    ],
  ),

  'pinch_index': Exercise(
    id: 'pinch_index',
    name: 'Pinza',
    description: 'Movimiento de pinza con el pulgar y el indice.',
    phases: [
      ExercisePhase(
        title: 'Preparar la mano',
        instruction: 'Mantén la mano relajada y los dedos extendidos.',
        duration: 5,
        image: 'assets/images/close.png',
      ),
      ExercisePhase(
        title: 'Realizar la pinza',
        instruction: 'Une la punta del pulgar con la punta del índice.',
        duration: 5,
        image: 'assets/images/pincer_thumb.png',
      ),
    ],
  ),

  'full_fist': Exercise(
    id: 'full_fist',
    name: 'Puño',
    description: 'Movimiento de formación de puño.',
    phases: [
      ExercisePhase(
        title: 'Preparar la mano',
        instruction: 'Mantén la mano relajada y los dedos extendidos.',
        duration: 5,
        image: 'assets/images/close.png',
      ),
      ExercisePhase(
        title: 'Formar el puño',
        instruction: 'Cierra la mano con todos los dedos formando un puño.',
        duration: 5,
        image: 'assets/images/fist_my_bump.png',
      ),
    ],
  ),

  'wrist_movement': Exercise(
    id: 'wrist_movement',
    name: 'Muñeca',
    description: 'Flexión y extensión de la muñeca',
    phases: [
      ExercisePhase(
        title: 'Preparar la mano',
        instruction: 'Mantén la mano relajada, dedos juntos y con dirección perpendicular a la cámara',
        duration: 5,
        image: 'assets/images/pincer_grasp/start.png',
      ),
      ExercisePhase(
        title: 'Mueve la muñeca',
        instruction: 'Extiende y luego flexiona la muñeca',
        duration: 5,
        image: 'assets/images/pincer_grasp/pinch.png',
      ),
    ],
  ),

};
