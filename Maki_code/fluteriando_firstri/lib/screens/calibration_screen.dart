import 'dart:async';

import 'package:flutter/material.dart';

import '../models/patient.dart';
import '../services/database_service.dart';
import '../services/device_service.dart';

class CalibrationScreen extends StatefulWidget {
  final Patient patient;
  final ValueChanged<Map<String, Map<String, dynamic>>> onComplete;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  const CalibrationScreen({
    super.key,
    required this.patient,
    required this.onComplete,
    required this.onSkip,
    required this.onCancel,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _Paso { preparacion, reposo, mvc, resumen }

class _CalibrationScreenState extends State<CalibrationScreen> {
  final DeviceService _service = DeviceService();

  bool _cargando = true;
  bool _seguridad = false;
  bool _revisando = false;
  bool _midiendo = false;

  _Paso _paso = _Paso.preparacion;
  int _canalActual = 0;
  int _cuenta = 0;
  int _duracion = 1;
  Timer? _timer;
  String? _error;

  List<String> _canales = [];
  Map<String, dynamic> _electrodos = {};
  final Map<String, Map<String, dynamic>> _resultado = {};
  Map<String, Map<String, dynamic>> _anterior = {};

  static const Color _azul = Color(0xFF243F60);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ==========================================
  // DATOS
  // ==========================================

  Future<void> _cargar() async {
    final r = await _service.calibracionCanales();
    final lista = r['canales'];
    Map<String, Map<String, dynamic>> anterior = {};

    if (widget.patient.id != null) {
      try {
        anterior = await DatabaseService.instance
            .getLastEmgCalibration(widget.patient.id!);
      } catch (e) {
        debugPrint('No se pudo leer la calibración anterior: $e');
      }
    }

    if (!mounted) return;

    setState(() {
      _canales = lista is List ? lista.map((c) => c.toString()).toList() : [];
      _anterior = anterior;
      _cargando = false;
      if (r['success'] == false) _error = r['message']?.toString();
    });
  }

  (String, String, String) _gesto(String canal) {
    return switch (canal) {
      'flexores' => (
          'Flexores',
          'Cierra el puño con toda tu fuerza.',
          'assets/images/fist_my_bump.png',
        ),
      'extensores' => (
          'Extensores',
          'Abre la mano y estira los dedos al máximo.',
          'assets/images/open.png',
        ),
      'muneca' => (
          'Pinza',
          'Junta la punta del pulgar y del índice y aprieta con fuerza.',
          'assets/images/pincer_thumb.png',
        ),
      _ => (
          canal,
          'Contrae el músculo con toda tu fuerza.',
          'assets/images/fist_my_bump.png',
        ),
    };
  }

  String _traducir(String error) {
    if (error.contains('error,suelto')) {
      return 'Electrodo suelto en ${error.split(',').last}: revisa la banda y repite.';
    }
    if (error.contains('error,ocupado')) {
      return 'La placa estaba ocupada. Intenta de nuevo.';
    }
    if (error.contains('error,falta_reposo')) {
      return 'Primero hay que medir el reposo.';
    }
    if (error.contains('sin respuesta')) {
      return 'La placa no respondió. Revisa la conexión en Dispositivos.';
    }
    return error;
  }

  // ==========================================
  // CUENTA REGRESIVA
  // ==========================================

  void _iniciarCuenta(int segundos) {
    _timer?.cancel();
    _duracion = segundos;
    _cuenta = segundos;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cuenta <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _cuenta--);
    });
  }

  void _detenerCuenta() {
    _timer?.cancel();
    _cuenta = 0;
  }

  // ==========================================
  // PASOS
  // ==========================================

  Future<void> _revisar() async {
    setState(() {
      _revisando = true;
      _error = null;
    });

    final r = await _service.revisarElectrodos();

    if (!mounted) return;

    setState(() {
      _revisando = false;
      _electrodos = r['canales'] is Map
          ? Map<String, dynamic>.from(r['canales'] as Map)
          : {};
      if (_electrodos.isEmpty) {
        _error = r['message']?.toString() ?? 'Las placas no respondieron.';
      }
    });
  }

  Future<void> _medirReposo() async {
    setState(() {
      _midiendo = true;
      _error = null;
      _resultado.clear();
    });
    _iniciarCuenta(8);

    final r = await _service.calibrarReposo();

    if (!mounted) return;

    _detenerCuenta();

    setState(() {
      _midiendo = false;

      if (r['success'] == true && r['canales'] is Map) {
        (r['canales'] as Map).forEach((canal, datos) {
          _resultado[canal.toString()] = Map<String, dynamic>.from(datos as Map);
        });
        _paso = _Paso.mvc;
        _canalActual = 0;
      } else {
        final errores = r['errores'];
        _error = errores is List && errores.isNotEmpty
            ? errores.map((e) => _traducir(e.toString())).join('\n')
            : (r['message'] ?? 'No se pudo medir el reposo.').toString();
      }
    });
  }

  Future<void> _medirMvc() async {
    final canal = _canales[_canalActual];

    setState(() {
      _midiendo = true;
      _error = null;
      _resultado[canal]?.remove('calidad');
    });
    _iniciarCuenta(5);

    final r = await _service.calibrarMvc(canal);

    if (!mounted) return;

    _detenerCuenta();

    setState(() {
      _midiendo = false;

      if (r['success'] == true && r['datos'] is Map) {
        _resultado[canal] = Map<String, dynamic>.from(r['datos'] as Map);
      } else {
        _error = _traducir((r['error'] ?? r['message'] ?? 'Error desconocido').toString());
      }
    });
  }

  void _siguienteCanal() {
    setState(() {
      _error = null;
      if (_canalActual < _canales.length - 1) {
        _canalActual++;
      } else {
        _paso = _Paso.resumen;
      }
    });
  }

  void _repetirTodo() {
    setState(() {
      _resultado.clear();
      _error = null;
      _canalActual = 0;
      _paso = _Paso.reposo;
    });
  }

  // ==========================================
  // INTERFAZ
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Calibración · ${widget.patient.nombre} ${widget.patient.apellido}'),
        leading: IconButton(
          tooltip: 'Cancelar sesión',
          icon: const Icon(Icons.close),
          onPressed: _midiendo ? null : widget.onCancel,
        ),
        actions: [
          TextButton(
            onPressed: _midiendo ? null : widget.onSkip,
            child: const Text('Omitir calibración'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPasos(),
                      const SizedBox(height: 20),
                      switch (_paso) {
                        _Paso.preparacion => _buildPreparacion(),
                        _Paso.reposo => _buildReposo(),
                        _Paso.mvc => _buildMvc(),
                        _Paso.resumen => _buildResumen(),
                      },
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _buildAviso(_error!, Colors.red),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPasos() {
    const nombres = ['Preparación', 'Reposo', 'Esfuerzo máximo', 'Resumen'];

    return Row(
      children: List.generate(nombres.length, (i) {
        final activo = i == _paso.index;
        final hecho = i < _paso.index;

        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: activo || hecho ? _azul : Colors.grey.shade300,
                child: hecho
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: activo ? Colors.white : Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                nombres[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.bold : FontWeight.normal,
                  color: activo ? _azul : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _tarjeta(List<Widget> hijos) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hijos,
      ),
    );
  }

  Widget _titulo(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: Color(0xFF243447),
      ),
    );
  }

  Widget _buildAviso(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(texto, style: TextStyle(color: color)),
    );
  }

  Widget _buildCuenta(String texto) {
    return Column(
      children: [
        Text(
          '$_cuenta',
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.bold,
            color: _azul,
          ),
        ),
        Text(texto, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _duracion > 0 ? 1 - _cuenta / _duracion : null,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  // ---------- 1. Preparación ----------

  Widget _buildPreparacion() {
    if (_canales.isEmpty) {
      return _tarjeta([
        _titulo('No hay placas EMG conectadas'),
        const SizedBox(height: 8),
        const Text(
          'Para medir la actividad muscular, conecta las placas en Dispositivos. '
          'También puedes continuar solo con la cámara.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _cargando = true);
                _cargar();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a buscar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar sin EMG'),
            ),
          ],
        ),
      ]);
    }

    return _tarjeta([
      _titulo('Antes de empezar'),
      const SizedBox(height: 12),
      _buildAviso(
        'Seguridad: con los electrodos puestos, la laptop debe estar DESENCHUFADA '
        '(solo con batería).',
        Colors.orange.shade800,
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _seguridad,
        onChanged: (v) => setState(() => _seguridad = v ?? false),
        title: const Text('Confirmo que la laptop está desenchufada'),
      ),
      const SizedBox(height: 4),
      const Text('1. Coloca las bandas en el antebrazo, siempre en el mismo lugar.'),
      const Text('2. Apoya el brazo en la mesa, con la mano relajada.'),
      const Text('3. Revisa los electrodos antes de calibrar.'),
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Electrodos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: _revisando ? null : _revisar,
            icon: _revisando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sensors),
            label: const Text('Revisar electrodos'),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _canales.map((canal) {
          final estado = _electrodos[canal] is Map
              ? (_electrodos[canal] as Map)['estado']?.toString()
              : null;
          final (texto, color) = switch (estado) {
            'ok' => ('bien', Colors.green),
            'suelto' => ('suelto', Colors.red),
            'sin_senal' => ('sin señal', Colors.red),
            'saturado' => ('saturado', Colors.orange),
            _ => ('sin revisar', Colors.grey),
          };

          return Chip(
            avatar: Icon(Icons.circle, size: 12, color: color),
            label: Text('${_gesto(canal).$1}: $texto'),
          );
        }).toList(),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: _seguridad
              ? () => setState(() {
                    _error = null;
                    _paso = _Paso.reposo;
                  })
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Comenzar calibración'),
        ),
      ),
    ]);
  }

  // ---------- 2. Reposo ----------

  Widget _buildReposo() {
    return _tarjeta([
      _titulo('Reposo'),
      const SizedBox(height: 8),
      const Text(
        'Deja la mano relajada sobre la mesa y no te muevas. '
        'Se mide la actividad del músculo en reposo durante 8 segundos.',
      ),
      const SizedBox(height: 24),
      if (_midiendo)
        _buildCuenta(_cuenta > 3 ? 'Relájate...' : 'Midiendo, no te muevas')
      else
        const Center(
          child: Icon(Icons.back_hand_outlined, size: 90, color: _azul),
        ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: _midiendo ? null : _medirReposo,
          icon: const Icon(Icons.timer_outlined),
          label: Text(_error == null ? 'Medir reposo' : 'Repetir reposo'),
        ),
      ),
    ]);
  }

  // ---------- 3. Esfuerzo máximo ----------

  Widget _buildMvc() {
    final canal = _canales[_canalActual];
    final (nombre, instruccion, imagen) = _gesto(canal);
    final datos = _resultado[canal] ?? {};
    final calidad = datos['calidad']?.toString();
    final anterior = _anterior[canal]?['mvc_mv'];

    return _tarjeta([
      _titulo('Esfuerzo máximo · $nombre (${_canalActual + 1} de ${_canales.length})'),
      const SizedBox(height: 8),
      Text(instruccion, style: const TextStyle(fontSize: 16)),
      const Text(
        'Al pulsar "Medir", haz el gesto con toda la fuerza y mantenlo durante 5 segundos.',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 20),
      Center(
        child: _midiendo
            ? _buildCuenta('¡Fuerza! Mantén el gesto')
            : Image.asset(
                imagen,
                height: 160,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.front_hand, size: 90, color: _azul),
              ),
      ),
      if (calidad != null && !_midiendo) ...[
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _dato('Máximo', '${_num(datos['mvc_mv'])} mV'),
            ),
            Expanded(
              child: _dato('Veces el reposo', '${_num(datos['mvc_veces_reposo'])}×'),
            ),
            Expanded(
              child: _dato(
                'Sesión anterior',
                anterior is num ? '${anterior.toStringAsFixed(1)} mV' : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        switch (calidad) {
          'ok' => _buildAviso('Buena señal.', Colors.green.shade700),
          'debil' => _buildAviso(
              'Señal débil: los porcentajes serán aproximados. Revisa el contacto o repite.',
              Colors.orange.shade800,
            ),
          _ => _buildAviso(
              'El músculo no se activó lo suficiente. Repite la medición.',
              Colors.red,
            ),
        },
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _midiendo ? null : _medirMvc,
              icon: const Icon(Icons.fitness_center),
              label: Text(calidad == null ? 'Medir' : 'Repetir'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: !_midiendo && (calidad == 'ok' || calidad == 'debil')
                  ? _siguienteCanal
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                _canalActual < _canales.length - 1 ? 'Siguiente músculo' : 'Ver resumen',
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  // ---------- 4. Resumen ----------

  Widget _buildResumen() {
    return _tarjeta([
      _titulo('Resumen de la calibración'),
      const SizedBox(height: 16),
      Table(
        columnWidths: const {0: FlexColumnWidth(1.4)},
        children: [
          _fila(['Músculo', 'Reposo', 'Máximo', '× reposo', 'Anterior', 'Calidad'], negrita: true),
          ..._canales.map((canal) {
            final d = _resultado[canal] ?? {};
            final anterior = _anterior[canal]?['mvc_mv'];
            return _fila([
              _gesto(canal).$1,
              '${_num(d['reposo_mv'])} mV',
              '${_num(d['mvc_mv'])} mV',
              '${_num(d['mvc_veces_reposo'])}×',
              anterior is num ? '${anterior.toStringAsFixed(1)} mV' : '—',
              switch (d['calidad']) {
                'ok' => 'buena',
                'debil' => 'débil',
                _ => '—',
              },
            ]);
          }),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _repetirTodo,
              icon: const Icon(Icons.replay),
              label: const Text('Repetir calibración'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => widget.onComplete(Map.of(_resultado)),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar a los ejercicios'),
            ),
          ),
        ],
      ),
    ]);
  }

  TableRow _fila(List<String> celdas, {bool negrita = false}) {
    return TableRow(
      children: celdas
          .map(
            (c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                c,
                style: TextStyle(
                  fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
                  color: negrita ? Colors.grey.shade700 : const Color(0xFF243447),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: _azul,
          ),
        ),
      ],
    );
  }

  String _num(dynamic v) => v is num ? v.toStringAsFixed(1) : '—';
}
