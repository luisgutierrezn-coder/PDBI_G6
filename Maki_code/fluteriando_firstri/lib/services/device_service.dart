
import 'dart:convert';
import 'package:http/http.dart' as http;

class DeviceService {
  static const String _baseUrl = 'http://127.0.0.1:8000';

  // ==========================================
  // COMPROBAR SERVIDOR
  // ==========================================

  Future<Map<String, dynamic>> checkServer() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return {
          'success': true,
          ...jsonDecode(response.body) as Map<String, dynamic>,
        };
      }

      return {
        'success': false,
        'message': 'El servidor respondió con un error.',
      };
    } catch (error) {
      return {
        'success': false,
        'message': 'No se pudo conectar con Python: $error',
      };
    }
  }

  // ==========================================
  // CONSULTAR DISPOSITIVOS
  // ==========================================

  Future<Map<String, dynamic>> getDevices() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/devices'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return {
          'success': true,
          ...jsonDecode(response.body) as Map<String, dynamic>,
        };
      }

      return {
        'success': false,
        'message': 'No se pudieron consultar los dispositivos.',
      };
    } catch (error) {
      return {
        'success': false,
        'message': 'Error consultando dispositivos: $error',
      };
    }
  }

  // ==========================================
  // CONFIGURAR CÁMARA
  // ==========================================

  Future<Map<String, dynamic>> configureCamera(
    String cameraId,
    String source,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/$cameraId/configure'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return _parseResponse(response);
    } catch (error) {
      return {
        'success': false,
        'message': 'Error configurando $cameraId: $error',
      };
    }
  }

  // ==========================================
  // COMPROBAR CÁMARA
  // ==========================================

  Future<Map<String, dynamic>> checkCamera(
    String cameraId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/$cameraId/check'),
          )
          .timeout(const Duration(seconds: 10));

      return _parseResponse(response);
    } catch (error) {
      return {
        'success': false,
        'available': false,
        'message': 'No se pudo comprobar $cameraId: $error',
      };
    }
  }

  // ==========================================
  // COMPROBAR AMBAS CÁMARAS
  // ==========================================

  Future<Map<String, dynamic>> checkAllCameras() async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/check-all'),
          )
          .timeout(const Duration(seconds: 20));

      return _parseResponse(response);
    } catch (error) {
      return {
        'success': false,
        'message': 'Error comprobando las cámaras: $error',
      };
    }
  }

  // ==========================================
  // INICIAR CÁMARA
  // ==========================================

  Future<Map<String, dynamic>> startCamera(
    String cameraId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/$cameraId/start'),
          )
          .timeout(const Duration(seconds: 10));

      return _parseResponse(response);
    } catch (error) {
      return {
        'success': false,
        'message': 'No se pudo iniciar $cameraId: $error',
      };
    }
  }

  // ==========================================
  // DETENER CÁMARA
  // ==========================================

  Future<Map<String, dynamic>> stopCamera(
    String cameraId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/devices/$cameraId/stop'),
          )
          .timeout(const Duration(seconds: 5));

      return _parseResponse(response);
    } catch (error) {
      return {
        'success': false,
        'message': 'No se pudo detener $cameraId: $error',
      };
    }
  }

  // ==========================================
  // PLACAS MAKI (EMG + CÁMARA)
  // ==========================================

  Future<Map<String, dynamic>> _get(String path, Duration timeout) async {
    try {
      final response =
          await http.get(Uri.parse('$_baseUrl$path')).timeout(timeout);
      return _parseResponse(response);
    } catch (error) {
      return {'success': false, 'message': 'Error de conexión: $error'};
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Duration timeout, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return _parseResponse(response);
    } catch (error) {
      return {'success': false, 'message': 'Error de conexión: $error'};
    }
  }

  Future<Map<String, dynamic>> getPlacas() =>
      _get('/placas', const Duration(seconds: 5));

  Future<Map<String, dynamic>> buscarPlacas() =>
      _post('/placas/buscar', const Duration(seconds: 8));

  Future<Map<String, dynamic>> conectarPlaca(String ip, String? cameraId) =>
      _post('/placas/conectar', const Duration(seconds: 10), {
        'ip': ip,
        'camera_id': cameraId,
      });

  Future<Map<String, dynamic>> desconectarPlaca(String ip) =>
      _post('/placas/$ip/desconectar', const Duration(seconds: 5));

  Future<Map<String, dynamic>> ordenPlaca(String ip, String orden) =>
      _post('/placas/$ip/orden', const Duration(seconds: 8), {
        'orden': orden,
      });

  Future<Map<String, dynamic>> wifiLaptop() =>
      _get('/wifi/laptop', const Duration(seconds: 8));

  Future<Map<String, dynamic>> buscarBluetooth() =>
      _post('/ble/buscar', const Duration(seconds: 15));

  Future<Map<String, dynamic>> configurarWifiBluetooth(
    String address, {
    String? ssid,
    String? clave,
  }) =>
      _post('/ble/configurar', const Duration(seconds: 60), {
        'address': address,
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
        if (clave != null && clave.isNotEmpty) 'clave': clave,
      });

  // ==========================================
  // VISTA PREVIA Y CALIBRACIÓN
  // ==========================================

  Future<Map<String, dynamic>> getPreview() =>
      _get('/devices/preview', const Duration(seconds: 5));

  Future<Map<String, dynamic>> startPreview() =>
      _post('/devices/preview/start', const Duration(seconds: 15), {});

  Future<Map<String, dynamic>> stopPreview() =>
      _post('/devices/preview/stop', const Duration(seconds: 10));

  Future<Map<String, dynamic>> calibracionCanales() =>
      _get('/calibracion/canales', const Duration(seconds: 5));

  Future<Map<String, dynamic>> revisarElectrodos() =>
      _post('/calibracion/revisar', const Duration(seconds: 15));

  Future<Map<String, dynamic>> calibrarReposo() =>
      _post('/calibracion/reposo', const Duration(seconds: 30));

  Future<Map<String, dynamic>> calibrarMvc(String canal) =>
      _post('/calibracion/mvc', const Duration(seconds: 20), {'canal': canal});

  Future<Map<String, dynamic>> progresoEmg(
    List<List<Map<String, dynamic>>> sesiones,
  ) =>
      _post('/progreso/emg', const Duration(seconds: 15), {
        'sesiones': sesiones,
      });

  // ==========================================
  // PROCESAR RESPUESTAS
  // ==========================================

  Map<String, dynamic> _parseResponse(
    http.Response response,
  ) {
    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic>) {
      return {
        ...data,
        'success': data['success'] ?? response.statusCode == 200,
      };
    }

    return {
      'success': false,
      'message': 'Respuesta no válida del servidor.',
    };
  }
}
