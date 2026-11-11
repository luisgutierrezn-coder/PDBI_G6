
import '../models/exercise.dart';

final Map<String, Exercise> exercises = {

  'open_close': Exercise(
    id: 'open_close',
    name: 'Open Close',
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

  'pincer_grasp': Exercise(
    id: 'pincer_grasp',
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

  'fist_my_bump': Exercise(
    id: 'fist_my_bump',
    name: 'Puño',
    description: 'Movimiento de formación de puño.',
    phases: [
      ExercisePhase(
        title: 'Preparar la mano',
        instruction: 'Mantén la mano relajada y los dedos extendidos.',
        duration: 5,
        image: 'assets/images/pincer_grasp/start.png',
      ),
      ExercisePhase(
        title: 'Realizar la pinza',
        instruction: 'Une la punta del pulgar con la punta del índice.',
        duration: 5,
        image: 'assets/images/pincer_grasp/pinch.png',
      ),
    ],
  ),

  'wrist': Exercise(
    id: 'pincer_grasp',
    name: 'Pinza',
    description: 'Movimiento de pinza con el pulgar y el dedo indicado.',
    phases: [
      ExercisePhase(
        title: 'Preparar la mano',
        instruction: 'Mantén la mano relajada y los dedos extendidos.',
        duration: 5,
        image: 'assets/images/pincer_grasp/start.png',
      ),
      ExercisePhase(
        title: 'Realizar la pinza',
        instruction: 'Une la punta del pulgar con la punta del índice.',
        duration: 5,
        image: 'assets/images/pincer_grasp/pinch.png',
      ),
    ],
  ),

};
