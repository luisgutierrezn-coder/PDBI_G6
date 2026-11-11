
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
                TextButton.icon(
                  onPressed: _serverOnline && !_checkingAll
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
