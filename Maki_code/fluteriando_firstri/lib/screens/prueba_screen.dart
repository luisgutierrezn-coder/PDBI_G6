
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/patient.dart';
import '../services/database_service.dart';
import 'package:flutter/material.dart';

class PruebaScreen extends StatefulWidget {

  final Patient? pacienteInicial;

  const PruebaScreen({
    super.key,
    this.pacienteInicial,
  });

  @override
  State<PruebaScreen> createState() => _PruebaScreenState();
}

class _PruebaScreenState extends State<PruebaScreen> {
  final String servidor = 'http://127.0.0.1:8000';

  final TextEditingController repController =
      TextEditingController(text: '5');

  Timer? pollingTimer;
  String ejercicioSeleccionado = 'pinch_index';

  bool pruebaActiva = false;
  bool cargando = false;
  bool consultandoEstado = false;

  String mensaje = 'Configura las repeticiones e inicia la prueba.';
  String fase = 'IDLE';

  int repeticionActual = 0;
  int totalRepeticiones = 5;

  Map<String, dynamic>? resultado;

  // Pacientes registrados
  List<Patient> pacientes = [];
  Patient? pacienteSeleccionado;
  bool cargandoPacientes = true;

  // Paciente asociado a la prueba que está en ejecución
  int? pacienteSesionId;

  // Control del guardado del resultado
  bool guardandoResultado = false;
  bool resultadoGuardado = false;

  String get nombreEjercicio {
    switch (ejercicioSeleccionado) {
      case 'wrist_movement':
        return 'Movimiento de muñeca';
      case 'finger_abduction':
        return 'Abducción de dedos';
      case 'full_fist':
        return 'Puño completo';
      case 'pinch_index':
      default:
        return 'Pinza índice';
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarPacientes();
  }

  @override
  void didUpdateWidget(covariant PruebaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nuevoId = widget.pacienteInicial?.id;
    final anteriorId = oldWidget.pacienteInicial?.id;

    if (nuevoId != anteriorId && nuevoId != null) {
      Patient? pacienteEncontrado;

      for (final paciente in pacientes) {
        if (paciente.id == nuevoId) {
          pacienteEncontrado = paciente;
          break;
        }
      }

      if (pacienteEncontrado != null) {
        setState(() {
          pacienteSeleccionado = pacienteEncontrado;
        });
      }
    }
  }

  Future<void> _cargarPacientes() async {
    try {
      final pacientesMap = await DatabaseService.instance.getPatients();

      if (!mounted) return;

      setState(() {
        pacientes = pacientesMap
            .map((map) => Patient.fromMap(map))
            .toList();

        // Si HomeScreen envió un paciente, seleccionarlo.
        if (widget.pacienteInicial != null) {
          pacienteSeleccionado = pacientes.firstWhere(
            (p) => p.id == widget.pacienteInicial!.id,
            orElse: () => widget.pacienteInicial!,
          );
        }

        cargandoPacientes = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cargandoPacientes = false;
      });

      debugPrint('Error cargando pacientes: $e');
    }
  }

  // ==================================================
  // COMUNICACIÓN CON FASTAPI
  // ==================================================

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse('$servidor$path');

      final HttpClientRequest req;

      if (method == 'POST') {
        req = await client.postUrl(uri);
      } else {
        req = await client.getUrl(uri);
      }

      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }

      final response = await req.close().timeout(
        const Duration(seconds: 10),
      );

      final responseText = await response
          .transform(utf8.decoder)
          .join();

      final decoded = jsonDecode(responseText);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw Exception('Respuesta no válida del servidor.');
    } finally {
      client.close(force: true);
    }
  }

  // ==================================================
  // INICIAR PRUEBA
  // ==================================================

  Future<void> iniciarPrueba() async {
    final reps = int.tryParse(repController.text);
    if (pacienteSeleccionado == null ||
        pacienteSeleccionado!.id == null) {
      setState(() {
        mensaje = 'Selecciona un paciente antes de iniciar la prueba.';
      });
      return;
    }
    if (reps == null || reps < 1 || reps > 20) {
      setState(() {
        mensaje = 'Ingresa entre 1 y 20 repeticiones.';
      });
      return;
    }

    setState(() {
      cargando = true;
      mensaje = 'Conectando con Python...';
      resultado = null;
      fase = 'POSITIONING';
      repeticionActual = 0;
      totalRepeticiones = reps;
    });
    pacienteSesionId = pacienteSeleccionado!.id;
    resultadoGuardado = false;
    guardandoResultado = false;
    try {
      final response = await request(
        '/webcam/start',
        method: 'POST',
        body: {
          'repetitions': reps,
          'exercise': ejercicioSeleccionado,
        },
      );
      print('Respuesta: $response');

      if (!mounted) return;

      if (response['status'] == 'running') {
        setState(() {
          pruebaActiva = true;
          mensaje = ejercicioSeleccionado == 'wrist_movement'
            ? 'Coloca la mano frente a la cámara y mantén el antebrazo apoyado.'
            : ejercicioSeleccionado == 'finger_abduction'
                ? 'Coloca la mano frente a la cámara con los cinco dedos juntos.'
                : ejercicioSeleccionado == 'full_fist'
                    ? 'Coloca la mano frente a la cámara con los cinco dedos extendidos.'
                    : 'Coloca la mano frente a la cámara.';
        });

        pollingTimer?.cancel();

        pollingTimer = Timer.periodic(
          const Duration(milliseconds: 300),
          (_) => consultarEstado(),
        );
      } else {
        setState(() {
          mensaje = response['message'] ??
              'No se pudo iniciar la prueba.';
          
        });
        
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        mensaje = 'Error al conectar con Python: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
        });
      }
    }
  }

  // ==================================================
  // CONSULTAR ESTADO
  // ==================================================

  Future<void> consultarEstado() async {
    // Evita consultas simultáneas.
    if (consultandoEstado) return;

    consultandoEstado = true;

    try {
      final data = await request('/webcam/status');

      if (!mounted) return;

      final status = data['status'];

      setState(() {
        fase = data['phase'] ?? 'IDLE';

        repeticionActual = data['current_rep'] ?? 0;

        totalRepeticiones = data['total_reps'] ?? 0;

        if (fase == 'POSITIONING') {
          if (repeticionActual == 0) {
            if (ejercicioSeleccionado == 'wrist_movement') {
              mensaje = 'Posicionamiento inicial: coloca la muñeca en posición neutra.';
            } else if (ejercicioSeleccionado == 'finger_abduction') {
              mensaje = 'Posicionamiento inicial: mantén los cinco dedos juntos.';
            } else {
              mensaje = 'Posicionamiento inicial: coloca la mano abierta con los dedos extendidos.';
            }
          } else {
            if (ejercicioSeleccionado == 'wrist_movement') {
              mensaje = 'Reposicionamiento: vuelve a la posición neutra.';
            } else if (ejercicioSeleccionado == 'finger_abduction') {
              mensaje = 'Reposicionamiento: vuelve a juntar los cinco dedos.';
            } else {
              mensaje = 'Reposicionamiento: vuelve a abrir la mano.';
            }
          }
        } else if (fase == 'EXECUTING') {
          if (ejercicioSeleccionado == 'wrist_movement') {
            mensaje = 'Realizando flexión y extensión de muñeca...';
          } else if (ejercicioSeleccionado == 'finger_abduction') {
            mensaje = 'Separa los cinco dedos y vuelve a juntarlos...';
          } else if (ejercicioSeleccionado == 'full_fist') {
            mensaje = 'Cierra la mano formando un puño completo y mantén la posición...';
          } else {
            mensaje = 'Realizando pinza índice...';
          }
        } else if (fase == 'WAITING_NEXT') {
          mensaje = 'Preparando siguiente repetición...';
        }

        if (status == 'COMPLETED') {
          pruebaActiva = false;
          resultado = data['result'];

          mensaje = 'Prueba completada correctamente.';
        }

        

        if (status == 'ERROR') {
          pruebaActiva = false;

          mensaje = data['error'] ??
              'Error durante la prueba.';
        }

        if (status == 'CANCELLED') {
          pruebaActiva = false;
          mensaje = 'Prueba cancelada.';
        }
      });

      // Guardar automáticamente al completar.
      if (status == 'COMPLETED') {
        await _guardarResultado(data['result']);
        final sesiones = await DatabaseService.instance
            .getRealSessions(pacienteSesionId!);

        debugPrint('Sesiones reales: ${sesiones.length}');
        debugPrint('Última sesión: ${sesiones.last}');
      }

      if (status == 'COMPLETED' ||
          status == 'ERROR' ||
          status == 'CANCELLED') {
        pollingTimer?.cancel();
      }
    } catch (e) {
      debugPrint('Error consultando estado: $e');
    } finally {
      consultandoEstado = false;
    }
  }
  // ==================================================
  // GUARDAR RESULTADOS
  // ==================================================

  Future<void> _guardarResultado(dynamic resultadoRaw) async {
    if (resultadoGuardado || guardandoResultado) return;

    final patientId = pacienteSesionId;

    if (patientId == null) {
      setState(() {
        mensaje = 'No se pudo guardar: no hay un paciente asociado.';
      });
      return;
    }

    if (resultadoRaw is! Map) {
      setState(() {
        mensaje = 'No se pudo guardar: el resultado recibido no es válido.';
      });
      return;
    }

    setState(() {
      guardandoResultado = true;
      mensaje = 'Prueba completada. Guardando resultados...';
    });

    try {
      final resultadoMap = Map<String, dynamic>.from(resultadoRaw);

      await DatabaseService.instance.insertExerciseSession(
        patientId: patientId,
        result: resultadoMap,
      );

      if (!mounted) return;

      setState(() {
        resultadoGuardado = true;
        mensaje = 'Prueba completada y resultados guardados correctamente.';
      });

      debugPrint('Sesión guardada para el paciente $patientId');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        mensaje = 'La prueba terminó, pero ocurrió un error al guardar: $e';
      });

      debugPrint('Error guardando sesión: $e');
    } finally {
      if (mounted) {
        setState(() {
          guardandoResultado = false;
        });
      }
    }
  }

  // ==================================================
  // DETENER PRUEBA
  // ==================================================

  Future<void> detenerPrueba() async {
    pollingTimer?.cancel();

    setState(() {
      cargando = true;
    });

    try {
      await request(
        '/webcam/stop',
        method: 'POST',
      );

      if (!mounted) return;

      setState(() {
        pruebaActiva = false;
        mensaje = 'Prueba cancelada.';
        fase = 'CANCELLED';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        mensaje = 'Error al detener: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
        });
      }
    }
  }

  // ==================================================
  // FORMATO DE VALORES
  // ==================================================

  String formatValue(dynamic value, {int decimals = 2}) {
    if (value == null) return '--';

    if (value is num) {
      return value.toStringAsFixed(decimals);
    }

    return value.toString();
  }

  // ==================================================
  // TARJETAS DE MÉTRICAS
  // ==================================================

  Widget metricCard(
    String title,
    dynamic value,
    String unit, {
    IconData? icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.blue, size: 22),
              const SizedBox(height: 6),
            ],

            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              value == null
                  ? '--'
                  : '${formatValue(value)} $unit',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // FILA DE DETALLE
  // ==================================================

  Widget detailRow(
    String title,
    dynamic value,
    String unit,
  ) {
    return ListTile(
      dense: true,
      title: Text(title),
      trailing: Text(
        value == null
            ? '--'
            : '${formatValue(value)} $unit',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }


// ==================================================
// RESULTADOS DE MOVIMIENTO DE MUÑECA
// ==================================================

  Widget resultadosMuneca(
    Map<String, dynamic> summary,
    List reps,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 25),

        const Text(
          'Resultados de movimiento de muñeca',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Repeticiones válidas: '
          '${summary['valid_repetitions'] ?? 0}/'
          '${resultado!['total_repetitions'] ?? 0}',
        ),

        const SizedBox(height: 15),

        const Text(
          'Resumen de la sesión',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.45,
          children: [
            metricCard(
              'Rango angular proyectado promedio',
              summary['mean_projected_rom_deg'],
              '°',
              icon: Icons.open_in_full,
            ),

            metricCard(
              'Consistencia',
              summary['consistency_cv_pct'],
              '% CV',
              icon: Icons.repeat,
            ),

            metricCard(
              'Excursión de flexión',
              summary['mean_flexion_excursion_deg'],
              '°',
              icon: Icons.keyboard_arrow_down,
            ),

            metricCard(
              'Excursión de extensión',
              summary['mean_extension_excursion_deg'],
              '°',
              icon: Icons.keyboard_arrow_up,
            ),

            metricCard(
              'Calidad del seguimiento',
              summary['mean_tracking_quality_pct'],
              '%',
              icon: Icons.camera_alt,
            ),
          ],
        ),

        const SizedBox(height: 15),

        const Text(
          'Detalle por repetición',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        ...reps.map((rawRep) {
          final rep = Map<String, dynamic>.from(rawRep);

          final valid = rep['valid'] == true;

          return Card(
            child: ExpansionTile(
              title: Text(
                'Repetición ${rep['number']}',
              ),

              subtitle: Text(
                valid
                    ? 'Datos válidos'
                    : 'Datos insuficientes',
              ),

              children: [
                detailRow(
                  'Calidad del seguimiento',
                  rep['tracking_quality_pct'],
                  '%',
                ),

                if (valid) ...[
                  detailRow(
                    'Ángulo de referencia',
                    rep['reference_angle_deg'],
                    '°',
                  ),

                  detailRow(
                    'Excursión de flexión',
                    rep['flexion_excursion_deg'],
                    '°',
                  ),

                  detailRow(
                    'Excursión de extensión',
                    rep['extension_excursion_deg'],
                    '°',
                  ),

                  detailRow(
                    'Rango angular proyectado',
                    rep['projected_rom_deg'],
                    '°',
                  ),

                  detailRow(
                    'Desviación angular absoluta promedio',
                    rep['mean_absolute_deviation_deg'],
                    '°',
                  ),

                  detailRow(
                    'Número de muestras',
                    rep['samples_count'],
                    '',
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      rep['message'] ??
                          'No se obtuvieron suficientes datos '
                          'para esta repetición.',
                    ),
                  ),
                ],
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        const Text(
          'Consideraciones sobre las métricas:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          '• El rango angular proyectado representa la variación '
          'de orientación de la mano observada por la cámara.\n\n'
          '• Las excursiones de flexión y extensión se calculan '
          'respecto a la posición de referencia de cada repetición',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }


// ==================================================
// RESULTADOS DE ABDUCCIÓN DE DEDOS
// ==================================================

  Widget resultadosAbduccion(
    Map<String, dynamic> summary,
    List reps,
  ) {
    final pairExcursions = Map<String, dynamic>.from(
      summary['mean_pair_excursions'] ?? {},
    );

    final pairNames = {
      'thumb_index': 'Pulgar - Índice',
      'index_middle': 'Índice - Medio',
      'middle_ring': 'Medio - Anular',
      'ring_pinky': 'Anular - Meñique',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 25),

        const Text(
          'Resultados de abducción de dedos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Repeticiones válidas: '
          '${summary['valid_repetitions'] ?? 0}/'
          '${resultado!['total_repetitions'] ?? 0}',
        ),

        const SizedBox(height: 15),

        const Text(
          'Resumen de la sesión',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.45,
          children: [
            metricCard(
              'Apertura global promedio',
              summary['mean_global_opening_excursion'],
              'normalizada',
              icon: Icons.open_in_full,
            ),

            metricCard(
              'Consistencia',
              summary['consistency_cv_pct'],
              '% CV',
              icon: Icons.repeat,
            ),

            metricCard(
              'Calidad del seguimiento',
              summary['mean_tracking_quality_pct'],
              '%',
              icon: Icons.camera_alt,
            ),
          ],
        ),

        const SizedBox(height: 15),

        const Text(
          'Separación promedio por par de dedos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        Card(
          child: Column(
            children: pairNames.entries.map((entry) {
              return detailRow(
                entry.value,
                pairExcursions[entry.key],
                'normalizada',
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          'Detalle por repetición',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        ...reps.map((rawRep) {
          final rep = Map<String, dynamic>.from(rawRep);

          final valid = rep['valid'] == true;

          final repPairExcursions = Map<String, dynamic>.from(
            rep['pair_excursions'] ?? {},
          );

          return Card(
            child: ExpansionTile(
              title: Text(
                'Repetición ${rep['number']}',
              ),

              subtitle: Text(
                valid
                    ? 'Datos válidos'
                    : 'Datos insuficientes',
              ),

              children: [
                detailRow(
                  'Calidad del seguimiento',
                  rep['tracking_quality_pct'],
                  '%',
                ),

                if (valid) ...[
                  detailRow(
                    'Apertura global máxima',
                    rep['global_opening_excursion'],
                    'normalizada',
                  ),

                  const Divider(),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Separación adicional por par de dedos',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  ...pairNames.entries.map((entry) {
                    return detailRow(
                      entry.value,
                      repPairExcursions[entry.key],
                      'normalizada',
                    );
                  }),

                  detailRow(
                    'Número de muestras',
                    rep['samples_count'],
                    '',
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      rep['reason'] ??
                          'No se obtuvieron suficientes datos '
                          'para esta repetición.',
                    ),
                  ),
                ],
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        const Text(
          'Consideraciones sobre las métricas:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          '• La apertura global representa el incremento promedio '
          'de separación entre las puntas de los dedos respecto '
          'a la posición inicial.\n\n'
          '• Las métricas por par muestran el incremento máximo '
          'de separación entre dedos adyacentes.\n\n'
          '• La consistencia se estima mediante el coeficiente '
          'de variación de la apertura global entre repeticiones.\n\n'
          '• La calidad del seguimiento representa el porcentaje '
          'de fotogramas con detección válida de la mano.\n\n'
          'Las distancias están normalizadas respecto al ancho '
          'de la palma. Son indicadores experimentales de separación '
          'de los dedos y no mediciones directas de ángulos '
          'anatómicos de abducción.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }


  // ==================================================
  // RESULTADOS DE PUÑO COMPLETO
  // ==================================================

  Widget resultadosPunoCompleto(
    Map<String, dynamic> summary,
    List reps,
  ) {
    final fingerExcursions = Map<String, dynamic>.from(
      summary['mean_finger_excursions'] ?? {},
    );

    final fingerNames = {
      'thumb': 'Pulgar',
      'index': 'Índice',
      'middle': 'Medio',
      'ring': 'Anular',
      'pinky': 'Meñique',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 25),

        const Text(
          'Resultados de puño completo',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Repeticiones válidas: '
          '${summary['valid_repetitions'] ?? 0}/'
          '${resultado!['total_repetitions'] ?? 0}',
        ),

        const SizedBox(height: 15),

        const Text(
          'Resumen de la sesión',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.45,
          children: [
            metricCard(
              'Flexión promedio',
              summary['mean_flexion_excursion_deg'],
              '°',
              icon: Icons.pan_tool_alt,
            ),

            metricCard(
              'Consistencia',
              summary['consistency_cv_pct'],
              '% CV',
              icon: Icons.repeat,
            ),

            metricCard(
              'Calidad del seguimiento',
              summary['mean_tracking_quality_pct'],
              '%',
              icon: Icons.camera_alt,
            ),
          ],
        ),

        const SizedBox(height: 15),

        const Text(
          'Excursión promedio de flexión por dedo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        Card(
          child: Column(
            children: fingerNames.entries.map((entry) {
              return detailRow(
                entry.value,
                fingerExcursions[entry.key],
                '°',
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          'Detalle por repetición',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        ...reps.map((rawRep) {
          final rep = Map<String, dynamic>.from(rawRep);

          final valid = rep['valid'] == true;

          final repExcursions = Map<String, dynamic>.from(
            rep['finger_excursions'] ?? {},
          );

          final minimumAngles = Map<String, dynamic>.from(
            rep['minimum_angles'] ?? {},
          );

          return Card(
            child: ExpansionTile(
              title: Text(
                'Repetición ${rep['number']}',
              ),

              subtitle: Text(
                valid
                    ? 'Datos válidos'
                    : 'Datos insuficientes',
              ),

              children: [
                detailRow(
                  'Calidad del seguimiento',
                  rep['tracking_quality_pct'],
                  '%',
                ),

                if (valid) ...[
                  detailRow(
                    'Flexión promedio',
                    rep['mean_flexion_excursion_deg'],
                    '°',
                  ),

                  const Divider(),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Excursión de flexión por dedo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  ...fingerNames.entries.map((entry) {
                    return detailRow(
                      entry.value,
                      repExcursions[entry.key],
                      '°',
                    );
                  }),

                  const Divider(),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Ángulos mínimos registrados',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  ...fingerNames.entries.map((entry) {
                    return detailRow(
                      entry.value,
                      minimumAngles[entry.key],
                      '°',
                    );
                  }),

                  detailRow(
                    'Número de muestras',
                    rep['samples_count'],
                    '',
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      rep['reason'] ??
                          'No se obtuvieron suficientes datos '
                          'para esta repetición.',
                    ),
                  ),
                ],
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        const Text(
          'Consideraciones sobre las métricas:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          '• La excursión de flexión representa la diferencia '
          'entre el ángulo de referencia de la mano abierta '
          'y el ángulo mínimo registrado durante el cierre.\n\n'
          '• Se evalúan el pulgar mediante su articulación IP '
          'y los demás dedos mediante sus articulaciones PIP.\n\n'
          '• La consistencia se estima mediante el coeficiente '
          'de variación de la excursión promedio entre repeticiones.\n\n'
          '• La calidad del seguimiento representa el porcentaje '
          'de fotogramas con detección válida de la mano.\n\n'
          'Los ángulos son estimaciones proyectadas en 2D y no '
          'mediciones goniométricas clínicas directas.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  // ==================================================
  // RESULTADOS
  // ==================================================

  Widget resultados() {
    if (resultado == null) {
      return const SizedBox.shrink();
    }

    final summary = Map<String, dynamic>.from(
      resultado!['summary'] ?? {},
    );

    final repsRaw = resultado!['repetitions'];

    final List reps = repsRaw is List ? repsRaw : [];

    // Si el ejercicio fue movimiento de muñeca,
    // mostrar sus métricas específicas.
    if (resultado!['exercise'] == 'wrist_movement') {
      return resultadosMuneca(summary, reps);
    }

    if (resultado!['exercise'] == 'finger_abduction') {
      return resultadosAbduccion(summary, reps);
    }
    if (resultado!['exercise'] == 'full_fist') {
      return resultadosPunoCompleto(summary, reps);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 25),

        const Text(
          'Resultados de la prueba',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Repeticiones válidas: '
          '${summary['valid_repetitions'] ?? 0}/'
          '${resultado!['total_repetitions'] ?? 0}',
        ),

        const SizedBox(height: 15),

        // ==========================================
        // RESUMEN DE LA SESIÓN
        // ==========================================

        const Text(
          'Resumen de la sesión',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.45,
          children: [
            metricCard(
              'Excursión promedio',
              summary['mean_excursion'],
              'normalizada',
              icon: Icons.open_in_full,
            ),

            metricCard(
              'Consistencia',
              summary['consistency_cv_pct'],
              '% CV',
              icon: Icons.repeat,
            ),

            metricCard(
              'Movimiento compensatorio',
              summary['mean_compensatory_movement_deg'],
              '°',
              icon: Icons.pan_tool_alt,
            ),

            metricCard(
              'Suavidad del movimiento',
              summary['mean_normalized_jerk'],
              '',
              icon: Icons.show_chart,
            ),

            metricCard(
              'Estabilidad del pinzamiento',
              summary['mean_pinch_stability_std'],
              'normalizada',
              icon: Icons.front_hand,
            ),

            metricCard(
              'Calidad del seguimiento',
              summary['mean_tracking_quality_pct'],
              '%',
              icon: Icons.camera_alt,
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ==========================================
        // DETALLE POR REPETICIÓN
        // ==========================================

        const Text(
          'Detalle por repetición',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        ...reps.map((rawRep) {
          final rep = Map<String, dynamic>.from(rawRep);

          final fingerMovement = Map<String, dynamic>.from(
            rep['finger_movement_deg'] ?? {},
          );

          final valid = rep['valid'] == true;

          return Card(
            child: ExpansionTile(
              title: Text(
                'Repetición ${rep['number']}',
              ),

              subtitle: Text(
                valid
                    ? 'Datos válidos'
                    : 'Datos insuficientes',
              ),

              children: [
                // Calidad de seguimiento:
                // se muestra incluso si la repetición
                // no tiene suficientes datos para calcular
                // las demás métricas.

                detailRow(
                  'Calidad del seguimiento',
                  rep['tracking_quality_pct'],
                  '%',
                ),

                if (valid) ...[
                  detailRow(
                    'Excursión del pinzamiento',
                    rep['pinch_excursion'],
                    'normalizada',
                  ),

                  detailRow(
                    'Distancia mínima',
                    rep['minimum_distance'],
                    'normalizada',
                  ),

                  detailRow(
                    'Velocidad máxima de cierre',
                    rep['maximum_closing_velocity'],
                    '/s',
                  ),

                  detailRow(
                    'Velocidad máxima de apertura',
                    rep['maximum_opening_velocity'],
                    '/s',
                  ),

                  detailRow(
                    'Rango angular PIP',
                    rep['pip_rom'],
                    '°',
                  ),

                  detailRow(
                    'Rango angular DIP',
                    rep['dip_rom'],
                    '°',
                  ),

                  const Divider(),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Movimiento de dedos no objetivo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  detailRow(
                    'Dedo medio',
                    fingerMovement['middle'],
                    '°',
                  ),

                  detailRow(
                    'Dedo anular',
                    fingerMovement['ring'],
                    '°',
                  ),

                  detailRow(
                    'Dedo meñique',
                    fingerMovement['pinky'],
                    '°',
                  ),

                  detailRow(
                    'Movimiento compensatorio promedio',
                    rep['mean_compensatory_movement_deg'],
                    '°',
                  ),

                  const Divider(),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Calidad del movimiento',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  detailRow(
                    'Suavidad del movimiento',
                    rep['normalized_jerk'],
                    '',
                  ),

                  detailRow(
                    'Estabilidad del pinzamiento',
                    rep['pinch_stability_std'],
                    'normalizada',
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      rep['message'] ??
                          'No se obtuvieron suficientes datos '
                          'para esta repetición.',
                    ),
                  ),
                ],
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        // ==========================================
        // NOTAS METODOLÓGICAS
        // ==========================================

        const Text(
          'Consideraciones sobre las métricas:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          '• La suavidad se estima mediante el jerk normalizado. '
          'Un valor menor representa un movimiento más suave.\n\n'
          '• La estabilidad se estima mediante la desviación '
          'estándar de la distancia durante el cierre del '
          'pinzamiento. Un valor menor representa mayor '
          'estabilidad.\n\n'
          '• La calidad del seguimiento representa el porcentaje '
          'de fotogramas en los que se detectó correctamente '
          'la mano.\n\n'
          '• El movimiento compensatorio es una métrica '
          'experimental basada en la desviación angular de los '
          'dedos no objetivo.\n\n'
          'Estas métricas son experimentales y no constituyen '
          'por sí solas una escala clínica validada.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }


  // ==================================================
  // DISPOSE
  // ==================================================

  @override
  void dispose() {
    pollingTimer?.cancel();
    repController.dispose();

    super.dispose();
  }

  // ==================================================
  // INTERFAZ
  // ==================================================

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),

      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 650,
          ),

          child: Column(
            children: [
              const Icon(
                Icons.camera_alt,
                size: 75,
                color: Colors.blue,
              ),

              const SizedBox(height: 20),

              const Text(
                'Prueba de movimientos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                mensaje,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              if (!pruebaActiva) ...[

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paciente de la evaluación',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (cargandoPacientes)
                          const Center(
                            child: CircularProgressIndicator(),
                          )
                        else if (pacientes.isEmpty)
                          const Text(
                            'No hay pacientes registrados. '
                            'Registra un paciente en la sección Pacientes.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          DropdownButtonFormField<Patient>(
                            value: pacienteSeleccionado,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                              hintText: 'Seleccionar paciente',
                            ),
                            items: pacientes.map((paciente) {
                              return DropdownMenuItem<Patient>(
                                value: paciente,
                                child: Text(
                                  '${paciente.nombre} ${paciente.apellido} '
                                  '(${paciente.edad} años)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: pruebaActiva
                                ? null
                                : (paciente) {
                                    setState(() {
                                      pacienteSeleccionado = paciente;
                                    });
                                  },
                          ),
                      ],
                    ),
                  ),
                ),
                // ==========================================
                // SELECTOR DE EJERCICIO
                // ==========================================
                
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    value: ejercicioSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Ejercicio',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pinch_index',
                        child: Text('Pinza índice'),
                      ),
                      DropdownMenuItem(
                        value: 'wrist_movement',
                        child: Text('Movimiento de muñeca'),
                      ),
                      DropdownMenuItem(
                        value: 'finger_abduction',
                        child: Text('Abducción de dedos'),
                      ),
                      DropdownMenuItem(
                        value: 'full_fist',
                        child: Text('Puño completo'),
                      ),
                    ],
                    onChanged: cargando
                        ? null
                        : (value) {
                            if (value == null) return;

                            setState(() {
                              ejercicioSeleccionado = value;
                              resultado = null;
                              mensaje = 'Configura las repeticiones e inicia la prueba.';
                            });
                          },
                  ),
                ),

                const SizedBox(height: 15),

                // ==========================================
                // NÚMERO DE REPETICIONES
                // ==========================================

                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: repController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de repeticiones',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              if (pruebaActiva) ...[
                const SizedBox(height: 15),

                Text(
                  fase == 'POSITIONING'
                      ? (repeticionActual == 0
                          ? 'Posicionamiento inicial'
                          : 'Reposicionamiento')
                      : 'Repetición $repeticionActual de $totalRepeticiones',

                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                LinearProgressIndicator(
                  value: totalRepeticiones > 0
                      ? repeticionActual / totalRepeticiones
                      : 0,
                ),
              ],

              const SizedBox(height: 25),

              SizedBox(
                width: 230,
                child: ElevatedButton.icon(
                  onPressed: cargando
                      ? null
                      : pruebaActiva
                          ? detenerPrueba
                          : iniciarPrueba,

                  icon: Icon(
                    pruebaActiva
                        ? Icons.stop
                        : Icons.play_arrow,
                  ),

                  label: Text(
                    cargando
                        ? 'Conectando...'
                        : pruebaActiva
                            ? 'Cancelar prueba'
                            : resultado != null
                                ? 'Repetir prueba'
                                : 'Iniciar prueba',
                  ),
                ),
              ),

              resultados(),
            ],
          ),
        ),
      ),
    );
  }
}
