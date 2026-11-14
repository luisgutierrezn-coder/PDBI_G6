
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../services/device_service.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final DeviceService _deviceService = DeviceService();

  bool _serverOnline = false;
  bool _checkingServer = false;
  bool _checkingAll = false;

  late List<DeviceInfo> _devices;

  List<Map<String, dynamic>> _placas = [];
  List<Map<String, dynamic>> _encontradas = [];
  bool _buscandoPlacas = false;
  String? _probandoEmg;

  bool _vistaPrevia = false;
  bool _cambiandoVista = false;
  Timer? _vistaTimer;

  @override
  void initState() {
    super.initState();

    _devices = [
      const DeviceInfo(
        id: 'camera_1',
        name: 'Cámara 1',
        description: 'ESP32-S3-CAM principal',
        source: '',
      ),
      const DeviceInfo(
        id: 'camera_2',
        name: 'Cámara 2',
        description: 'ESP32-S3-CAM secundaria',
        source: '',
      ),
    ];
  }

  @override
  void dispose() {
    _vistaTimer?.cancel();
    super.dispose();
  }

  // ==========================================
  // VISTA PREVIA (POSICIONAR LAS CÁMARAS)
  // ==========================================

  Future<void> _alternarVistaPrevia() async {
    setState(() => _cambiandoVista = true);

    final r = _vistaPrevia
        ? await _deviceService.stopPreview()
        : await _deviceService.startPreview();

    if (!mounted) return;

    final activa = !_vistaPrevia && r['success'] == true;

    setState(() {
      _cambiandoVista = false;
      _vistaPrevia = activa;
    });

    _vistaTimer?.cancel();

    if (activa) {
      _mensaje(
        'Vista previa abierta en ventanas de Python. Acomoda la mano hasta ver "Mano detectada".',
      );
      // Si se cierra la ventana (Esc o X), el botón vuelve a su estado.
      _vistaTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        final estado = await _deviceService.getPreview();
        if (!mounted) return;
        if (estado['activa'] != true) {
          _vistaTimer?.cancel();
          setState(() => _vistaPrevia = false);
        }
      });
    } else if (r['success'] != true) {
      _mensaje(_error(r));
    }
  }

  // ==========================================
  // ACTUALIZAR ESTADO DE UNA CÁMARA
  // ==========================================

  void _updateCamera(
    String cameraId, {
    String? source,
    DeviceConnectionStatus? status,
  }) {
    setState(() {
      _devices = _devices.map((device) {
        if (device.id != cameraId) return device;

        return device.copyWith(
          source: source,
          status: status,
        );
      }).toList();
    });
  }

  // ==========================================
  // COMPROBAR SERVIDOR
  // ==========================================

  Future<void> _checkServer() async {
    setState(() {
      _checkingServer = true;
    });

    final result = await _deviceService.checkServer();

    if (!mounted) return;

    setState(() {
      _serverOnline = result['success'] == true;
      _checkingServer = false;
    });

    if (_serverOnline) _actualizarPlacas();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _serverOnline
              ? 'Servidor Python conectado.'
              : 'No se pudo conectar con Python.',
        ),
      ),
    );
  }

  // ==========================================
  // CONFIGURAR CÁMARA
  // ==========================================

  Future<void> _configureCamera(DeviceInfo device) async {
    final controller = TextEditingController(
      text: device.source == '0' ? '' : device.source,
    );

    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Configurar ${device.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresa la dirección del stream de la ESP32-S3-CAM.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Dirección IP / URL',
                  hintText: 'http://192.168.1.101/stream',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text.trim(),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (source == null || source.isEmpty) return;

    _updateCamera(
      device.id,
      status: DeviceConnectionStatus.connecting,
    );

    final result = await _deviceService.configureCamera(
      device.id,
      source,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      _updateCamera(
        device.id,
        source: source,
        status: DeviceConnectionStatus.disconnected,
      );
    } else {
      _updateCamera(
        device.id,
        status: DeviceConnectionStatus.error,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? '${device.name} configurada correctamente.'
              : 'Error al configurar: ${result['message'] ?? 'Error desconocido'}',
        ),
      ),
    );
  }

  // ==========================================
  // PROBAR CÁMARA INDIVIDUAL
  // ==========================================


  Future<void> _checkCamera(DeviceInfo device) async {
    if (device.source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero debes configurar la cámara.'),
        ),
      );
      return;
    }

    // _updateCamera ya ejecuta setState internamente.
    _updateCamera(
      device.id,
      status: DeviceConnectionStatus.connecting,
    );

    final result = await _deviceService.checkCamera(device.id);

    if (!mounted) return;

    final available = result['available'] == true;

    _updateCamera(
      device.id,
      status: available
          ? DeviceConnectionStatus.connected
          : DeviceConnectionStatus.error,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          available
              ? '${device.name} disponible.'
              : 'No se pudo recibir video de ${device.name}. '
                '${result['message'] ?? ''}',
        ),
      ),
    );
  }

  // ==========================================
  // COMPROBAR AMBAS CÁMARAS
  // ==========================================

  Future<void> _checkAllCameras() async {
    setState(() {
      _checkingAll = true;
    });

    // Actualizamos cada cámara fuera de setState.
    for (final device in _devices) {
      if (device.source.isNotEmpty) {
        _updateCamera(
          device.id,
          status: DeviceConnectionStatus.connecting,
        );
      }
    }

    final result = await _deviceService.checkAllCameras();

    if (!mounted) return;

    final cameras = result['cameras'];

    if (cameras is Map) {
      for (final device in List<DeviceInfo>.from(_devices)) {
        final available = cameras[device.id] == true;

        _updateCamera(
          device.id,
          status: device.source.isEmpty
              ? DeviceConnectionStatus.notConfigured
              : available
                  ? DeviceConnectionStatus.connected
                  : DeviceConnectionStatus.error,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      _checkingAll = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Comprobación de cámaras finalizada.'
              : 'No se pudo comprobar las cámaras.',
        ),
      ),
    );
  }

  // ==========================================
  // PLACAS MAKI (EMG + CÁMARA)
  // ==========================================

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  String _error(Map<String, dynamic> r) =>
      (r['message'] ?? r['detail'] ?? 'Error desconocido').toString();

  Future<void> _actualizarPlacas() async {
    final placas = await _deviceService.getPlacas();
    final devices = await _deviceService.getDevices();

    if (!mounted) return;

    setState(() {
      final lista = placas['placas'];
      _placas = lista is List
          ? lista.map((p) => Map<String, dynamic>.from(p as Map)).toList()
          : [];
      _encontradas.removeWhere(
        (e) => _placas.any((p) => p['ip'] == e['ip']),
      );

      final info = devices['devices'];
      if (info is Map) {
        _devices = _devices.map((device) {
          final estado = info[device.id];
          final source = estado is Map ? (estado['source'] ?? '').toString() : '';
          if (source == device.source) return device;
          return device.copyWith(
            source: source,
            status: source.isEmpty
                ? DeviceConnectionStatus.notConfigured
                : DeviceConnectionStatus.disconnected,
          );
        }).toList();
      }
    });
  }

  Future<void> _buscarPlacas() async {
    setState(() => _buscandoPlacas = true);

    final r = await _deviceService.buscarPlacas();

    if (!mounted) return;

    final lista = r['encontradas'];

    setState(() {
      _buscandoPlacas = false;
      _encontradas = lista is List
          ? lista
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) => !_placas.any((p) => p['ip'] == e['ip']))
              .toList()
          : [];
    });

    if (r['success'] != true) {
      _mensaje(_error(r));
    } else if (_encontradas.isEmpty) {
      _mensaje(
        _placas.isEmpty
            ? 'No se encontraron placas. ¿Están encendidas y en la misma red?'
            : 'No hay placas nuevas en la red.',
      );
    }
  }

  Future<void> _conectarPlaca(Map<String, dynamic> encontrada) async {
    final nombre = (encontrada['nombre'] ?? '').toString();
    final sugerida = nombre.contains('muneca') ? 'camera_2' : 'camera_1';

    final camara = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('¿Qué cámara es $nombre?'),
        children: [
          for (final opcion in const [
            ['camera_1', 'Cámara 1 (principal, mide)'],
            ['camera_2', 'Cámara 2 (secundaria)'],
            ['ninguna', 'Sin cámara (solo EMG)'],
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, opcion[0]),
              child: Row(
                children: [
                  Icon(
                    opcion[0] == sugerida
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(opcion[1]),
                ],
              ),
            ),
        ],
      ),
    );

    if (camara == null) return;

    final r = await _deviceService.conectarPlaca(
      encontrada['ip'].toString(),
      camara == 'ninguna' ? null : camara,
    );

    if (!mounted) return;

    _mensaje(r['success'] == true ? '$nombre conectada.' : _error(r));
    await _actualizarPlacas();
  }

  Future<void> _desconectarPlaca(String ip) async {
    await _deviceService.desconectarPlaca(ip);
    await _actualizarPlacas();
  }

  Future<void> _probarEmg(Map<String, dynamic> placa) async {
    final ip = placa['ip'].toString();
    final r = await _deviceService.ordenPlaca(ip, 'MEDIR');

    if (!mounted) return;

    if (r['success'] != true) {
      _mensaje('No se pudo medir: ${r['respuesta'] ?? _error(r)}');
      return;
    }

    setState(() => _probandoEmg = ip);

    for (int i = 0; i < 20 && mounted; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      await _actualizarPlacas();
    }

    await _deviceService.ordenPlaca(ip, 'PARAR');

    if (!mounted) return;

    setState(() => _probandoEmg = null);
  }

  Future<void> _olvidarWifi(Map<String, dynamic> placa) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Olvidar red Wi-Fi'),
        content: Text(
          '${placa['nombre']} borrará su red guardada y se reiniciará. '
          'Después habrá que configurarla de nuevo por Bluetooth.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Olvidar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final ip = placa['ip'].toString();
    await _deviceService.ordenPlaca(ip, 'WIFI OLVIDAR');
    await _deviceService.desconectarPlaca(ip);
    await _actualizarPlacas();
  }

  Future<void> _configurarWifi() async {
    final red = await _deviceService.wifiLaptop();

    if (!mounted) return;

    final ssidLaptop = red['success'] == true ? red['ssid'].toString() : '';
    final ssidCtrl = TextEditingController(text: ssidLaptop);
    final claveCtrl = TextEditingController();
    final tieneClave = red['tiene_clave'] == true;
    final banda5 = red['banda_5ghz'] == true;

    List<Map<String, dynamic>> dispositivos = [];
    String? elegido;
    String? estado = red['success'] == true ? null : _error(red);
    bool buscando = false;
    bool enviando = false;
    bool abierto = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          void actualizar(VoidCallback cambio) {
            if (abierto) setDialog(cambio);
          }

          Future<void> buscar() async {
            actualizar(() {
              buscando = true;
              estado = 'Buscando placas por Bluetooth...';
            });

            final r = await _deviceService.buscarBluetooth();
            final lista = r['dispositivos'];

            actualizar(() {
              buscando = false;
              dispositivos = lista is List
                  ? lista.map((d) => Map<String, dynamic>.from(d as Map)).toList()
                  : [];
              if (dispositivos.length == 1) {
                elegido = dispositivos.first['address']?.toString();
              }
              estado = r['success'] != true
                  ? _error(r)
                  : dispositivos.isEmpty
                      ? 'No apareció ninguna placa. Enciéndela y espera unos 15 s.'
                      : null;
            });
          }

          Future<void> enviar() async {
            final ssid = ssidCtrl.text.trim();
            final clave = claveCtrl.text;

            if (ssid != ssidLaptop && clave.isEmpty) {
              actualizar(() => estado = 'Escribe la clave de $ssid.');
              return;
            }

            actualizar(() {
              enviando = true;
              estado = 'Enviando la red a la placa (puede tardar hasta 30 s)...';
            });

            final r = await _deviceService.configurarWifiBluetooth(
              elegido!,
              ssid: ssid,
              clave: clave,
            );

            actualizar(() {
              enviando = false;
              estado = _error(r);
            });

            if (r['success'] == true && mounted) {
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) _buscarPlacas();
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bluetooth),
                SizedBox(width: 10),
                Text('Configurar Wi-Fi de una placa'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ssidCtrl,
                      enabled: !enviando,
                      decoration: const InputDecoration(
                        labelText: 'Red Wi-Fi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (banda5)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'La laptop está en 5 GHz: la placa solo usa 2.4 GHz.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: claveCtrl,
                      enabled: !enviando,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Clave',
                        helperText: tieneClave
                            ? 'Vacía = la guardada en la laptop para esta red.'
                            : 'No se pudo leer la clave de la laptop: escríbela.',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Placas por Bluetooth',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: buscando || enviando ? null : buscar,
                          icon: buscando
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.bluetooth_searching),
                          label: const Text('Buscar'),
                        ),
                      ],
                    ),
                    ...dispositivos.map((d) {
                      final address = d['address']?.toString();
                      final seleccionado = address == elegido;

                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.memory),
                        title: Text((d['nombre'] ?? 'MaKi').toString()),
                        subtitle: Text(address ?? ''),
                        selected: seleccionado,
                        trailing: seleccionado
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        onTap: enviando
                            ? null
                            : () => actualizar(() => elegido = address),
                      );
                    }),
                    if (estado != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(estado!),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: enviando ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
              FilledButton.icon(
                onPressed: elegido == null || buscando || enviando ? null : enviar,
                icon: const Icon(Icons.wifi),
                label: const Text('Enviar red'),
              ),
            ],
          );
        },
      ),
    );

    abierto = false;
    ssidCtrl.dispose();
    claveCtrl.dispose();
  }

  // ==========================================
  // ESTADOS VISUALES
  // ==========================================

  String _statusText(DeviceConnectionStatus status) {
    switch (status) {
      case DeviceConnectionStatus.notConfigured:
        return 'Sin configurar';

      case DeviceConnectionStatus.disconnected:
        return 'Configurada';

      case DeviceConnectionStatus.connecting:
        return 'Comprobando...';

      case DeviceConnectionStatus.connected:
        return 'Disponible';

      case DeviceConnectionStatus.error:
        return 'Sin conexión';
    }
  }

  Color _statusColor(DeviceConnectionStatus status) {
    switch (status) {
      case DeviceConnectionStatus.notConfigured:
        return Colors.grey;

      case DeviceConnectionStatus.disconnected:
        return Colors.orange;

      case DeviceConnectionStatus.connecting:
        return Colors.blue;

      case DeviceConnectionStatus.connected:
        return Colors.green;

      case DeviceConnectionStatus.error:
        return Colors.red;
    }
  }

  Widget _buildStatusIndicator(DeviceConnectionStatus status) {
    final color = _statusColor(status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          _statusText(status),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TARJETA DEL SERVIDOR
  // ==========================================

  Widget _buildServerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.computer, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servidor Python',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'FastAPI · 127.0.0.1:8000',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                _buildStatusIndicator(
                  _serverOnline
                      ? DeviceConnectionStatus.connected
                      : DeviceConnectionStatus.disconnected,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _checkingServer ? null : _checkServer,
                icon: _checkingServer
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  _checkingServer
                      ? 'Comprobando...'
                      : 'Comprobar conexión',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TARJETA DE CÁMARA
  // ==========================================

  Widget _buildCameraCard(DeviceInfo device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        device.description,
                        style: const TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusIndicator(device.status),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              device.source.isEmpty
                  ? 'Dirección: No configurada'
                  : 'Dirección: ${device.source}',
              style: const TextStyle(fontSize: 13),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _serverOnline
                        ? () => _configureCamera(device)
                        : null,
                    icon: const Icon(Icons.settings),
                    label: const Text('Configurar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _serverOnline &&
                            device.source.isNotEmpty &&
                            device.status !=
                                DeviceConnectionStatus.connecting
                        ? () => _checkCamera(device)
                        : null,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Probar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TARJETAS DE PLACAS
  // ==========================================

  Widget _buildPlacasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Placas MaKi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _serverOnline ? _configurarWifi : null,
              icon: const Icon(Icons.bluetooth),
              label: const Text('Configurar Wi-Fi'),
            ),
            TextButton.icon(
              onPressed: _serverOnline && !_buscandoPlacas ? _buscarPlacas : null,
              icon: _buscandoPlacas
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: const Text('Buscar en la red'),
            ),
          ],
        ),
        const Text(
          'Cada placa lleva el EMG y su cámara. Una placa nueva o en otra red se configura '
          'primero por Bluetooth.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ..._encontradas.map(
          (e) => Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: Text((e['nombre'] ?? 'Placa MaKi').toString()),
              subtitle: Text('Encontrada en ${e['ip']}'),
              trailing: FilledButton(
                onPressed: () => _conectarPlaca(e),
                child: const Text('Conectar'),
              ),
            ),
          ),
        ),
        ..._placas.map(_buildPlacaCard),
      ],
    );
  }

  Widget _buildPlacaCard(Map<String, dynamic> placa) {
    final ip = placa['ip'].toString();
    final conectada = placa['conectada'] == true;
    final canales = (placa['canales'] as List?)?.join(', ') ?? '';
    final camara = switch (placa['camera_id']) {
      'camera_1' => 'Cámara 1',
      'camera_2' => 'Cámara 2',
      _ => 'sin cámara',
    };
    final video = placa['video_url'] != null ? 'video encendido' : 'video apagado';
    final mv = placa['ultimo_mv'];
    final valores = mv is Map && mv['valores'] is Map
        ? (mv['valores'] as Map).entries
            .map((e) => '${e.key} ${(e.value as num).toStringAsFixed(1)} mV')
            .join(' · ')
        : null;
    final sueltos = mv is Map ? mv['sueltos'] : null;
    final probando = _probandoEmg == ip;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (placa['nombre'] ?? ip).toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$ip · $canales',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                _buildStatusIndicator(
                  conectada
                      ? DeviceConnectionStatus.connected
                      : DeviceConnectionStatus.error,
                ),
                PopupMenuButton<String>(
                  onSelected: (opcion) {
                    if (opcion == 'desconectar') _desconectarPlaca(ip);
                    if (opcion == 'olvidar') _olvidarWifi(placa);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'desconectar',
                      child: Text('Desconectar'),
                    ),
                    PopupMenuItem(
                      value: 'olvidar',
                      child: Text('Olvidar red Wi-Fi'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Usa la $camara · $video',
              style: const TextStyle(fontSize: 13),
            ),
            if (probando && valores != null) ...[
              const SizedBox(height: 8),
              Text(
                valores,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF243F60),
                ),
              ),
              if (sueltos is num && sueltos > 0)
                const Text(
                  'Hay electrodos sueltos: revisa la banda.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
            if (placa['ultimo_error'] != null) ...[
              const SizedBox(height: 6),
              Text(
                'Último error: ${placa['ultimo_error']}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: conectada && _probandoEmg == null
                    ? () => _probarEmg(placa)
                    : null,
                icon: probando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.monitor_heart),
                label: Text(probando ? 'Midiendo 5 s...' : 'Probar EMG'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // INTERFAZ
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Servidor',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            _buildServerCard(),

            const SizedBox(height: 24),

            _buildPlacasSection(),

            const SizedBox(height: 24),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cámaras',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _serverOnline && !_cambiandoVista
                      ? _alternarVistaPrevia
                      : null,
                  icon: _cambiandoVista
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_vistaPrevia ? Icons.videocam_off : Icons.videocam),
                  label: Text(_vistaPrevia ? 'Cerrar vista previa' : 'Vista previa'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _serverOnline && !_checkingAll && !_vistaPrevia
                      ? _checkAllCameras
                      : null,
                  icon: _checkingAll
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Probar ambas'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ..._devices.map(_buildCameraCard),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
