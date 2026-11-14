
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_service.dart';
import '../services/device_service.dart';

import '../models/patient.dart';
import 'dart:convert';

// --------------------------------------------------
// MODELO DE DATOS DE UNA SESIÓN
// --------------------------------------------------

class ProgressSession {
  final DateTime date;

  // Fuerza máxima respecto a la fuerza basal (%)
  final double maxStrengthPercent;

  // Rango de movimiento de cada dedo (grados)
  final Map<String, double> fingerRomDegrees;

  // Independencia en movimiento de pinza (%)
  final double pinchIndependencePercent;

  // Rango de movimiento de muñeca (grados)
  final double wristRomDegrees;

  const ProgressSession({
    required this.date,
    required this.maxStrengthPercent,
    required this.fingerRomDegrees,
    required this.pinchIndependencePercent,
    required this.wristRomDegrees,
  });
}

// --------------------------------------------------
// PANTALLA DE PROGRESO
// --------------------------------------------------


class ProgressScreen extends StatefulWidget {
  final Patient? patient;
  final List<ProgressSession>? sessions;

  const ProgressScreen({
    super.key,
    this.patient,
    this.sessions,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<ProgressSession> progressData = [];

  // Controla si el historial reciente está desplegado
  bool _recentSessionsExpanded = false;

  bool _isLoading = false;
  String? _errorMessage;

  // Sesiones reales de rehabilitación
  List<Map<String, dynamic>> realSessions = [];

  // Sesiones de terapia (conjunto de ejercicios)
  List<Map<String, dynamic>> therapySessions = [];

  // Actividad muscular (EMG)
  Map<String, dynamic>? _emg;
  String? _errorEmg;
  List<Map<String, dynamic>> _calibraciones = [];


  String get patientName {
    if (widget.patient == null) return 'Ningún paciente seleccionado';

    return '${widget.patient!.nombre} ${widget.patient!.apellido}';
  }

  @override
  void initState() {
    super.initState();

    if (widget.sessions != null) {
      progressData = widget.sessions!;
    } else {
      _loadProgress();
    }
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.patient?.id != widget.patient?.id ||
        oldWidget.sessions != widget.sessions) {
      if (widget.sessions != null) {
        setState(() {
          progressData = widget.sessions!;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        _loadProgress();
      }
    }
  }

  // Consultar las sesiones del paciente en SQLite.
  Future<void> _loadProgress() async {
    if (widget.patient?.id == null) {
      setState(() {
        progressData = [];
        realSessions = [];
        therapySessions = [];
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final patientId = widget.patient!.id!;

      // Obtener todas las sesiones
      final records = await DatabaseService.instance.getSessions(
        patientId,
      );

      // Separar sesiones demostrativas
      final demoRecords = records.where(
        (session) => session['session_type'] != 'real',
      ).toList();

      // Obtener sesiones reales
      final realRecords = await DatabaseService.instance
          .getRealSessions(patientId);

      final therapyRecords = await DatabaseService.instance
          .getTherapySessions(patientId);

      final calibrationRecords = await DatabaseService.instance
          .getEmgCalibrations(patientId);

      final List<ProgressSession> loadedSessions = [];

      // Procesar únicamente las sesiones demostrativas
      for (final session in demoRecords) {
        final sessionId = session['id'] as int;

        final fingerRecords = await DatabaseService.instance
            .getFingerMeasurements(sessionId);

        final Map<String, double> fingerMeasurements = {
          for (final finger in fingerRecords)
            finger['finger'] as String:
                (finger['rom_degrees'] as num).toDouble(),
        };

        loadedSessions.add(
          ProgressSession(
            date: DateTime.parse(
              session['session_date'] as String,
            ),
            maxStrengthPercent:
                (session['max_strength_percent'] as num?)
                        ?.toDouble() ??
                    0.0,
            fingerRomDegrees: fingerMeasurements,
            pinchIndependencePercent:
                (session['pinch_independence_percent'] as num?)
                        ?.toDouble() ??
                    0.0,
            wristRomDegrees:
                (session['wrist_rom_degrees'] as num?)
                        ?.toDouble() ??
                    0.0,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        progressData = loadedSessions;
        realSessions = realRecords;
        therapySessions = therapyRecords;
        _calibraciones = calibrationRecords;
        _isLoading = false;
      });

      _cargarEmg();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar el progreso: $e';
      });
    }
  }

  
  @override
  Widget build(BuildContext context) {
    final data = progressData;

    // Estado de carga
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Estado de error
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text(_errorMessage!),
        ),
      );
    }

    // Sin sesiones registradas
    if (data.isEmpty && realSessions.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No hay sesiones registradas para $patientName',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadProgress,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      );
    }

    // 1. Datos de fuerza máxima
    final strengthData = [
      _ChartSeries(
        name: 'Fuerza máxima',
        color: const Color(0xFF3978B8),
        values: data.map((s) => s.maxStrengthPercent).toList(),
      ),
    ];

    // 2. Datos de movilidad de los dedos
    final fingerColors = [
      const Color(0xFFE57373),
      const Color(0xFF64B5F6),
      const Color(0xFF81C784),
      const Color(0xFFFFB74D),
      const Color(0xFFBA68C8),
    ];

    const fingerNames = [
      'Pulgar',
      'Índice',
      'Medio',
      'Anular',
      'Meñique',
    ];

    final fingerData = List.generate(
      fingerNames.length,
      (index) {
        final fingerName = fingerNames[index];

        return _ChartSeries(
          name: fingerName,
          color: fingerColors[index],
          values: data.map(
            (session) =>
                session.fingerRomDegrees[fingerName] ?? 0.0,
          ).toList(),
        );
      },
    );

    // 3. Datos de independencia de pinza
    final pinchData = [
      _ChartSeries(
        name: 'Independencia de pinza',
        color: const Color(0xFF26A69A),
        values: data
            .map((s) => s.pinchIndependencePercent)
            .toList(),
      ),
    ];

    // 5. Evolución de excursión angular de full_fist
    final fullFistData = _getFullFistChartData();

    final hasFullFistData = fullFistData.isNotEmpty &&
        fullFistData.first.values.any((v) => v != null);
    
    final pinchIndexData = _getPinchIndexChartData();

    final abductionData = _getFingerAbductionChartData();

    final wristData = _getWristMovementChartData();

    final abductionGlobalValues =
    abductionData[0].values.whereType<double>().toList();

    final abductionPairValues = abductionData
        .skip(1)
        .expand((series) => series.values)
        .whereType<double>()
        .toList();

    final wristValues = wristData
        .expand((series) => series.values)
        .whereType<double>()
        .toList();

    final hasAbductionData =
        abductionGlobalValues.isNotEmpty ||
        abductionPairValues.isNotEmpty;

    final hasWristData = wristValues.isNotEmpty;

    final excursionValues =
        pinchIndexData[0].values.whereType<double>().toList();

    final jerkValues =
        pinchIndexData[1].values.whereType<double>().toList();

    final compensatoryValues =
        pinchIndexData[2].values.whereType<double>().toList();

    double calculateMax(List<double> values) {
      if (values.isEmpty) return 1;

      final maximum = values.reduce(
        (a, b) => a > b ? a : b,
      );

      return maximum > 0 ? maximum * 1.2 : 1;
    }

    final abductionGlobalMax = calculateMax(abductionGlobalValues);
    final abductionPairMax = calculateMax(abductionPairValues);
    final wristMax = calculateMax(wristValues);

    final excursionMax = calculateMax(excursionValues);
    final jerkMax = calculateMax(jerkValues);
    final compensatoryMax = calculateMax(compensatoryValues);

    final hasPinchIndexData =
        excursionValues.isNotEmpty ||
        jerkValues.isNotEmpty ||
        compensatoryValues.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(data.length + _sessionGroups().length),

                  const SizedBox(height: 24),

                  if (realSessions.isNotEmpty) ...[
                    _buildRealSessionsSection(),
                    const SizedBox(height: 24),
                  ],

                  
                  if (hasFullFistData) ...[
                    const SizedBox(height: 24),

                    _buildChartCard(
                      title: 'Evolución de movilidad de los dedos',
                      subtitle:
                          'Excursión angular media durante el cierre completo del puño',
                      unit: 'Grados (°)',
                      color: const Color(0xFF3978B8),
                      minY: 0,
                      maxY: 180,
                      data: fullFistData,
                      dates: _exerciseDates('full_fist'),
                    ),
                  ],
                  if (hasPinchIndexData) ...[
                    // ------------------------------------------
                    // EXCURSIÓN MEDIA DE PINZA
                    // ------------------------------------------

                    if (pinchIndexData[0].values.any((v) => v != null)) ...[
                      const SizedBox(height: 24),

                      _buildChartCard(
                        title: 'Evolución de la excursión de pinza',
                        subtitle:
                            'Cambio medio de distancia entre la posición inicial y el pinzamiento',
                        unit: 'Unidades de distancia',
                        color: pinchIndexData[0].color,
                        minY: 0,
                        maxY: excursionMax,
                        data: [pinchIndexData[0]],
                        dates: _exerciseDates('pinch_index'),
                      ),
                    ],

                    // ------------------------------------------
                    // SUAVIDAD DEL MOVIMIENTO
                    // ------------------------------------------

                    if (pinchIndexData[1].values.any((v) => v != null)) ...[
                      const SizedBox(height: 24),

                      _buildChartCard(
                        title: 'Evolución de la suavidad del movimiento',
                        subtitle:
                            'Variación del Normalized Jerk durante el movimiento de pinza. Menor valor indica mayor suavidad.',
                        unit: 'Normalized Jerk',
                        color: pinchIndexData[1].color,
                        minY: 0,
                        maxY: jerkMax,
                        data: [pinchIndexData[1]],
                        dates: _exerciseDates('pinch_index'),
                      ),
                    ],

                    // ------------------------------------------
                    // MOVIMIENTO COMPENSATORIO
                    // ------------------------------------------

                    if (pinchIndexData[2].values.any((v) => v != null)) ...[
                      const SizedBox(height: 24),

                      _buildChartCard(
                        title: 'Evolución del movimiento compensatorio',
                        subtitle:
                            'Movimiento promedio de los dedos medio, anular y meñique durante la pinza.',
                        unit: 'Grados (°)',
                        color: pinchIndexData[2].color,
                        minY: 0,
                        maxY: compensatoryMax,
                        data: [pinchIndexData[2]],
                        dates: _exerciseDates('pinch_index'),
                      ),
                    ],
                  ],

                  // ==========================================
                  // FINGER ABDUCTION
                  // ==========================================

                  if (hasAbductionData) ...[
                    // Apertura global

                    if (abductionGlobalValues.isNotEmpty) ...[
                      const SizedBox(height: 24),

                      _buildChartCard(
                        title: 'Evolución de la apertura global',
                        subtitle:
                            'Excursión de apertura de los dedos respecto a la posición inicial.',
                        unit: 'Proporción normalizada',
                        color: abductionData[0].color,
                        minY: 0,
                        maxY: abductionGlobalMax,
                        data: [abductionData[0]],
                        dates: _exerciseDates('finger_abduction'),
                      ),
                    ],

                    // Separación entre pares de dedos

                    if (abductionPairValues.isNotEmpty) ...[
                      const SizedBox(height: 24),

                      _buildChartCard(
                        title: 'Evolución de la separación entre dedos',
                        subtitle:
                            'Excursión de separación de los cuatro pares de dedos.',
                        unit: 'Proporción normalizada',
                        color: abductionData[1].color,
                        minY: 0,
                        maxY: abductionPairMax,
                        data: abductionData.sublist(1),
                        dates: _exerciseDates('finger_abduction'),
                      ),
                    ],
                  ],

                  // ==========================================
                  // WRIST MOVEMENT
                  // ==========================================

                  if (hasWristData) ...[
                    const SizedBox(height: 24),

                    _buildChartCard(
                      title: 'Evolución de la movilidad de muñeca',
                      subtitle:
                          'Rango de movimiento proyectado, flexión y extensión.',
                      unit: 'Grados (°)',
                      color: wristData[0].color,
                      minY: 0,
                      maxY: wristMax,
                      data: wristData,
                      dates: _exerciseDates('wrist_movement'),
                    ),
                  ],

                  // ==========================================
                  // ACTIVIDAD MUSCULAR (EMG)
                  // ==========================================

                  if (_emg != null ||
                      _errorEmg != null ||
                      _calibraciones.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    ..._buildEmgSection(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // PREPARAR DATOS DE EVOLUCIÓN DE FULL FIST
  // --------------------------------------------------

  List<_ChartSeries> _getFullFistChartData() {
    // Orden cronológico: sesiones antiguas a recientes
    final sessions = realSessions
        .where((session) => session['exercise'] == 'full_fist')
        .toList();

    const fingerNames = {
      'thumb': 'Pulgar',
      'index': 'Índice',
      'middle': 'Medio',
      'ring': 'Anular',
      'pinky': 'Meñique',
    };

    const fingerColors = [
      Color(0xFFE57373),
      Color(0xFF64B5F6),
      Color(0xFF81C784),
      Color(0xFFFFB74D),
      Color(0xFFBA68C8),
    ];

    // Almacenará una lista de valores por cada dedo
    final Map<String, List<double?>> fingerValues = {
      for (final finger in fingerNames.keys) finger: [],
    };

    for (final session in sessions) {
      try {
        final decoded = jsonDecode(
          session['result_json'] as String,
        );

        if (decoded is! Map) throw const FormatException('Sin datos');

        final result = Map<String, dynamic>.from(decoded);
        final summaryRaw = result['summary'];

        if (summaryRaw is! Map) throw const FormatException('Sin datos');

        final summary = Map<String, dynamic>.from(summaryRaw);
        final excursionsRaw = summary['mean_finger_excursions'];

        if (excursionsRaw is! Map) throw const FormatException('Sin datos');

        final excursions = Map<String, dynamic>.from(excursionsRaw);

        // Verificar que existan los cinco valores
        final hasAllValues = fingerNames.keys.every(
          (finger) => excursions[finger] is num,
        );

        if (!hasAllValues) throw const FormatException('Sin datos');

        for (final finger in fingerNames.keys) {
          fingerValues[finger]!.add(
            (excursions[finger] as num).toDouble(),
          );
        }
      } catch (e) {
        debugPrint('Error procesando sesión full_fist: $e');

        for (final finger in fingerNames.keys) {
          fingerValues[finger]!.add(null);
        }
      }
    }

    return List.generate(fingerNames.length, (index) {
      final finger = fingerNames.keys.elementAt(index);

      return _ChartSeries(
        name: fingerNames[finger]!,
        color: fingerColors[index],
        values: fingerValues[finger]!,
      );
    });
  }

  // --------------------------------------------------
  // PREPARAR DATOS DE PINCH INDEX
  // --------------------------------------------------
  List<_ChartSeries> _getPinchIndexChartData() {
    final sessions = realSessions
        .where((session) => session['exercise'] == 'pinch_index')
        .toList();

    final excursion = <double?>[];
    final smoothness = <double?>[];
    final compensatoryMovement = <double?>[];

    for (final session in sessions) {
      try {
        final rawResult = session['result_json'];

        if (rawResult == null) throw const FormatException('Sin datos');

        final decoded = jsonDecode(rawResult as String);
        final result = Map<String, dynamic>.from(decoded as Map);

        final rawSummary = result['summary'];

        if (rawSummary is! Map) throw const FormatException('Sin datos');

        final summary = Map<String, dynamic>.from(rawSummary);

        excursion.add(
          (summary['mean_excursion'] as num?)?.toDouble(),
        );

        smoothness.add(
          (summary['mean_normalized_jerk'] as num?)?.toDouble(),
        );

        compensatoryMovement.add(
          (summary['mean_compensatory_movement_deg'] as num?)
              ?.toDouble(),
        );
      } catch (e) {
        debugPrint('Error leyendo sesión pinch_index: $e');

        // Conservamos la posición de esta sesión en las gráficas.
        excursion.add(null);
        smoothness.add(null);
        compensatoryMovement.add(null);
      }
    }

    return [
      _ChartSeries(
        name: 'Excursión media',
        color: const Color(0xFF3978B8),
        values: excursion,
      ),
      _ChartSeries(
        name: 'Suavidad',
        color: const Color(0xFF27A69A),
        values: smoothness,
      ),
      _ChartSeries(
        name: 'Movimiento compensatorio',
        color: const Color(0xFFE39A43),
        values: compensatoryMovement,
      ),
    ];
  }

  // --------------------------------------------------
  // PREPARAR DATOS PARA ABDUCCION DE DEDOS
  // --------------------------------------------------
  List<_ChartSeries> _getFingerAbductionChartData() {
    final sessions = realSessions
        .where((session) => session['exercise'] == 'finger_abduction')
        .toList();

    final globalOpening = <double?>[];

    final thumbIndex = <double?>[];
    final indexMiddle = <double?>[];
    final middleRing = <double?>[];
    final ringPinky = <double?>[];

    for (final session in sessions) {
      try {
        final rawResult = session['result_json'];

        if (rawResult == null) throw const FormatException('Sin datos');

        final decoded = jsonDecode(rawResult as String);
        final result = Map<String, dynamic>.from(decoded as Map);

        final rawSummary = result['summary'];

        if (rawSummary is! Map) throw const FormatException('Sin datos');

        final summary = Map<String, dynamic>.from(rawSummary);

        final rawPairs = summary['mean_pair_excursions'];

        final pairs = rawPairs is Map
            ? Map<String, dynamic>.from(rawPairs)
            : <String, dynamic>{};

        globalOpening.add(
          (summary['mean_global_opening_excursion'] as num?)
              ?.toDouble(),
        );

        thumbIndex.add(
          (pairs['thumb_index'] as num?)?.toDouble(),
        );

        indexMiddle.add(
          (pairs['index_middle'] as num?)?.toDouble(),
        );

        middleRing.add(
          (pairs['middle_ring'] as num?)?.toDouble(),
        );

        ringPinky.add(
          (pairs['ring_pinky'] as num?)?.toDouble(),
        );
      } catch (e) {
        debugPrint('Error leyendo sesión finger_abduction: $e');

        globalOpening.add(null);
        thumbIndex.add(null);
        indexMiddle.add(null);
        middleRing.add(null);
        ringPinky.add(null);
      }
    }

    return [
      _ChartSeries(
        name: 'Apertura global',
        color: const Color(0xFF3978B8),
        values: globalOpening,
      ),
      _ChartSeries(
        name: 'Pulgar - índice',
        color: const Color(0xFF27A69A),
        values: thumbIndex,
      ),
      _ChartSeries(
        name: 'Índice - medio',
        color: const Color(0xFFE39A43),
        values: indexMiddle,
      ),
      _ChartSeries(
        name: 'Medio - anular',
        color: const Color(0xFF8E6BBE),
        values: middleRing,
      ),
      _ChartSeries(
        name: 'Anular - meñique',
        color: const Color(0xFFD66B83),
        values: ringPinky,
      ),
    ];
  }

  // --------------------------------------------------
  // PREPARAR DATOS PARA MOVIMIENTO DE MUÑECA
  // --------------------------------------------------
  List<_ChartSeries> _getWristMovementChartData() {
    final sessions = realSessions
        .where((session) => session['exercise'] == 'wrist_movement')
        .toList();

    final projectedRom = <double?>[];
    final flexionExcursion = <double?>[];
    final extensionExcursion = <double?>[];

    for (final session in sessions) {
      try {
        final rawResult = session['result_json'];

        if (rawResult == null) throw const FormatException('Sin datos');

        final decoded = jsonDecode(rawResult as String);
        final result = Map<String, dynamic>.from(decoded as Map);

        final rawSummary = result['summary'];

        if (rawSummary is! Map) throw const FormatException('Sin datos');

        final summary = Map<String, dynamic>.from(rawSummary);

        projectedRom.add(
          (summary['mean_projected_rom_deg'] as num?)
              ?.toDouble(),
        );

        flexionExcursion.add(
          (summary['mean_flexion_excursion_deg'] as num?)
              ?.toDouble(),
        );

        extensionExcursion.add(
          (summary['mean_extension_excursion_deg'] as num?)
              ?.toDouble(),
        );
      } catch (e) {
        debugPrint('Error leyendo sesión wrist_movement: $e');

        projectedRom.add(null);
        flexionExcursion.add(null);
        extensionExcursion.add(null);
      }
    }

    return [
      _ChartSeries(
        name: 'Rango de movimiento',
        color: const Color(0xFF3978B8),
        values: projectedRom,
      ),
      _ChartSeries(
        name: 'Flexión',
        color: const Color(0xFF27A69A),
        values: flexionExcursion,
      ),
      _ChartSeries(
        name: 'Extensión',
        color: const Color(0xFFE39A43),
        values: extensionExcursion,
      ),
    ];
  }
  // --------------------------------------------------
  // HISTORIAL DE LAS ÚLTIMAS SESIONES REALES
  // --------------------------------------------------

  Widget _buildRealSessionsSection() {
    final groups = _sessionGroups();

    // Ordenar de más reciente a más antigua
    final recentGroups = groups.reversed.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ENCABEZADO DESPLEGABLE
          InkWell(
            onTap: () {
              setState(() {
                _recentSessionsExpanded =
                    !_recentSessionsExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Últimas sesiones',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF243447),
                      ),
                    ),
                  ),

                  Text(
                    '${groups.length} registradas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Icon(
                    _recentSessionsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF243F60),
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          // CONTENIDO DESPLEGABLE
          if (_recentSessionsExpanded) ...[
            const SizedBox(height: 12),

            const Text(
              'Ejercicios realizados en las tres sesiones más recientes.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 20),

            ...recentGroups.map(
              (group) => _buildSessionGroupCard(
                group,
                groups.indexOf(group) + 1,
              ),
            ),

            // BOTÓN VER MÁS
            const SizedBox(height: 4),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                child: const Text('Ver más'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------
  // AGRUPAR EJERCICIOS POR SESIÓN DE TERAPIA
  // --------------------------------------------------

  List<_SessionGroup> _sessionGroups() {
    final groups = <_SessionGroup>[];

    for (final therapy in therapySessions) {
      final exercises = realSessions
          .where((s) => s['therapy_session_id'] == therapy['id'])
          .toList();

      if (exercises.isEmpty) continue;

      groups.add(
        _SessionGroup(
          date: DateTime.parse(therapy['session_date'] as String),
          cameraSource: therapy['camera_source'] as String?,
          exercises: exercises,
          therapyId: therapy['id'] as int?,
        ),
      );
    }

    // Registros antiguos sin sesión asociada
    for (final session in realSessions) {
      if (session['therapy_session_id'] != null) continue;

      groups.add(
        _SessionGroup(
          date: DateTime.parse(session['session_date'] as String),
          exercises: [session],
        ),
      );
    }

    groups.sort((a, b) => a.date.compareTo(b.date));

    return groups;
  }

  List<DateTime> _exerciseDates(String exercise) {
    return realSessions
        .where((session) => session['exercise'] == exercise)
        .map((session) => DateTime.parse(session['session_date'] as String))
        .toList();
  }

  String _formatDate(
    DateTime date, {
    bool short = false,
    bool withTime = false,
  }) {
    String two(int value) => value.toString().padLeft(2, '0');

    final day = '${two(date.day)}/${two(date.month)}';

    if (short) return day;

    final full = '$day/${date.year}';

    return withTime ? '$full ${two(date.hour)}:${two(date.minute)}' : full;
  }

  String _exerciseName(String exercise) {
    return switch (exercise) {
      'full_fist' => 'Cierre completo de puño',
      'pinch_index' => 'Pinza con índice',
      'pinch_middle' => 'Pinza con dedo medio',
      'pinch_pinky' => 'Pinza con meñique',
      'finger_abduction' => 'Separación de dedos',
      'wrist_movement' => 'Movimiento de muñeca',
      'index_extension' => 'Extensión del índice',
      _ => exercise,
    };
  }

  // --------------------------------------------------
  // TARJETA DE UNA SESIÓN
  // --------------------------------------------------

  Widget _buildSessionGroupCard(_SessionGroup group, int number) {
    final source = switch (group.cameraSource) {
      'esp' => ' · Cámaras ESP',
      'webcam' => ' · Webcam',
      _ => '',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD5DFEA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_note,
                color: Color(0xFF243F60),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sesión $number',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF243447),
                  ),
                ),
              ),
              Text(
                _formatDate(group.date, withTime: true),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF555555),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            '${group.exercises.length} '
            '${group.exercises.length == 1 ? 'ejercicio' : 'ejercicios'}'
            '$source',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.exercises.map((session) {
              return Chip(
                label: Text(
                  _exerciseName(session['exercise']?.toString() ?? ''),
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          ...group.exercises.map(_buildExerciseCard),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // RESULTADO DE UN EJERCICIO
  // --------------------------------------------------

  Widget _buildExerciseCard(Map<String, dynamic> session) {
    final String exercise =
        session['exercise']?.toString() ?? 'Ejercicio';

    final int totalRepetitions =
        (session['total_repetitions'] as num?)?.toInt() ?? 0;

    final int validRepetitions =
        (session['valid_repetitions'] as num?)?.toInt() ?? 0;

    // Interpretar el JSON almacenado
    Map<String, dynamic> result = {};

    try {
      final decoded = jsonDecode(
        session['result_json'] as String,
      );

      if (decoded is Map) {
        result = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('Error interpretando resultado: $e');
    }

    final summaryRaw = result['summary'];

    final Map<String, dynamic> summary =
        summaryRaw is Map
            ? Map<String, dynamic>.from(summaryRaw)
            : {};

    final String exerciseName = _exerciseName(exercise);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fitness_center,
                color: Color(0xFF3978B8),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  exerciseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF243447),
                  ),
                ),
              ),

              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 20,
              ),
            ],
          ),

          const Divider(height: 24),

          Row(
            children: [
              Expanded(
                child: _buildSessionMetric(
                  'Repeticiones',
                  '$validRepetitions/$totalRepetitions',
                ),
              ),

              Expanded(
                child: _buildSessionMetric(
                  'Válidas',
                  '${totalRepetitions > 0 ? (validRepetitions / totalRepetitions * 100).toStringAsFixed(0) : 0}%',
                ),
              ),
            ],
          ),

          // MÉTRICAS DE FULL FIST
          if (exercise == 'full_fist') ...[
            const SizedBox(height: 16),

            const Text(
              'Movilidad de los dedos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF243447),
              ),
            ),

            const SizedBox(height: 10),

            _buildSessionMetric(
              'Excursión media de flexión',
              '${(summary['mean_flexion_excursion_deg'] as num?)?.toStringAsFixed(2) ?? '--'}°',
            ),

            const SizedBox(height: 10),

            _buildSessionMetric(
              'Calidad media de seguimiento',
              '${(summary['mean_tracking_quality_pct'] as num?)?.toStringAsFixed(1) ?? '--'}%',
            ),

            const SizedBox(height: 10),

            _buildSessionMetric(
              'Consistencia entre repeticiones',
              '${(summary['consistency_cv_pct'] as num?)?.toStringAsFixed(2) ?? '--'}%',
            ),

            const SizedBox(height: 14),

            const Text(
              'Excursión por dedo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF243447),
              ),
            ),

            const SizedBox(height: 8),

            ..._buildFingerExcursions(
              summary['mean_finger_excursions'],
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------
  // MÉTRICA INDIVIDUAL
  // --------------------------------------------------

  Widget _buildSessionMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF243F60),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------
  // EXCURSIÓN DE CADA DEDO
  // --------------------------------------------------

  List<Widget> _buildFingerExcursions(dynamic rawValues) {
    if (rawValues is! Map) {
      return [
        const Text(
          'No hay datos disponibles.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }

    const fingerNames = {
      'thumb': 'Pulgar',
      'index': 'Índice',
      'middle': 'Medio',
      'ring': 'Anular',
      'pinky': 'Meñique',
    };

    final values = Map<String, dynamic>.from(rawValues);

    return fingerNames.entries.map((entry) {
      final value = values[entry.key];

      final double? degrees =
          value is num ? value.toDouble() : null;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              entry.value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF555555),
              ),
            ),

            Text(
              degrees != null
                  ? '${degrees.toStringAsFixed(2)}°'
                  : '--',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF243F60),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
  // --------------------------------------------------
  // ENCABEZADO
  // --------------------------------------------------

  Widget _buildHeader(int sessionCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF243F60),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person,
              color: Color(0xFF243F60),
              size: 32,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Progreso de rehabilitación',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  patientName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Column(
            children: [
              Text(
                '$sessionCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Text(
                'Sesiones',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          IconButton(
            tooltip: 'Actualizar progreso',
            onPressed: _isLoading ? null : _loadProgress,
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
              size: 25,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // TARJETA DE GRÁFICA
  // --------------------------------------------------

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required String unit,
    required Color color,
    required double minY,
    required double maxY,
    required List<_ChartSeries> data,
    required List<DateTime> dates,
    List<double>? franja,
    Widget? badge,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF243447),
                  ),
                ),
              ),
              if (badge != null) badge,
            ],
          ),

          const SizedBox(height: 5),

          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 220,
            child: LineChart(
              _buildChartData(
                data: data,
                minY: minY,
                maxY: maxY,
                unit: unit,
                dates: dates,
                franja: franja,
              ),
            ),
          ),

          if (data.length > 1) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              children: data.map((series) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: series.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      series.name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------
  // CONFIGURACIÓN DE LAS GRÁFICAS
  // --------------------------------------------------

  LineChartData _buildChartData({
    required List<_ChartSeries> data,
    required double minY,
    required double maxY,
    required String unit,
    required List<DateTime> dates,
    List<double>? franja,
  }) {
    final sessionCount = data.isNotEmpty
    ? data.first.values.length
    : 0;

    final labelInterval = (sessionCount / 8).ceil().clamp(1, 1000);

    final axisInterval = (maxY - minY) / 4;

    return LineChartData(
      minY: minY,
      maxY: maxY,

      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          if (franja != null && franja.length == 2)
            HorizontalRangeAnnotation(
              y1: franja[0].clamp(minY, maxY),
              y2: franja[1].clamp(minY, maxY),
              color: Colors.green.withValues(alpha: 0.08),
            ),
        ],
      ),

      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: axisInterval > 0 ? axisInterval : 1, //ojito interval
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey.withValues(alpha:0.15),
            strokeWidth: 1,
          );
        },
      ),

      borderData: FlBorderData(show: false),

      titlesData: FlTitlesData(
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),

        leftTitles: AxisTitles(
          axisNameWidget: Text(
            unit,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: axisInterval > 0 ? axisInterval : 1,
            getTitlesWidget: (value, meta) {
              return Text(
                maxY - minY < 10
                    ? value.toStringAsFixed(maxY - minY < 1 ? 2 : 1)
                    : value.toInt().toString(),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ),

        bottomTitles: AxisTitles(
          axisNameWidget: const Text(
            'Fecha',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();

              if (index < 0 ||
                  index >= sessionCount ||
                  index >= dates.length ||
                  index % labelInterval != 0) {
                return const SizedBox.shrink();
              }

              return Text(
                _formatDate(dates[index], short: true),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ),
      ),

      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final index = spot.x.toInt();
              final dateText = spot == spots.first &&
                      index >= 0 &&
                      index < dates.length
                  ? '${_formatDate(dates[index], withTime: true)}\n'
                  : '';

              return LineTooltipItem(
                '$dateText${spot.y.toStringAsFixed(1)} $unit',
                TextStyle(
                  color: data[spot.barIndex].color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            }).toList();
          },
        ),
      ),

      lineBarsData: data.map((series) {
        final spots = <FlSpot>[];

        for (int i = 0; i < series.values.length; i++) {
          final value = series.values[i];

          if (value != null && value.isFinite) {
            spots.add(
              FlSpot(
                i.toDouble(),
                value,
              ),
            );
          }
        }

        return LineChartBarData(
          spots: spots,
          isCurved: true,
          color: series.color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: series.color.withValues(alpha:0.07),
          ),
        );
      }).toList(),
    );
  }

  // --------------------------------------------------
  // ACTIVIDAD MUSCULAR (EMG)
  // --------------------------------------------------

  Future<void> _cargarEmg() async {
    final grupos = _sessionGroups();

    final sesiones = grupos.map((grupo) {
      return grupo.exercises
          .map((row) {
            try {
              final decoded = jsonDecode(row['result_json'] as String);
              final emg = decoded is Map ? decoded['emg'] : null;
              return emg is Map && emg['disponible'] == true
                  ? Map<String, dynamic>.from(emg)
                  : null;
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    }).toList();

    if (!sesiones.any((s) => s.isNotEmpty)) {
      if (mounted) {
        setState(() {
          _emg = null;
          _errorEmg = null;
        });
      }
      return;
    }

    final r = await DeviceService().progresoEmg(sesiones);

    if (!mounted) return;

    setState(() {
      _emg = r['success'] == true ? r : null;
      _errorEmg = r['success'] == true
          ? null
          : 'No se pudo calcular la evolución del EMG. ¿Está abierto el servidor Python?';
    });
  }

  Color _colorEstado(String estado) {
    return switch (estado) {
      'mejora' => Colors.green.shade700,
      'posible mejora' => Colors.green.shade400,
      'retroceso' => Colors.red.shade700,
      'posible retroceso' => Colors.orange.shade700,
      'subió' || 'bajó' => const Color(0xFF3978B8),
      _ => Colors.grey.shade600,
    };
  }

  Widget _chipEstado(String estado, String? cambio) {
    final color = _colorEstado(estado);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        cambio == null ? estado : '$estado · $cambio',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Widget> _buildEmgSection() {
    final grupos = _sessionGroups();
    final fechas = grupos.map((g) => g.date).toList();
    final widgets = <Widget>[
      const Text(
        'Actividad muscular (EMG)',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF243447),
        ),
      ),
    ];

    final emg = _emg;

    if (emg != null) {
      final nivel = switch (emg['nivel']) {
        'bajo' => 'bajo: activar más el músculo cuenta como mejora',
        'medio_alto' => 'medio-alto: la activación solo se informa; lo que decide es la eficiencia',
        _ => 'sin datos suficientes',
      };

      widgets.addAll([
        const SizedBox(height: 4),
        Text(
          'Nivel del paciente $nivel (${emg['nivel_por_que']}). '
          'Línea base: sus 3 primeras sesiones con EMG. La franja verde es la variación normal.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ]);
    }

    if (_errorEmg != null) {
      widgets.addAll([
        const SizedBox(height: 8),
        Text(_errorEmg!, style: const TextStyle(color: Colors.red)),
      ]);
    }

    // Esfuerzo máximo de cada calibración, por músculo
    if (_calibraciones.isNotEmpty) {
      const colores = {
        'flexores': Color(0xFF3978B8),
        'extensores': Color(0xFF27A69A),
        'muneca': Color(0xFFE39A43),
      };
      final canales = _calibraciones.map((c) => c['channel'] as String).toSet().toList();
      final porSesion = <int, Map<String, double>>{};

      for (final c in _calibraciones) {
        final id = c['therapy_session_id'] as int?;
        final mvc = (c['mvc_mv'] as num?)?.toDouble();
        if (id != null && mvc != null) {
          porSesion.putIfAbsent(id, () => {})[c['channel'] as String] = mvc;
        }
      }

      final series = canales.map((canal) {
        return _ChartSeries(
          name: canal == 'muneca' ? 'pinza' : canal,
          color: colores[canal] ?? const Color(0xFF8E6BBE),
          values: grupos.map((g) => porSesion[g.therapyId]?[canal]).toList(),
        );
      }).toList();

      final valores = series.expand((s) => s.values).whereType<double>().toList();

      if (valores.isNotEmpty) {
        final maximo = valores.reduce((a, b) => a > b ? a : b);
        widgets.addAll([
          const SizedBox(height: 16),
          _buildChartCard(
            title: 'Esfuerzo máximo por músculo',
            subtitle: 'MVC medido en la calibración de cada sesión.',
            unit: 'mV',
            color: series.first.color,
            minY: 0,
            maxY: maximo * 1.2,
            data: series,
            dates: fechas,
          ),
        ]);
      }
    }

    final indicadores = emg?['indicadores'];

    if (indicadores is Map) {
      const colores = [
        Color(0xFF3978B8),
        Color(0xFF27A69A),
        Color(0xFFE39A43),
        Color(0xFF8E6BBE),
        Color(0xFFD66B83),
      ];
      var i = 0;

      for (final entry in indicadores.entries) {
        final ind = Map<String, dynamic>.from(entry.value as Map);
        final serie = (ind['serie'] as List)
            .map((v) => v is num ? v.toDouble() : null)
            .toList();
        final valores = serie.whereType<double>().toList();

        if (valores.isEmpty) continue;

        final franja = ind['franja'] is List
            ? (ind['franja'] as List).map((v) => (v as num).toDouble()).toList()
            : null;
        final maximo = [...valores, ...?franja].reduce((a, b) => a > b ? a : b);
        final color = colores[i++ % colores.length];

        widgets.addAll([
          const SizedBox(height: 16),
          _buildChartCard(
            title: ind['nombre'].toString(),
            subtitle: ind['margen_origen'] != null
                ? 'Margen según ${ind['margen_origen']}.'
                : 'Comparado con su línea base.',
            unit: ind['unidad'].toString(),
            color: color,
            minY: 0,
            maxY: maximo > 0 ? maximo * 1.2 : 1,
            data: [
              _ChartSeries(
                name: ind['nombre'].toString(),
                color: color,
                values: serie,
              ),
            ],
            dates: fechas,
            franja: franja,
            badge: _chipEstado(
              ind['estado'].toString(),
              ind['cambio']?.toString(),
            ),
          ),
        ]);
      }
    }

    return widgets;
  }
}

// --------------------------------------------------
// ESTRUCTURA INTERNA PARA LAS SERIES DE DATOS
// --------------------------------------------------

class _ChartSeries {
  final String name;
  final Color color;
  final List<double?> values;

  const _ChartSeries({
    required this.name,
    required this.color,
    required this.values,
  });
}

class _SessionGroup {
  final DateTime date;
  final String? cameraSource;
  final List<Map<String, dynamic>> exercises;
  final int? therapyId;

  const _SessionGroup({
    required this.date,
    this.cameraSource,
    required this.exercises,
    this.therapyId,
  });
}
