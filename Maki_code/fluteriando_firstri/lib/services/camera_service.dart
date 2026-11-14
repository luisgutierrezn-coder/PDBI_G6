  import 'package:http/http.dart' as http;

class CameraService {
  // Reemplazar por las IP reales de los ESP32.
  final String camera1IP = '10.202.78.136';
  final String camera2IP = '10.202.78.24';

  Future<bool> checkConnection(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip/status'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> startCamera(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip/start'))
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 &&
          (response.body == 'SESSION_STARTED' ||
           response.body == 'SESSION_ALREADY_ACTIVE');
    } catch (e) {
      return false;
    }
  }

  Future<bool> stopCamera(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip/stop'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}