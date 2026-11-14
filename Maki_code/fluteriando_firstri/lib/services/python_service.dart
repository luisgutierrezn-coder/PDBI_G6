
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class PythonService {
  late final WebSocketChannel _channel;
  late final Stream<Map<String, dynamic>> _broadcastStream;

  PythonService()
      : _channel = WebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:8000/ws'),
        ) {
    _broadcastStream = _channel.stream
        .map((message) {
          final decoded = jsonDecode(message as String);

          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }

          return <String, dynamic>{};
        })
        .asBroadcastStream();
  }

  // Datos recibidos desde Python
  Stream<Map<String, dynamic>> get messages => _broadcastStream;

  Stream<Map<String, dynamic>> get angles => _broadcastStream;

  // Envío de comandos exclusivamente para las cámaras
  void _sendCommand(Map<String, dynamic> command) {
    _channel.sink.add(jsonEncode(command));
  }

  // Cámaras
  void startCameras() {
    _sendCommand({'command': 'start_cameras'});
  }

  void stopCameras() {
    _sendCommand({'command': 'stop_cameras'});
  }

  void showCamera1() {
    _sendCommand({'command': 'show_camera_1'});
  }

  void showCamera2() {
    _sendCommand({'command': 'show_camera_2'});
  }

  void showBothCameras() {
    _sendCommand({'command': 'show_both'});
  }

  void hideCameras() {
    _sendCommand({'command': 'hide_cameras'});
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}
