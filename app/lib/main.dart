import 'package:flutter/material.dart';

import 'screens/setup_screen.dart';

void main() {
  runApp(const DartApp());
}

class DartApp extends StatelessWidget {
  const DartApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1D9E75);
    return MaterialApp(
      title: 'Dartzähler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const SetupScreen(),
    );
  }
}
