
// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../services/database_service.dart';

class PatientsScreen extends StatefulWidget {
  final Function(Patient) onNewSession;
  final Function(Patient) onViewProgress;

  const PatientsScreen({
    super.key,
    required this.onNewSession,
    required this.onViewProgress,
  });

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final List<Patient> patients = [];
  bool _isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  // Cargar pacientes desde SQLite
  Future<void> _loadPatients() async {
    try {
      final records = await DatabaseService.instance.getPatients();

      final loadedPatients = records
          .map((record) => Patient.fromMap(record))
          .toList();

      if (!mounted) return;

      setState(() {
        patients
          ..clear()
          ..addAll(loadedPatients);

        _isLoading = false;
        loadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        loadError = "No se pudieron cargar los pacientes.";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar pacientes: $e'),
        ),
      );
    }
  }

  // Registrar un nuevo paciente
  Future<void> _showAddPatientDialog() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (dialogContext) {
        return const _AddPatientDialog();
      },
    );

    if (!mounted || patient == null) return;

    try {
      final patientId =
          await DatabaseService.instance.insertPatient(
        name: patient.nombre,
        surname: patient.apellido,
        age: patient.edad,
        dni: patient.dni,
        fechaAcv: patient.fechaAcv,
        manoAcv: patient.manoAcv,
      );

      // Generar datos simulados para las pruebas.
      //await DatabaseService.instance.generateDemoProgress(
        //patientId,
      //);

      await _loadPatients();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paciente registrado correctamente'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar el paciente: $e'),
        ),
      );
    }
  }
  // FORMATO DE FECHA
  String _formatDate(DateTime? date) {
    if (date == null) return 'No registrada';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // LISTA DE PACIENTES
  Widget _buildPatientList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 54,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(loadError!),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadPatients,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (patients.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              'No hay pacientes registrados',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: patients.length,
      itemBuilder: (context, index) {
        final patient = patients[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  child: Icon(Icons.person),
                ),

                const SizedBox(width: 20),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${patient.nombre} ${patient.apellido}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text('DNI: ${patient.dni}'),
                      Text('Edad: ${patient.edad} años'),
                      Text(
                        'Fecha del ACV: ${_formatDate(patient.fechaAcv)}',
                      ),
                      Text('Mano afectada: ${patient.manoAcv}'),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                ElevatedButton.icon(
                  onPressed: () {
                    widget.onNewSession(patient);
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Seleccionar paciente'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // INTERFAZ PRINCIPAL
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pacientes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Registro y gestión de pacientes',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),

                ElevatedButton.icon(
                  onPressed: _isLoading || loadError != null
                      ? null
                      : _showAddPatientDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Agregar paciente'),
                ),
              ],
            ),

            const SizedBox(height: 28),

            Expanded(
              child: _buildPatientList(),
            ),
          ],
        ),
      ),
    );
  }
}
// Formulario para agregar pacientes

class _AddPatientDialog extends StatefulWidget {
  const _AddPatientDialog();

  @override
  State<_AddPatientDialog> createState() =>
      _AddPatientDialogState();
}

class _AddPatientDialogState extends State<_AddPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _edadController = TextEditingController();
  final _dniController = TextEditingController();

  DateTime? _fechaAcv;
  String? _manoAcv;

  Future<void> _seleccionarFechaAcv() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Seleccionar fecha del ACV',
    );

    if (fecha != null) {
      setState(() {
        _fechaAcv = fecha;
      });
    }
  }

  void _guardarPaciente() {
    if (!_formKey.currentState!.validate()) return;

    final patient = Patient(
      nombre: _nombreController.text.trim(),
      apellido: _apellidoController.text.trim(),
      edad: int.parse(_edadController.text.trim()),
      dni: _dniController.text.trim().isEmpty
          ? null
          : _dniController.text.trim(),
      fechaAcv: _fechaAcv,
      manoAcv: _manoAcv,
    );

    Navigator.of(context).pop(patient);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _edadController.dispose();
    super.dispose();
    _dniController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar paciente'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el nombre';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _apellidoController,
                decoration: const InputDecoration(
                  labelText: 'Apellido',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el apellido';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _edadController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Edad',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final age = int.tryParse(value ?? '');

                  if (age == null || age <= 0 || age > 120) {
                    return 'Ingresa una edad válida';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 15),

              TextFormField(
                controller: _dniController,
                decoration: const InputDecoration(
                  labelText: 'DNI (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),

              // Fecha del ACV
              InkWell(
                onTap: _seleccionarFechaAcv,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha del ACV (opcional)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _fechaAcv == null
                        ? 'Seleccionar fecha'
                        : '${_fechaAcv!.day.toString().padLeft(2, '0')}/'
                          '${_fechaAcv!.month.toString().padLeft(2, '0')}/'
                          '${_fechaAcv!.year}',
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // Mano afectada
              DropdownButtonFormField<String>(
                value: _manoAcv,
                decoration: const InputDecoration(
                  labelText: 'Mano afectada (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'izquierda',
                    child: Text('Izquierda'),
                  ),
                  DropdownMenuItem(
                    value: 'derecha',
                    child: Text('Derecha'),
                  ),
                  DropdownMenuItem(
                    value: 'ambas',
                    child: Text('Ambas'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _manoAcv = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Salir'),
        ),

        ElevatedButton(
          onPressed: _guardarPaciente,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
