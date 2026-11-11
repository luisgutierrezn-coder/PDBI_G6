class Patient {
  final String nombre;
  final String apellido;
  final int edad;
  final String dni;
  final DateTime? fechaAcv;
  final String manoAcv;

  Patient({
    required this.nombre,
    required this.apellido,
    required this.edad,
    required this.dni,
    this.fechaAcv,
    required this.manoAcv,
  });
}