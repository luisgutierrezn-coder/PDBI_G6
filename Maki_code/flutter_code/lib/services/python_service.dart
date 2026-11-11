
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class PythonService {
  late final WebSocketChannel _channel;

  PythonService() {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:8000/ws'),
    );
  }

  // Recibir los datos enviados por Python
  Stream<Map<String, dynamic>> get angles {
    return _channel.stream.map((message) {
      return Map<String, dynamic>.from(
        jsonDecode(message as String) as Map,
      );
    });
  }

  // Enviar comandos a Python
  void _sendCommand(Map<String, dynamic> command) {
    _channel.sink.add(jsonEncode(command));
  }

  // Iniciar un ejercicio
  void startExercise(String exerciseName) {
    _sendCommand({
      'command': 'start_exercise',
      'exercise': exerciseName,
    });
  }

  // Pasar a la siguiente tarea
  void nextTask() {
    _sendCommand({
      'command': 'next_task',
    });
  }

  // Finalizar el ejercicio
  void finishExercise() {
    _sendCommand({
      'command': 'finish_exercise',
    });
  }

  // Mostrar solamente la primera cámara
  void showCamera1() {
    _sendCommand({'command': 'show_camera_1'});
  }

  // Mostrar solamente la segunda cámara
  void showCamera2() {
    _sendCommand({'command': 'show_camera_2'});
  }

  // Mostrar ambas cámaras
  void showBothCameras() {
    _sendCommand({'command': 'show_both'});
  }

  // Ocultar ambas cámaras
  void hideCameras() {
    _sendCommand({'command': 'hide_cameras'});
  }

  // Mandar fases 
  void sendPhases(String exerciseName) {
    _sendCommand({
      'command': 'send_phases',
      'exercise': exerciseName,
      });
  }

  // Cerrar conexión
  Future<void> close() async {
    await _channel.sink.close();
  }
}
