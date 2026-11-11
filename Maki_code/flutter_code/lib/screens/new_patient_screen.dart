
import 'package:flutter/material.dart';
import '../models/patient.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _edadController = TextEditingController();
  final _dniController = TextEditingController();

  DateTime? _fechaAcv;
  String? _manoAcv;

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _edadController.dispose();
    _dniController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Seleccionar fecha del ACV',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (selectedDate != null) {
      setState(() {
        _fechaAcv = selectedDate;
      });
    }
  }

  void _savePatient() {
    if (!_formKey.currentState!.validate()) return;

    if (_manoAcv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la mano afectada'),
        ),
      );
      return;
    }

    final patient = Patient(
      nombre: _nombreController.text.trim(),
      apellido: _apellidoController.text.trim(),
      edad: int.parse(_edadController.text),
      dni: _dniController.text.trim(),
      fechaAcv: _fechaAcv,
      manoAcv: _manoAcv!,
    );

    Navigator.pop(context, patient);
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ENCABEZADO
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Registrar paciente',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Text(
                      'Ingresa los datos del paciente para registrarlo en MaKi.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // DATOS PERSONALES
                  const Text(
                    'Datos personales',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildTextField(
                    label: 'Nombre',
                    controller: _nombreController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa el nombre';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 18),

                  _buildTextField(
                    label: 'Apellido',
                    controller: _apellidoController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa el apellido';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 18),

                  _buildTextField(
                    label: 'Edad',
                    controller: _edadController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final age = int.tryParse(value ?? '');

                      if (age == null || age <= 0 || age > 120) {
                        return 'Ingresa una edad válida';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 18),

                  _buildTextField(
                    label: 'DNI',
                    controller: _dniController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    validator: (value) {
                      if (value == null ||
                          !RegExp(r'^\d{8}$').hasMatch(value.trim())) {
                        return 'El DNI debe tener 8 dígitos';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 30),

                  // DATOS DEL ACV
                  const Text(
                    'Información del ACV',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha del ACV',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_month),
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

                  const SizedBox(height: 18),

                  DropdownButtonFormField<String>(
                    initialValue: _manoAcv,
                    decoration: const InputDecoration(
                      labelText: 'Mano afectada',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Derecha',
                        child: Text('Derecha'),
                      ),
                      DropdownMenuItem(
                        value: 'Izquierda',
                        child: Text('Izquierda'),
                      ),
                      DropdownMenuItem(
                        value: 'Ambas',
                        child: Text('Ambas'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _manoAcv = value;
                      });
                    },
                  ),

                  const SizedBox(height: 36),

                  // BOTONES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),

                      const SizedBox(width: 12),

                      ElevatedButton.icon(
                        onPressed: _savePatient,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar paciente'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF356AE6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
