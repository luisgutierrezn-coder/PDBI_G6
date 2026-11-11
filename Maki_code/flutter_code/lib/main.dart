
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MakiApp());
}

class MakiApp extends StatelessWidget {
  const MakiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaKi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF356AE6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
