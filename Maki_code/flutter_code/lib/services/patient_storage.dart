
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import '../models/patient.dart';

class PatientStorage {
  // Ubicación del archivo CSV
  Future<File> get _file async {
    final directory = await getApplicationSupportDirectory();

    return File('${directory.path}/patients.csv');
  }

  // --------------------------------------------------
  // CARGAR PACIENTES
  // --------------------------------------------------

  Future<List<Patient>> loadPatients() async {
    final file = await _file;

    if (!await file.exists()) {
      return [];
    }

    final content = await file.readAsString();

    if (content.trim().isEmpty) {
      return [];
    }

    // CSV versión 8
    final rows = csv.decode(content);

    // Omitir encabezados
    return rows.skip(1).map((row) {
      return Patient(
        nombre: row[1].toString(),
        apellido: row[2].toString(),
        edad: int.parse(row[3].toString()),
        dni: row[4].toString(),
        fechaAcv: row[5].toString().isEmpty
            ? null
            : DateTime.parse(row[5].toString()),
        manoAcv: row[6].toString(),
      );
    }).toList();
  }

  // --------------------------------------------------
  // GUARDAR PACIENTES
  // --------------------------------------------------

  Future<void> savePatients(List<Patient> patients) async {
    final file = await _file;

    final rows = <List<dynamic>>[
      [
        'id',
        'nombre',
        'apellido',
        'edad',
        'dni',
        'fecha_acv',
        'mano_acv',
      ],
    ];

    for (int i = 0; i < patients.length; i++) {
      final patient = patients[i];

      rows.add([
        i + 1,
        patient.nombre,
        patient.apellido,
        patient.edad,
        patient.dni,
        patient.fechaAcv?.toIso8601String() ?? '',
        patient.manoAcv,
      ]);
    }

    // CSV versión 8
    final csvContent = csv.encode(rows);

    await file.writeAsString(
      csvContent,
      flush: true,
    );
  }
}
