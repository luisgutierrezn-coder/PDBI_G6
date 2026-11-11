
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
