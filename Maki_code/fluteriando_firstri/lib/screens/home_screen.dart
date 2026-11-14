
import 'package:flutter/material.dart';
import 'evaluation_screen.dart';
import '../models/patient.dart';
import 'patient_screen.dart';
import 'progress_screen.dart';
import 'prueba_screen.dart';
import 'device_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Índices de navegación
  static const int homeIndex = 0;
  static const int patientsIndex = 1;
  static const int deviceIndex = 2;
  static const int sessionIndex = 3;
  static const int progressIndex = 4;
  static const int settingsIndex = 5;
  static const int pruebaIndex = 6;
  int selectedIndex = homeIndex;

  // Paciente seleccionado para la evaluación
  Patient? selectedPatient;

  // --------------------------------------------------
  // SELECCIONAR PACIENTE
  // --------------------------------------------------

  void selectPatient(Patient patient) {
    setState(() {
      selectedPatient = patient;

      // Permanecer en la pantalla de pacientes
      selectedIndex = patientsIndex;
    });
  }


//abrir progreso del paciente
  void openPatientProgress(Patient patient) {
    setState(() {
      selectedPatient = patient;
      selectedIndex = progressIndex;
    });
  }

  // --------------------------------------------------
  // NAVEGACIÓN
  // --------------------------------------------------

  void navigateTo(int index) {
    // No permitir entrar a sesión o progreso
    // si todavía no se ha seleccionado un paciente.
    if ((index == sessionIndex || index == progressIndex) &&
        selectedPatient == null) {
      return;
    }

    setState(() {
      selectedIndex = index;
    });
  }

// Navegar a Evaluación con el paciente seleccionado
  void openNewSession(Patient patient) {
    setState(() {
      selectedPatient = patient;
      selectedIndex = sessionIndex;
    });
  }

  // --------------------------------------------------
  // CONSTRUIR PANTALLAS
  // --------------------------------------------------

  List<Widget> _buildPages() {
    return [
      _HomePage(
        onNavigate: navigateTo,
        hasSelectedPatient: selectedPatient != null,
      ),

      PatientsScreen(
        onNewSession: selectPatient,
        onViewProgress: openPatientProgress,
      ),

      DeviceScreen(
      ),

      if (selectedPatient != null) ...[
        
        EvaluationScreen(
          patient: selectedPatient,
        ),

        ProgressScreen(
        patient: selectedPatient,
        ),
        _SectionPage(
          title: 'Configuración',
          icon: Icons.settings_outlined,
          description: 'Configura las preferencias del sistema.',
        ),

        PruebaScreen(
          pacienteInicial: selectedPatient,
        ),

      ],
    ];
  }

  // --------------------------------------------------
  // INTERFAZ PRINCIPAL
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();

    return Scaffold(
      body: Row(
        children: [
          // ------------------------------------------
          // MENÚ LATERAL
          // ------------------------------------------

          Container(
            width: 125,
            color: Colors.white,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // LOGO
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 15,
                      bottom: 20,
                    ),

                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/deus.jpeg',
                          width: 42,
                          height: 42,
                          fit: BoxFit.contain,
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'MaKi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF356AE6),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // OPCIONES GENERALES
                  _SidebarItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Inicio',
                    selected: selectedIndex == homeIndex,
                    onTap: () => navigateTo(homeIndex),
                  ),

                  _SidebarItem(
                    icon: Icons.people_outline,
                    selectedIcon: Icons.people,
                    label: 'Pacientes',
                    selected: selectedIndex == patientsIndex,
                    onTap: () => navigateTo(patientsIndex),
                  ),

                  _SidebarItem(
                    icon: Icons.camera_alt_outlined,
                    selectedIcon: Icons.camera_alt,
                    label: 'Dispositivo',
                    selected: selectedIndex == deviceIndex,
                    onTap: () => navigateTo(deviceIndex),
                  ),

                  // --------------------------------------
                  // SEPARADOR
                  // --------------------------------------

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 1,
                      vertical: 12,
                    ),

                    child: Divider(
                      thickness: 1,
                      color: Color(0xFFE8ECF2),
                    ),
                  ),

                  // --------------------------------------
                  // OPCIONES DEL PACIENTE
                  // --------------------------------------

                  if (selectedPatient != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),

                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            color: Color(0xFF356AE6),
                            size: 22,
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${selectedPatient!.nombre}\n'
                            '${selectedPatient!.apellido}',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF202A3C),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    _SidebarItem(
                      icon: Icons.assignment_outlined,
                      selectedIcon: Icons.assignment,
                      label: 'Sesión',
                      selected: selectedIndex == sessionIndex,
                      onTap: () => navigateTo(sessionIndex),
                    ),

                    _SidebarItem(
                      icon: Icons.show_chart,
                      selectedIcon: Icons.insights,
                      label: 'Progreso',
                      selected: selectedIndex == progressIndex,
                      onTap: () => navigateTo(progressIndex),
                    ),

                    _SidebarItem(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.insights,
                      label: 'Ajustes',
                      selected: selectedIndex == settingsIndex,
                      onTap: () => navigateTo(settingsIndex),
                    ),

                    _SidebarItem(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.insights,
                      label: 'Prueba',
                      selected: selectedIndex == pruebaIndex,
                      onTap: () => navigateTo(pruebaIndex),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ------------------------------------------
          // DIVISOR DEL MENÚ Y CONTENIDO
          // ------------------------------------------

          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFFE8ECF2),
          ),

          // ------------------------------------------
          // CONTENIDO DE LAS PANTALLAS
          // ------------------------------------------

          Expanded(
            child: Container(
              color: const Color(0xFFF5F7FB),

              child: IndexedStack(
                index: selectedIndex,
                children: pages,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// ELEMENTO DEL MENÚ LATERAL
// --------------------------------------------------

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),

        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 4,
          ),

          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE5ECFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),

          child: Column(
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 24,
                color: selected
                    ? const Color(0xFF356AE6)
                    : const Color(0xFF7B8495),
              ),

              const SizedBox(height: 5),

              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? const Color(0xFF356AE6)
                      : const Color(0xFF7B8495),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// PANTALLA DE INICIO
// --------------------------------------------------

class _HomePage extends StatelessWidget {
  final Function(int) onNavigate;
  final bool hasSelectedPatient;

  const _HomePage({
    required this.onNavigate,
    required this.hasSelectedPatient,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Panel principal',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF202A3C),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Bienvenido a MaKi, tu sistema de seguimiento '
            'de rehabilitación de manos.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF7B8495),
            ),
          ),

          const SizedBox(height: 32),

          // TARJETA DE BIENVENIDA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),

            decoration: BoxDecoration(
              color: const Color(0xFF356AE6),
              borderRadius: BorderRadius.circular(20),
            ),

            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.back_hand_outlined,
                  color: Colors.white,
                  size: 38,
                ),

                SizedBox(height: 18),

                Text(
                  'Rehabilitación más objetiva',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 8),

                Text(
                  'Registra movimientos y consulta los '
                  'resultados de las evaluaciones.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          const Text(
            'Accesos rápidos',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF202A3C),
            ),
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 16,
            runSpacing: 16,

            children: [
              _QuickAccessCard(
                icon: Icons.people_outline,
                title: 'Pacientes',
                description: 'Gestionar pacientes',
                onTap: () => onNavigate(1),
              ),

              _QuickAccessCard(
                icon: Icons.camera_alt_outlined,
                title: 'Dispositivo',
                description: 'Conectar cámaras y sensores',
                onTap: () => onNavigate(2),
              ),

              if (hasSelectedPatient)
                _QuickAccessCard(
                  icon: Icons.assignment_outlined,
                  title: 'Sesión',
                  description: 'Iniciar una sesión',
                  onTap: () => onNavigate(3),
                ),

              if (hasSelectedPatient)
                _QuickAccessCard(
                  icon: Icons.show_chart,
                  title: 'Progreso',
                  description: 'Consultar resultados',
                  onTap: () => onNavigate(4),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// TARJETAS DE ACCESOS RÁPIDOS
// --------------------------------------------------

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),

      child: Container(
        width: 220,
        padding: const EdgeInsets.all(20),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE8ECF2),
          ),
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 28,
              color: const Color(0xFF356AE6),
            ),

            const SizedBox(height: 14),

            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF202A3C),
              ),
            ),

            const SizedBox(height: 6),

            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7B8495),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// screens
class _SectionPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const _SectionPage({
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: const Color(0xFF356AE6),
            ),

            const SizedBox(height: 20),

            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF202A3C),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF7B8495),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
