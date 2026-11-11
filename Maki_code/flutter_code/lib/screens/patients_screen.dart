
import 'package:flutter/material.dart';

import '../models/patient.dart';
import '../services/patient_storage.dart';
import 'new_patient_screen.dart';

class PatientsScreen extends StatefulWidget {
  final Function(Patient) onNewSession;

  const PatientsScreen({
    super.key,
    required this.onNewSession,
  });

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final PatientStorage _storage = PatientStorage();

  List<Patient> patients = [];

  bool isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  // CARGAR PACIENTES
  Future<void> _loadPatients() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final loadedPatients = await _storage.loadPatients();

      if (!mounted) return;

      setState(() {
        patients = loadedPatients;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = 'No se pudieron cargar los pacientes.';
      });

      debugPrint('Error cargando pacientes: $e');
    }
  }

  // AGREGAR PACIENTE
  Future<void> _openAddPatientScreen() async {
    final newPatient = await Navigator.push<Patient>(
      context,
      MaterialPageRoute(
        builder: (context) => const AddPatientScreen(),
      ),
    );

    if (newPatient == null || !mounted) return;

    final updatedPatients = [...patients, newPatient];

    try {
      await _storage.savePatients(updatedPatients);

      if (!mounted) return;

      setState(() {
        patients = updatedPatients;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paciente registrado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el paciente.'),
        ),
      );

      debugPrint('Error guardando paciente: $e');
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
    if (isLoading) {
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
                  onPressed: isLoading || loadError != null
                      ? null
                      : _openAddPatientScreen,
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
