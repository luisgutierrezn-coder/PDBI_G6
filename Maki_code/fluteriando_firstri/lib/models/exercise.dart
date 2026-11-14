class ExercisePhase {
  final String title;
  final String instruction;
  final int duration;
  final String image;

  const ExercisePhase({
    required this.title,
    required this.instruction,
    required this.duration,
    required this.image,
  });
}

class Exercise {
  final String id;
  final String name;
  final String description;
  final List<ExercisePhase> phases;

  const Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.phases,
  });
}
