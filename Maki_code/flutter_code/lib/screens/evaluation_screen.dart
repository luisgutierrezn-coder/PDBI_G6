
// ignore_for_file: unused_element

import 'package:flutter/material.dart';

import '../models/patient.dart';
import '../models/exercise.dart';
import '../data/exercises_data.dart';
import '../services/python_service.dart';
import 'session_screen.dart';

class EvaluationScreen extends StatefulWidget {
  final Patient? patient;

  const EvaluationScreen({
    super.key,
    this.patient,
  });

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  late final PythonService _python;
  late final Stream<Map<String, dynamic>> _angles;

  bool _sessionStarted = false;

  int _currentExerciseIndex = 0;

  bool _camera1Visible = false;
  bool _camera2Visible = false;

  // Información visual de los ejercicios.
  // Las instrucciones y fases se encuentran en exercises_data.dart.
  final List<Map<String, dynamic>> _exerciseDisplay = [
    {
      'id': 'open_close',
      'icon': Icons.back_hand_outlined,
    },
    {
      'id': 'pincer_grasp',
      'icon': Icons.touch_app_outlined,
    },
    {
      'id': 'fist_my_bump',
      'icon': Icons.pan_tool_alt_outlined,
    },
    {
      'id': 'wrist',
      'icon': Icons.front_hand_outlined,
    },
  ];

  // Ejercicios seleccionados y su cantidad de repeticiones.
  final List<String> _selectedExercises = [];

  final Map<String, int> _exerciseRepetitions = {};

  static const int _defaultRepetitions = 3;
  static const int _minRepetitions = 1;
  static const int _maxRepetitions = 10;

  @override
  void initState() {
    super.initState();

    _python = PythonService();
    _angles = _python.angles;
  }

  // ==========================================
  // PACIENTE
  // ==========================================

  String _formatDate(DateTime? date) {
    if (date == null) return 'No registrada';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Widget _buildPatientCard() {
    final patient = widget.patient;

    if (patient == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: Colors.orange,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No hay ningún paciente seleccionado. '
                'Selecciona un paciente desde la sección Pacientes.',
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: Color(0xFF356AE6),
                ),
                SizedBox(width: 8),
                Text(
                  'Paciente seleccionado',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${patient.nombre} ${patient.apellido}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF356AE6),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                _patientInfo('DNI', patient.dni),
                _patientInfo('Edad', '${patient.edad} años'),
                _patientInfo(
                  'Fecha del ACV',
                  _formatDate(patient.fechaAcv),
                ),
                _patientInfo('Mano afectada', patient.manoAcv),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _patientInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SELECCIÓN DE EJERCICIOS
  // ==========================================

  void _toggleExercise(String id) {
    setState(() {
      if (_selectedExercises.contains(id)) {
        _selectedExercises.remove(id);
        _exerciseRepetitions.remove(id);
      } else {
        _selectedExercises.add(id);
        _exerciseRepetitions[id] = _defaultRepetitions;
      }
    });
  }

  void _changeRepetitions(String id, int repetitions) {
    setState(() {
      _exerciseRepetitions[id] = repetitions;
    });
  }

  int _getRepetitions(String id) {
    return _exerciseRepetitions[id] ?? _defaultRepetitions;
  }

  void _reorderExercises(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex--;
      }

      final exercise = _selectedExercises.removeAt(oldIndex);
      _selectedExercises.insert(newIndex, exercise);
    });
  }

  Exercise _getExercise(String id) {
    final exercise = exercises[id];

    if (exercise == null) {
      throw StateError(
        'No se encontró el ejercicio "$id" en exercises_data.dart',
      );
    }

    return exercise;
  }

Map<String, dynamic> _getExerciseDisplay(String id) {
    return _exerciseDisplay.firstWhere(
      (exercise) => exercise['id'] == id,
    );
  }

  // ==========================================
  // INICIAR Y CONTROLAR SESIÓN
  // ==========================================

  void _startSession() {
    if (widget.patient == null) {
      _showMessage('Primero selecciona un paciente.');
      return;
    }

    if (_selectedExercises.isEmpty) {
      _showMessage('Selecciona al menos un ejercicio.');
      return;
    }

    setState(() {
      _currentExerciseIndex = 0;
      _sessionStarted = true;
    });

    final firstExercise = _selectedExercises.first;
    _python.startExercise(firstExercise);
  }

  void _nextTask() {
    _python.nextTask();
  }

  void _nextExercise() {
    if (_currentExerciseIndex >= _selectedExercises.length - 1) {
      _endSession();
      return;
    }

    _python.finishExercise();

    setState(() {
      _currentExerciseIndex++;
    });

    final nextExercise = _selectedExercises[_currentExerciseIndex];
    _python.startExercise(nextExercise);
  }

  void _endSession() {
    _python.finishExercise();

    setState(() {
      _sessionStarted = false;
      _currentExerciseIndex = 0;
      _camera1Visible = false;
      _camera2Visible = false;
    });

    _showMessage('Sesión finalizada.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ==========================================
  // CÁMARAS
  // ==========================================

  void _showCamera1() {
    _python.showCamera1();

    setState(() {
      _camera1Visible = true;
      _camera2Visible = false;
    });
  }

  void _showCamera2() {
    _python.showCamera2();

    setState(() {
      _camera1Visible = false;
      _camera2Visible = true;
    });
  }

  void _showBothCameras() {
    _python.showBothCameras();

    setState(() {
      _camera1Visible = true;
      _camera2Visible = true;
    });
  }

  void _hideCameras() {
    _python.hideCameras();

    setState(() {
      _camera1Visible = false;
      _camera2Visible = false;
    });
  }

  @override
  void dispose() {
    _python.close();
    super.dispose();
  }

  // ==========================================
  // INTERFAZ
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_sessionStarted) {
      final currentId = _selectedExercises[_currentExerciseIndex];

      final currentExercise = _getExercise(currentId);

      return SessionScreen(
        patient: widget.patient!,
        exercise: currentExercise,
        repetitions: _getRepetitions(currentId),
        exerciseNumber: _currentExerciseIndex + 1,
        totalExercises: _selectedExercises.length,

        onNextTask: _nextTask,
        onNextExercise: _nextExercise,
        onFinishSession: _endSession,

        onShowCamera1: _showCamera1,
        onShowCamera2: _showCamera2,
        onShowBothCameras: _showBothCameras,
        onHideCameras: _hideCameras,

        camera1Visible: _camera1Visible,
        camera2Visible: _camera2Visible,

        angles: _angles,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nueva evaluación',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF202A3C),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configura los ejercicios que se realizarán durante la sesión.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),

              _buildPatientCard(),

              const SizedBox(height: 28),

              const Text(
                'Seleccionar ejercicios',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF202A3C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Selecciona los ejercicios y configura sus repeticiones.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 14),

              ..._exerciseDisplay.map((display) {
                final id = display['id'] as String;
                final exercise = _getExercise(id);
                final selected = _selectedExercises.contains(id);

                return _buildExerciseCard(
                  exercise,
                  display['icon'] as IconData,
                  selected,
                );
              }),

              const SizedBox(height: 28),

              if (_selectedExercises.isNotEmpty) ...[
                const Text(
                  'Orden de los ejercicios',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF202A3C),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Arrastra los ejercicios para cambiar el orden.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),

                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedExercises.length,
                  onReorderItem: _reorderExercises,
                  itemBuilder: (context, index) {
                    final id = _selectedExercises[index];
                    final exercise = _getExercise(id);

                    return Card(
                      key: ValueKey(exercise.id),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE5ECFF),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Color(0xFF356AE6),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(exercise.name),
                        subtitle: Text(
                          '${_getRepetitions(id)} repeticiones',
                        ),
                        trailing: const Icon(Icons.drag_handle),
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _startSession,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    'Iniciar sesión (${_selectedExercises.length} ejercicios)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF356AE6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TARJETA DE EJERCICIO
  // ==========================================

  Widget _buildExerciseCard(
    Exercise exercise,
    IconData icon,
    bool selected,
  ) {
    final id = exercise.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? const Color(0xFFEAF1FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? const Color(0xFF356AE6)
              : const Color(0xFFE8ECF2),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF356AE6),
              size: 28,
            ),

            const SizedBox(width: 14),

            Expanded(
              child: InkWell(
                onTap: () => _toggleExercise(id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exercise.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (selected) ...[
              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF356AE6),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _getRepetitions(id),
                    isDense: true,
                    items: List.generate(
                      _maxRepetitions - _minRepetitions + 1,
                      (index) {
                        final value = index + _minRepetitions;

                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value'),
                        );
                      },
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        _changeRepetitions(id, value);
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(width: 4),
            ],

            Checkbox(
              value: selected,
              activeColor: const Color(0xFF356AE6),
              onChanged: (_) => _toggleExercise(id),
            ),
          ],
        ),
      ),
    );
  }
}
