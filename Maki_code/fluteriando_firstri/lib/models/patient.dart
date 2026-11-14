class Patient {
  final int? id;
  final String nombre;
  final String apellido;
  final int edad;

  // Datos clínicos incorporados del otro módulo.
  final String? dni;
  final DateTime? fechaAcv;
  final String? manoAcv;

  Patient({
    this.id,
    required this.nombre,
    required this.apellido,
    required this.edad,
    this.dni,
    this.fechaAcv,
    this.manoAcv,
  });

  // Convertir un registro de SQLite en un objeto Patient.
  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'] as int?,
      nombre: map['name'] as String,
      apellido: map['surname'] as String,
      edad: map['age'] as int,
      dni: map['dni'] as String?,
      fechaAcv: map['fecha_acv'] != null
          ? DateTime.tryParse(map['fecha_acv'] as String)
          : null,
      manoAcv: map['mano_acv'] as String?,
    );
  }
}