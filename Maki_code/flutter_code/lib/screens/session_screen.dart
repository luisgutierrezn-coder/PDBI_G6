import 'dart:async';
import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../models/exercise.dart';

class SessionScreen extends StatefulWidget {
  final Patient patient;
  final Exercise exercise;
  final int exerciseNumber;
  final int totalExercises;
  final VoidCallback onNextTask;
  final VoidCallback onNextExercise;
  final VoidCallback onFinishSession;
  final VoidCallback onShowCamera1;
  final VoidCallback onShowCamera2;
  final VoidCallback onShowBothCameras;
  final VoidCallback onHideCameras;
  final bool camera1Visible;
  final bool camera2Visible;
  final int repetitions;
  final Stream<Map<String, dynamic>> angles;

  // Controles del ejercicio desde Python.
  final VoidCallback? onStartCapture;
  final VoidCallback? onPauseCapture;
  final VoidCallback? onResumeCapture;
  final VoidCallback? onRestartCapture;
  final VoidCallback? onStopCapture;

  const SessionScreen({
    super.key,
    required this.patient,
    required this.exercise,
    required this.exerciseNumber,
    required this.totalExercises,
    required this.onNextTask,
    required this.onNextExercise,
    required this.onFinishSession,
    required this.onShowCamera1,
    required this.onShowCamera2,
    required this.onShowBothCameras,
    required this.onHideCameras,
    required this.camera1Visible,
    required this.camera2Visible,
    required this.repetitions,
    required this.angles,
    this.onStartCapture,
    this.onPauseCapture,
    this.onResumeCapture,
    this.onRestartCapture,
    this.onStopCapture,

  });



  @override

  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static const Color primaryColor = Color(0xFF356AE6);
  static const Color darkColor = Color(0xFF202A3C);
  static const Color backgroundColor = Color(0xFFF5F7FB);

  bool _panelOpen = false;
  bool _started = false;
  bool _paused = false;
  bool _completed = false;
  bool _stopped = false;
  bool _captureActive = false;

  late int _repetitions;
  int _currentRepetition = 1;
  int _remainingSeconds = 0;
  int _currentPhaseIndex = 0;
  Timer? _phaseTimer;

  ExercisePhase get _currentExercisePhase =>
      widget.exercise.phases[_currentPhaseIndex];
  final List<double> _pipHistory = [];
  final List<double> _dipHistory = [];

  String? _lastRecordedTimestamp;

  @override

  void initState() {
    super.initState();
    _repetitions = widget.repetitions;
    _currentPhaseIndex = 0;
    if (widget.exercise.phases.isNotEmpty) {
      _remainingSeconds = _phaseDuration(0);
    }
  }

  @override
  void didUpdateWidget(covariant SessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.exercise.id != widget.exercise.id) {
      _phaseTimer?.cancel();
      _phaseTimer = null;
      _currentPhaseIndex = 0;
      _started = false;
      _paused = false;
      _completed = false;
      _stopped = false;
      _captureActive = false;
      _currentRepetition = 1;
      _remainingSeconds = widget.exercise.phases.isNotEmpty
          ? _phaseDuration(0)
          : 0;
      _pipHistory.clear();
      _dipHistory.clear();
      _lastRecordedTimestamp = null;
      _repetitions = widget.repetitions;
    }
  }

  // =====================================================
  // CONTROLES DEL EJERCICIO
  // =====================================================

  void _startExercise() {
    if (_started || widget.exercise.phases.isEmpty) return;

    _phaseTimer?.cancel();

    setState(() {
      _started = true;
      _paused = false;
      _completed = false;
      _stopped = false;
      _currentRepetition = 1;
      _currentPhaseIndex = 0;
      _remainingSeconds = _phaseDuration(0);
      _pipHistory.clear();
      _dipHistory.clear();
      _lastRecordedTimestamp = null;
    });

    _startCapture();
    _startPhaseTimer();
  }

  int _phaseDuration(int index) {
    if (widget.exercise.phases.isEmpty) return 0;
    return widget.exercise.phases[index].duration.clamp(1, 86400).toInt();
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();

    if (!_started || _paused || _completed || _stopped ||
        widget.exercise.phases.isEmpty) {
      return;
    }

    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _paused || _completed || _stopped) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _completeCurrentPhase();
      }
    });
  }

  void _completeCurrentPhase() {
    _phaseTimer?.cancel();
    _phaseTimer = null;

    if (!mounted) return;

    final isLastPhase =
        _currentPhaseIndex >= widget.exercise.phases.length - 1;
    final isLastRepetition = _currentRepetition >= _repetitions;

    if (isLastPhase && isLastRepetition) {
      setState(() {
        _remainingSeconds = 0;
        _completed = true;
        _paused = false;
      });
      _stopCapture();
      return;
    }

    setState(() {
      if (isLastPhase) {
        _currentRepetition++;
        _currentPhaseIndex = 0;
      } else {
        _currentPhaseIndex++;
      }
      _remainingSeconds = _phaseDuration(_currentPhaseIndex);
    });

    _startPhaseTimer();
  }

  void _startCapture() {
    if (_captureActive) return;
    _captureActive = true;
    widget.onStartCapture?.call();
  }

  void _pauseExercise() {
    if (!_started || _paused || _completed || _stopped) return;

    _phaseTimer?.cancel();
    _phaseTimer = null;
    widget.onPauseCapture?.call();

    setState(() {
      _paused = true;
    });
  }

  void _resumeExercise() {
    if (!_paused || _completed || _stopped) return;

    widget.onResumeCapture?.call();

    setState(() {
      _paused = false;
    });

    _startPhaseTimer();
  }

  void _restartRepetition() {
    if (!_started || _completed || _stopped) return;

    _phaseTimer?.cancel();
    widget.onRestartCapture?.call();

    setState(() {
      _paused = false;
      _currentPhaseIndex = 0;
      _remainingSeconds = _phaseDuration(0);
    });

    _startPhaseTimer();
  }

  void _stopExercise() {
    if (!_started || _completed || _stopped) return;

    _phaseTimer?.cancel();
    _phaseTimer = null;
    _stopCapture();

    setState(() {
      _stopped = true;
      _paused = false;
    });
  }

  void _stopCapture() {
    if (!_captureActive) return;
    _captureActive = false;
    widget.onStopCapture?.call();
  }

  // =====================================================
  // ESTADO E INSTRUCCIONES
  // =====================================================

  String get _instructionText {
    if (!_started) {
      return 'Presiona el botón para iniciar el ejercicio.';
    }

    if (_completed) {
      return '¡Ejercicio completado!';
    }

    if (_stopped) {
      return 'El ejercicio ha sido detenido.';
    }

    if (_paused) {
      return 'El ejercicio está pausado.';
    }

    return _currentExercisePhase.instruction;
  }

  String get _phaseLabel {
    if (!_started) return 'Preparado para iniciar';
    if (_completed) return 'Todas las repeticiones completadas';
    if (_stopped) return 'Ejercicio detenido';
    if (_paused) return 'Ejercicio pausado';

    return 'Indicación ${_currentPhaseIndex + 1} de ${widget.exercise.phases.length}';
  }

  // =====================================================
  // DATOS DE MEDICIÓN
  // =====================================================

  Map<String, dynamic> _getExerciseData(

    Map<String, dynamic> data,

  ) {

    if (data['exercise_data'] is Map) {

      return Map<String, dynamic>.from(data['exercise_data']);

    }



    return {

      if (data['pip'] != null) 'pip': data['pip'],

      if (data['dip'] != null) 'dip': data['dip'],

    };

  }



  double? _findMetric(

    Map<String, dynamic> data,

    String target,

  ) {

    for (final entry in data.entries) {

      final key = entry.key.toLowerCase();



      if (key == target.toLowerCase() && entry.value is num) {

        return (entry.value as num).toDouble();

      }



      if (entry.value is Map) {

        final result = _findMetric(

          Map<String, dynamic>.from(entry.value),

          target,

        );



        if (result != null) return result;

      }

    }



    return null;

  }



  void _recordHistory(Map<String, dynamic> data) {

    final timestamp = (

      data['timestamp'] ??

      data['time'] ??

      DateTime.now().millisecondsSinceEpoch

    ).toString();



    if (timestamp == _lastRecordedTimestamp) return;



    final exerciseData = _getExerciseData(data);



    final pip = _findMetric(exerciseData, 'pip');

    final dip = _findMetric(exerciseData, 'dip');



    if (pip == null && dip == null) return;



    _lastRecordedTimestamp = timestamp;



    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (!mounted) return;



      setState(() {

        if (pip != null) {

          _pipHistory.add(pip);

          if (_pipHistory.length > 60) {

            _pipHistory.removeAt(0);

          }

        }



        if (dip != null) {

          _dipHistory.add(dip);

          if (_dipHistory.length > 60) {

            _dipHistory.removeAt(0);

          }

        }

      });

    });

  }



  // =====================================================

  // INTERFAZ PRINCIPAL

  // =====================================================



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: backgroundColor,

      body: SafeArea(

        child: StreamBuilder<Map<String, dynamic>>(

          stream: widget.angles,

          builder: (context, snapshot) {

            final data = snapshot.data ?? {};
            final exerciseData = _getExerciseData(data);
            _recordHistory(data);
            final camera1Detected =
                data['camera1'] is Map &&
                data['camera1']['detected'] == true;

            final camera2Detected =
                data['camera2'] is Map &&
                data['camera2']['detected'] == true;

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMainContent(
                            exerciseData,
                            data,
                          ),
                        ),

                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          width: _panelOpen ? 320 : 0,
                          margin: EdgeInsets.only(
                            left: _panelOpen ? 16 : 0,
                          ),
                          child: _panelOpen
                              ? _buildMeasurementPanel(
                                  exerciseData,
                                  camera1Detected,
                                  camera2Detected,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),



                  const SizedBox(height: 14),

                  _buildBottomControls(),

                ],

              ),

            );

          },

        ),

      ),

    );

  }



  // =====================================================

  // ENCABEZADO

  // =====================================================



  Widget _buildHeader() {

    return Row(

      children: [

        Expanded(

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Text(

                'Sesión de rehabilitación',

                style: TextStyle(

                  fontSize: 24,

                  fontWeight: FontWeight.bold,

                  color: darkColor,

                ),

              ),

              const SizedBox(height: 4),

              Text(

                '${widget.patient.nombre} ${widget.patient.apellido}',

                style: TextStyle(

                  color: Colors.grey.shade600,

                  fontSize: 14,

                ),

              ),

            ],

          ),

        ),



        IconButton(

          tooltip: _panelOpen

              ? 'Ocultar mediciones'

              : 'Mostrar mediciones',

          onPressed: () {

            setState(() {

              _panelOpen = !_panelOpen;

            });

          },

          icon: Icon(

            _panelOpen

                ? Icons.keyboard_double_arrow_right

                : Icons.analytics_outlined,

            color: primaryColor,

            size: 28,

          ),

        ),



        const SizedBox(width: 8),



        TextButton.icon(

          onPressed: widget.onFinishSession,

          icon: const Icon(Icons.stop_circle_outlined),

          label: const Text('Finalizar sesión'),

          style: TextButton.styleFrom(

            foregroundColor: Colors.red,

          ),

        ),

      ],

    );

  }



  // =====================================================

  // CONTENIDO CENTRAL

  // =====================================================



  Widget _buildMainContent(

    Map<String, dynamic> exerciseData,

    Map<String, dynamic> data,

  ) {

    return Column(

      children: [

        Expanded(

          child: Row(

            crossAxisAlignment: CrossAxisAlignment.center,

            children: [

              Expanded(

                flex: 5,

                child: Center(

                  child: AspectRatio(

                    aspectRatio: 1,

                    child: _buildAnimation(),

                  ),

                ),

              ),



              const SizedBox(width: 24),



              Expanded(

                flex: 6,

                child: _buildExerciseInformation(),

              ),

            ],

          ),

        ),

      ],

    );

  }



  // =====================================================

  // ANIMACIÓN

  // =====================================================



  Widget _buildAnimation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: Image.asset(
          _currentExercisePhase.image,
          key: ValueKey(_currentExercisePhase.image),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 72,
                  color: primaryColor,
                ),
                SizedBox(height: 12),
                Text(
                  'No se pudo cargar la imagen',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: darkColor),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // =====================================================

  // INFORMACIÓN E INSTRUCCIONES

  // =====================================================



  Widget _buildExerciseInformation() {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      mainAxisAlignment: MainAxisAlignment.center,

      children: [

        Text(

          widget.exercise.name,

          style: const TextStyle(

            fontSize: 23,

            fontWeight: FontWeight.bold,

            color: primaryColor,

          ),

        ),



        const SizedBox(height: 8),



        Text(

          widget.exercise.description,

          style: TextStyle(

            color: Colors.grey.shade600,

            fontSize: 13,

          ),

        ),



        const SizedBox(height: 24),



        Container(

          width: double.infinity,

          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(

            color: Colors.white,

            borderRadius: BorderRadius.circular(16),

            border: Border.all(

              color: const Color(0xFFE8ECF2),

            ),

          ),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              const Row(

                children: [

                  Icon(

                    Icons.info_outline,

                    color: primaryColor,

                  ),

                  SizedBox(width: 8),

                  Text(

                    'Instrucción actual',

                    style: TextStyle(

                      fontWeight: FontWeight.bold,

                    ),

                  ),

                ],

              ),



              const SizedBox(height: 14),



              Text(

                _instructionText,

                style: const TextStyle(

                  fontSize: 17,

                  fontWeight: FontWeight.w600,

                  color: darkColor,

                ),

              ),



              const SizedBox(height: 14),



              Row(

                crossAxisAlignment: CrossAxisAlignment.end,

                children: [

                  Text(

                    _formatTime(_remainingSeconds),

                    style: const TextStyle(

                      fontSize: 34,

                      fontWeight: FontWeight.bold,

                      color: primaryColor,

                    ),

                  ),



                  const SizedBox(width: 8),



                  Padding(

                    padding: const EdgeInsets.only(bottom: 7),

                    child: Text(

                      'restantes',

                      style: TextStyle(

                        color: Colors.grey.shade600,

                      ),

                    ),

                  ),

                ],

              ),



              const SizedBox(height: 8),



              Text(

                _phaseLabel,

                style: TextStyle(

                  color: Colors.grey.shade600,

                  fontSize: 12,

                ),

              ),

              const SizedBox(height: 12),




              if (_started && !_completed && !_stopped) ...[

                const SizedBox(height: 12),

                Text(

                  'Repetición $_currentRepetition de $_repetitions',

                  style: const TextStyle(

                    color: primaryColor,

                    fontWeight: FontWeight.w600,

                    fontSize: 13,

                  ),

                ),

              ],

            ],

          ),

        ),



        const SizedBox(height: 20),

        const SizedBox(height: 18),

        _buildSessionProgressCompact(),

      ],

    );

  }



  // =====================================================

  // PROGRESO DE SESIÓN

  // =====================================================



  Widget _buildSessionProgressCompact() {

    final progress = widget.totalExercises > 0

        ? widget.exerciseNumber / widget.totalExercises

        : 0.0;



    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(

          mainAxisAlignment: MainAxisAlignment.spaceBetween,

          children: [

            const Text(

              'Progreso de la sesión',

              style: TextStyle(

                fontWeight: FontWeight.w600,

              ),

            ),



            Text(

              '${widget.exerciseNumber} de ${widget.totalExercises}',

              style: TextStyle(

                color: Colors.grey.shade700,

                fontSize: 12,

              ),

            ),

          ],

        ),



        const SizedBox(height: 8),



        ClipRRect(

          borderRadius: BorderRadius.circular(10),

          child: LinearProgressIndicator(

            value: progress.clamp(0.0, 1.0),

            minHeight: 8,

            backgroundColor: const Color(0xFFE8ECF2),

            color: primaryColor,

          ),

        ),

      ],

    );

  }



  // =====================================================

  // PANEL LATERAL DE MEDICIONES

  // =====================================================



  Widget _buildMeasurementPanel(

    Map<String, dynamic> exerciseData,

    bool camera1Detected,

    bool camera2Detected,

  ) {

    final metrics = _flattenMetrics(exerciseData);



    return Container(

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(

          color: const Color(0xFFE8ECF2),

        ),

      ),

      padding: const EdgeInsets.all(16),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Text(

            'Mediciones',

            style: TextStyle(

              fontSize: 19,

              fontWeight: FontWeight.bold,

              color: darkColor,

            ),

          ),



          const SizedBox(height: 4),



          Text(

            'Parámetros del movimiento',

            style: TextStyle(

              fontSize: 12,

              color: Colors.grey.shade600,

            ),

          ),



          const SizedBox(height: 16),



          Expanded(

            child: SingleChildScrollView(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  if (metrics.isEmpty)

                    _emptyMeasurements()

                  else ...[

                    ...metrics.map(_buildMetricBar),

                    const SizedBox(height: 20),

                    _buildAngleChart(),

                  ],



                  const SizedBox(height: 20),

                  const Divider(),



                  const Text(

                    'Estado de cámaras',

                    style: TextStyle(

                      fontWeight: FontWeight.bold,

                    ),

                  ),



                  const SizedBox(height: 12),



                  _cameraStatus(

                    'Cámara 1',

                    camera1Detected,

                    widget.camera1Visible,

                  ),



                  const SizedBox(height: 8),



                  _cameraStatus(

                    'Cámara 2',

                    camera2Detected,

                    widget.camera2Visible,

                  ),



                  const SizedBox(height: 12),



                  Wrap(

                    spacing: 6,

                    runSpacing: 6,

                    children: [

                      _cameraButton(

                        'Cámara 1',

                        widget.onShowCamera1,

                      ),

                      _cameraButton(

                        'Cámara 2',

                        widget.onShowCamera2,

                      ),

                      _cameraButton(

                        'Ambas',

                        widget.onShowBothCameras,

                      ),

                      _cameraButton(

                        'Ocultar',

                        widget.onHideCameras,

                      ),

                    ],

                  ),

                ],

              ),

            ),

          ),

        ],

      ),

    );

  }



  // =====================================================

  // EXTRAER MEDICIONES NUMÉRICAS

  // =====================================================



  List<_Metric> _flattenMetrics(

    Map<String, dynamic> data, [

    String prefix = '',

  ]) {

    final result = <_Metric>[];



    for (final entry in data.entries) {

      final key = entry.key;

      final value = entry.value;



      if ([

        'timestamp',

        'time',

        'exercise',

      ].contains(key.toLowerCase())) {

        continue;

      }



      final label = prefix.isEmpty ? key : '$prefix $key';



      if (value is num) {

        result.add(

          _Metric(

            label: label,

            value: value.toDouble(),

          ),

        );

      } else if (value is Map) {

        result.addAll(

          _flattenMetrics(

            Map<String, dynamic>.from(value),

            label,

          ),

        );

      }

    }



    return result;

  }



  Widget _buildMetricBar(_Metric metric) {

    final key = metric.label.toLowerCase();



    final isAngle =

        key.contains('pip') ||

        key.contains('dip') ||

        key.contains('mcp') ||

        key.contains('angle') ||

        key.contains('angulo');



    final isDistance =

        key.contains('distance') || key.contains('distancia');



    final maximum = isAngle

        ? 180.0

        : isDistance

            ? 10.0

            : 100.0;



    final progress = (metric.value / maximum).clamp(0.0, 1.0);



    final unit = isAngle

        ? '°'

        : isDistance

            ? ' cm'

            : '';



    return Padding(

      padding: const EdgeInsets.only(bottom: 16),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [

              Expanded(

                child: Text(

                  _formatLabel(metric.label),

                  style: const TextStyle(fontSize: 12),

                ),

              ),



              Text(

                '${metric.value.toStringAsFixed(1)}$unit',

                style: const TextStyle(

                  fontWeight: FontWeight.bold,

                  color: primaryColor,

                ),

              ),

            ],

          ),



          const SizedBox(height: 7),



          ClipRRect(

            borderRadius: BorderRadius.circular(10),

            child: LinearProgressIndicator(

              value: progress,

              minHeight: 11,

              backgroundColor: const Color(0xFFE8ECF2),

              color: primaryColor,

            ),

          ),

        ],

      ),

    );

  }



  // =====================================================

  // GRÁFICO DE ÁNGULOS

  // =====================================================



  Widget _buildAngleChart() {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        const Text(

          'Evolución de ángulos',

          style: TextStyle(

            fontWeight: FontWeight.bold,

          ),

        ),



        const SizedBox(height: 12),



        Container(

          height: 150,

          width: double.infinity,

          padding: const EdgeInsets.all(10),

          decoration: BoxDecoration(

            color: backgroundColor,

            borderRadius: BorderRadius.circular(12),

          ),

          child: CustomPaint(

            painter: _AngleChartPainter(

              pipValues: List<double>.from(_pipHistory),

              dipValues: List<double>.from(_dipHistory),

            ),

            child: const SizedBox.expand(),

          ),

        ),



        const SizedBox(height: 10),



        const Row(

          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Icon(

              Icons.circle,

              size: 9,

              color: Color(0xFF356AE6),

            ),

            SizedBox(width: 5),

            Text('PIP', style: TextStyle(fontSize: 11)),

            SizedBox(width: 18),

            Icon(

              Icons.circle,

              size: 9,

              color: Color(0xFF16A085),

            ),

            SizedBox(width: 5),

            Text('DIP', style: TextStyle(fontSize: 11)),

          ],

        ),

      ],

    );

  }



  // =====================================================

  // CÁMARAS

  // =====================================================



  Widget _cameraStatus(

    String name,

    bool detected,

    bool visible,

  ) {

    return Row(

      children: [

        Icon(

          Icons.circle,

          size: 10,

          color: detected ? Colors.green : Colors.grey,

        ),



        const SizedBox(width: 8),



        Expanded(

          child: Text(

            name,

            style: const TextStyle(fontSize: 12),

          ),

        ),



        Text(

          detected

              ? 'Mano detectada'

              : visible

                  ? 'Sin detección'

                  : 'Oculta',

          style: TextStyle(

            fontSize: 10,

            color: detected ? Colors.green : Colors.grey,

          ),

        ),

      ],

    );

  }



  Widget _cameraButton(

    String label,

    VoidCallback callback,

  ) {

    return OutlinedButton(

      onPressed: callback,

      style: OutlinedButton.styleFrom(

        padding: const EdgeInsets.symmetric(

          horizontal: 9,

          vertical: 7,

        ),

        minimumSize: Size.zero,

        tapTargetSize: MaterialTapTargetSize.shrinkWrap,

      ),

      child: Text(

        label,

        style: const TextStyle(fontSize: 10),

      ),

    );

  }



  Widget _emptyMeasurements() {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(

        color: backgroundColor,

        borderRadius: BorderRadius.circular(12),

      ),

      child: const Text(

        'Esperando datos del ejercicio...',

        textAlign: TextAlign.center,

        style: TextStyle(fontSize: 12),

      ),

    );

  }



  // =====================================================

  // CONTROLES INFERIORES

  // =====================================================



  Widget _buildBottomControls() {

    final canGoNext = _completed || _stopped;



    return Container(

      padding: const EdgeInsets.symmetric(

        horizontal: 14,

        vertical: 12,

      ),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(

          color: const Color(0xFFE8ECF2),

        ),

      ),

      child: Row(

        children: [

          if (!_started)

            Expanded(

              child: ElevatedButton.icon(

                onPressed: _startExercise,

                icon: const Icon(Icons.play_arrow),

                label: const Text('Iniciar ejercicio'),

                style: _primaryButtonStyle(),

              ),

            )

          else ...[

            Expanded(

              child: OutlinedButton.icon(

                onPressed: (_completed || _stopped)

                    ? null

                    : _paused

                        ? _resumeExercise

                        : _pauseExercise,

                icon: Icon(

                  _paused ? Icons.play_arrow : Icons.pause,

                ),

                label: Text(

                  _paused ? 'Continuar' : 'Pausar',

                ),

              ),

            ),



            const SizedBox(width: 8),



            Expanded(

              child: OutlinedButton.icon(

                onPressed: canGoNext ? null : _restartRepetition,

                icon: const Icon(Icons.replay),

                label: const Text('Reiniciar repetición'),

              ),

            ),



            const SizedBox(width: 8),



            Expanded(

              child: OutlinedButton.icon(

                onPressed: canGoNext ? null : _stopExercise,

                icon: const Icon(Icons.stop),

                label: const Text('Detener'),

                style: OutlinedButton.styleFrom(

                  foregroundColor: Colors.red,

                ),

              ),

            ),

          ],



          const SizedBox(width: 8),



          Expanded(

            child: ElevatedButton.icon(

              onPressed: canGoNext

                  ? widget.onNextExercise

                  : null,

              icon: Icon(

                widget.exerciseNumber == widget.totalExercises

                    ? Icons.flag_outlined

                    : Icons.arrow_forward,

              ),

              label: Text(

                widget.exerciseNumber == widget.totalExercises

                    ? 'Terminar ejercicios'

                    : 'Siguiente ejercicio',

              ),

              style: _primaryButtonStyle(),

            ),

          ),



          if (widget.exercise.id == 'pincer_grasp') ...[

            const SizedBox(width: 8),

            IconButton(

              tooltip: 'Siguiente tarea',

              onPressed: widget.onNextTask,

              icon: const Icon(Icons.skip_next),

            ),

          ],

        ],

      ),

    );

  }



  ButtonStyle _primaryButtonStyle() {

    return ElevatedButton.styleFrom(

      backgroundColor: primaryColor,

      foregroundColor: Colors.white,

      disabledBackgroundColor: Colors.grey.shade300,

      disabledForegroundColor: Colors.grey.shade600,

      padding: const EdgeInsets.symmetric(vertical: 16),

    );

  }



  // =====================================================

  // UTILIDADES

  // =====================================================



  @override
  void dispose() {
    _phaseTimer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {

    final minutes = seconds ~/ 60;

    final remaining = seconds % 60;



    return '${minutes.toString().padLeft(2, '0')}:'

        '${remaining.toString().padLeft(2, '0')}';

  }



  String _formatLabel(String label) {

    final formatted = label

        .replaceAll('_', ' ')

        .replaceAll('-', ' ');



    if (formatted.isEmpty) return formatted;



    return formatted[0].toUpperCase() + formatted.substring(1);

  }

}



// =======================================================

// MODELO SIMPLE PARA LAS MEDICIONES

// =======================================================



class _Metric {

  final String label;

  final double value;



  const _Metric({

    required this.label,

    required this.value,

  });

}



// =======================================================

// GRÁFICO PERSONALIZADO

// =======================================================



class _AngleChartPainter extends CustomPainter {

  final List<double> pipValues;

  final List<double> dipValues;



  _AngleChartPainter({

    required this.pipValues,

    required this.dipValues,

  });



  @override

  void paint(Canvas canvas, Size size) {

    const leftPadding = 5.0;

    const rightPadding = 5.0;

    const topPadding = 8.0;

    const bottomPadding = 8.0;



    final chartWidth = size.width - leftPadding - rightPadding;

    final chartHeight = size.height - topPadding - bottomPadding;



    final gridPaint = Paint()

      ..color = Colors.grey.withValues(alpha: 0.2)

      ..strokeWidth = 1;



    for (int i = 0; i <= 4; i++) {

      final y = topPadding + chartHeight * i / 4;



      canvas.drawLine(

        Offset(leftPadding, y),

        Offset(size.width - rightPadding, y),

        gridPaint,

      );

    }



    _drawLine(

      canvas,

      pipValues,

      chartWidth,

      chartHeight,

      leftPadding,

      topPadding,

      const Color(0xFF356AE6),

    );



    _drawLine(

      canvas,

      dipValues,

      chartWidth,

      chartHeight,

      leftPadding,

      topPadding,

      const Color(0xFF16A085),

    );

  }



  void _drawLine(

    Canvas canvas,

    List<double> values,

    double chartWidth,

    double chartHeight,

    double left,

    double top,

    Color color,

  ) {

    if (values.length < 2) return;



    final paint = Paint()

      ..color = color

      ..strokeWidth = 2.2

      ..style = PaintingStyle.stroke

      ..strokeCap = StrokeCap.round;



    final path = Path();



    for (int i = 0; i < values.length; i++) {

      final x = left + chartWidth * i / (values.length - 1);



      final normalized = values[i].clamp(0.0, 180.0) / 180.0;

      final y = top + chartHeight * (1 - normalized);



      if (i == 0) {

        path.moveTo(x, y);

      } else {

        path.lineTo(x, y);

      }

    }



    canvas.drawPath(path, paint);

  }



  @override

  bool shouldRepaint(covariant _AngleChartPainter oldDelegate) {

    return oldDelegate.pipValues != pipValues ||

        oldDelegate.dipValues != dipValues;

  }

}
