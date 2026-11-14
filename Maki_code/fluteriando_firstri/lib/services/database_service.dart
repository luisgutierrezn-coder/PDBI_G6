
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:math';
import 'dart:convert';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    // Directorio de almacenamiento de Windows
    final appData = Platform.environment['APPDATA'] ??
        Directory.current.path;

    final directory = Directory(join(appData, 'MaKi'));
    await directory.create(recursive: true);

    final dbPath = join(directory.path, 'maki_database.db');

    _database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE patients (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              surname TEXT NOT NULL,
              age INTEGER NOT NULL,
              registration_date TEXT NOT NULL,
              dni TEXT,
              fecha_acv TEXT,
              mano_acv TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              patient_id INTEGER NOT NULL,
              session_date TEXT NOT NULL,

              max_strength_n REAL,
              baseline_strength_n REAL,
              max_strength_percent REAL,
              pinch_independence_percent REAL,
              wrist_rom_degrees REAL,

              exercise TEXT,
              total_repetitions INTEGER,
              valid_repetitions INTEGER,
              result_json TEXT,
              session_type TEXT NOT NULL DEFAULT 'demo',
              therapy_session_id INTEGER
                REFERENCES therapy_sessions(id)
                ON DELETE CASCADE,

              FOREIGN KEY (patient_id)
                REFERENCES patients(id)
                ON DELETE CASCADE
            )
          ''');

          await _createTherapySessionsTable(db);
          await _createEmgCalibrationsTable(db);

          await db.execute('''
            CREATE TABLE finger_measurements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id INTEGER NOT NULL,
              finger TEXT NOT NULL,
              rom_degrees REAL NOT NULL,
              FOREIGN KEY (session_id)
                REFERENCES sessions(id)
                ON DELETE CASCADE
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN exercise TEXT',
            );

            await db.execute(
              'ALTER TABLE sessions ADD COLUMN total_repetitions INTEGER',
            );

            await db.execute(
              'ALTER TABLE sessions ADD COLUMN valid_repetitions INTEGER',
            );

            await db.execute(
              'ALTER TABLE sessions ADD COLUMN result_json TEXT',
            );

            await db.execute('''
              ALTER TABLE sessions
              ADD COLUMN session_type TEXT NOT NULL DEFAULT 'demo'
            ''');
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE patients ADD COLUMN dni TEXT',
            );

            await db.execute(
              'ALTER TABLE patients ADD COLUMN fecha_acv TEXT',
            );

            await db.execute(
              'ALTER TABLE patients ADD COLUMN mano_acv TEXT',
            );
          }
          if (oldVersion < 4) {
            await _createTherapySessionsTable(db);

            await db.execute('''
              ALTER TABLE sessions
              ADD COLUMN therapy_session_id INTEGER
              REFERENCES therapy_sessions(id) ON DELETE CASCADE
            ''');
          }
          if (oldVersion < 5) {
            await _createEmgCalibrationsTable(db);
          }
        },
      ),
    );

    return _database!;
  }

  Future<void> _createEmgCalibrationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE emg_calibrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        therapy_session_id INTEGER NOT NULL,
        patient_id INTEGER NOT NULL,
        calibration_date TEXT NOT NULL,
        channel TEXT NOT NULL,
        rest_mv REAL,
        threshold_mv REAL,
        mvc_mv REAL,
        mvc_times_rest REAL,
        quality TEXT,
        FOREIGN KEY (therapy_session_id)
          REFERENCES therapy_sessions(id)
          ON DELETE CASCADE,
        FOREIGN KEY (patient_id)
          REFERENCES patients(id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createTherapySessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE therapy_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        session_date TEXT NOT NULL,
        camera_source TEXT,
        planned_exercises TEXT,
        FOREIGN KEY (patient_id)
          REFERENCES patients(id)
          ON DELETE CASCADE
      )
    ''');
  }

  // REGISTRAR PACIENTES
  Future<int> insertPatient({
    required String name,
    required String surname,
    required int age,
    String? dni,
    DateTime? fechaAcv,
    String? manoAcv,
  }) async {
    final db = await database;

    return await db.insert('patients', {
      'name': name,
      'surname': surname,
      'age': age,
      'registration_date': DateTime.now().toIso8601String(),
      'dni': dni,
      'fecha_acv': fechaAcv?.toIso8601String(),
      'mano_acv': manoAcv,
    });
  }

  // OBTENER PACIENTES
  Future<List<Map<String, dynamic>>> getPatients() async {
    final db = await database;

    return await db.query(
      'patients',
      orderBy: 'name ASC',
    );
  }

  // REGISTRAR UNA SESIÓN

  Future<int> insertSession({
    required int patientId,
    required double maxStrengthN,
    required double baselineStrengthN,
    required double pinchIndependence,
    required double wristRom,
    DateTime? sessionDate,
  }) async {
    final db = await database;

    final strengthPercent = baselineStrengthN > 0
        ? (maxStrengthN / baselineStrengthN) * 100
        : 0.0;

    return await db.insert('sessions', {
      'patient_id': patientId,
      'session_date': (sessionDate ?? DateTime.now())
          .toIso8601String(),
      'max_strength_n': maxStrengthN,
      'baseline_strength_n': baselineStrengthN,
      'max_strength_percent': strengthPercent,
      'pinch_independence_percent': pinchIndependence,
      'wrist_rom_degrees': wristRom,
    });
  }

  // REGISTRAR UNA SESIÓN DE TERAPIA (CONJUNTO DE EJERCICIOS)

  Future<int> insertTherapySession({
    required int patientId,
    required List<String> exercises,
    String? cameraSource,
    DateTime? sessionDate,
  }) async {
    final db = await database;

    return await db.insert('therapy_sessions', {
      'patient_id': patientId,
      'session_date': (sessionDate ?? DateTime.now()).toIso8601String(),
      'camera_source': cameraSource,
      'planned_exercises': jsonEncode(exercises),
    });
  }

  // CALIBRACIÓN DEL EMG (una fila por canal y sesión)

  Future<void> insertEmgCalibration({
    required int therapySessionId,
    required int patientId,
    required Map<String, Map<String, dynamic>> channels,
  }) async {
    final db = await database;
    final date = DateTime.now().toIso8601String();

    double? number(dynamic v) => v is num ? v.toDouble() : null;

    await db.transaction((txn) async {
      for (final entry in channels.entries) {
        final c = entry.value;
        await txn.insert('emg_calibrations', {
          'therapy_session_id': therapySessionId,
          'patient_id': patientId,
          'calibration_date': date,
          'channel': entry.key,
          'rest_mv': number(c['reposo_mv']),
          'threshold_mv': number(c['umbral_mv']),
          'mvc_mv': number(c['mvc_mv']),
          'mvc_times_rest': number(c['mvc_veces_reposo']),
          'quality': c['calidad']?.toString(),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getEmgCalibrations(int patientId) async {
    final db = await database;

    return await db.query(
      'emg_calibrations',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'calibration_date ASC',
    );
  }

  // Última calibración de cada canal (para comparar con la de hoy)
  Future<Map<String, Map<String, dynamic>>> getLastEmgCalibration(
    int patientId,
  ) async {
    final rows = await getEmgCalibrations(patientId);
    return {
      for (final row in rows) row['channel'] as String: row,
    };
  }

  Future<List<Map<String, dynamic>>> getTherapySessions(
    int patientId,
  ) async {
    final db = await database;

    return await db.query(
      'therapy_sessions',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'session_date ASC',
    );
  }

  // REGISTRAR UNA SESIÓN REAL DE REHABILITACIÓN

  Future<int> insertExerciseSession({
    required int patientId,
    required Map<String, dynamic> result,
    int? therapySessionId,
  }) async {
    final db = await database;

    final summaryRaw = result['summary'];

    final summary = summaryRaw is Map
        ? Map<String, dynamic>.from(summaryRaw)
        : <String, dynamic>{};

    final validRepetitions =
        summary['valid_repetitions'] ?? 0;

    return await db.insert('sessions', {
      'patient_id': patientId,
      'session_date': DateTime.now().toIso8601String(),
      'exercise': result['exercise'],
      'total_repetitions': result['total_repetitions'],
      'valid_repetitions': validRepetitions,
      'result_json': jsonEncode(result),
      'session_type': 'real',
      'therapy_session_id': therapySessionId,
    });
  }

  Future<List<Map<String, dynamic>>> getRealSessions(
    int patientId,
  ) async {
    final db = await database;

    return await db.query(
      'sessions',
      where: 'patient_id = ? AND session_type = ?',
      whereArgs: [patientId, 'real'],
      orderBy: 'session_date ASC',
    );
  }

  // REGISTRAR MEDICIONES DE LOS DEDOS
  Future<void> insertFingerMeasurements({
    required int sessionId,
    required Map<String, double> measurements,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      for (final entry in measurements.entries) {
        await txn.insert('finger_measurements', {
          'session_id': sessionId,
          'finger': entry.key,
          'rom_degrees': entry.value,
        });
      }
    });
  }

  // OBTENER SESIONES DE UN PACIENTE
  Future<List<Map<String, dynamic>>> getSessions(int patientId) async {
    final db = await database;

    return await db.query(
      'sessions',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'session_date ASC',
    );
  }

  // OBTENER MEDICIONES DE LOS DEDOS
  Future<List<Map<String, dynamic>>> getFingerMeasurements(
    int sessionId,
  ) async {
    final db = await database;

    return await db.query(
      'finger_measurements',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // CERRAR BASE DE DATOS
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
  //Generacion de datos prueba

  Future<void> generateDemoProgress(int patientId) async {
    final random = Random();

    const baselineStrength = 20.0;

    // Generamos cinco sesiones de prueba.
    for (int i = 0; i < 5; i++) {
      // Valores que muestran una tendencia de progreso.
      final strengthPercent =
          (40 + i * 10 + random.nextInt(9) - 4).toDouble();

      final pinchIndependence =
          (35 + i * 11 + random.nextInt(9) - 4).toDouble();

      final wristRom =
          (20 + i * 9 + random.nextInt(7) - 3).toDouble();

      final maxStrength =
          baselineStrength * strengthPercent / 100;

      // Fecha de cada sesión: una semana de diferencia.
      final sessionDate = DateTime.now().subtract(
        Duration(days: (4 - i) * 7),
      );

      // Guardamos la sesión y obtenemos su ID.
      final sessionId = await insertSession(
        patientId: patientId,
        maxStrengthN: maxStrength,
        baselineStrengthN: baselineStrength,
        pinchIndependence: pinchIndependence,
        wristRom: wristRom,
        sessionDate: sessionDate,
      );

      // Mediciones simuladas para los cinco dedos.
      final fingerMeasurements = {
        'Pulgar': (25 + i * 10 + random.nextInt(9) - 4).toDouble(),
        'Índice': (30 + i * 9 + random.nextInt(9) - 4).toDouble(),
        'Medio': (35 + i * 8 + random.nextInt(9) - 4).toDouble(),
        'Anular': (28 + i * 9 + random.nextInt(9) - 4).toDouble(),
        'Meñique': (22 + i * 8 + random.nextInt(9) - 4).toDouble(),
      };

      await insertFingerMeasurements(
        sessionId: sessionId,
        measurements: fingerMeasurements,
      );
    }
  }

}

