import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/profiles_screen.dart';
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
      home: const HomeScreen(),
    );
  }
}

/// Startseite mit drei Bereichen: Spielen, Historie, Spieler.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _historyKey = GlobalKey<HistoryScreenState>();
  final _profilesKey = GlobalKey<ProfilesScreenState>();

  void _select(int tab) {
    setState(() => _tab = tab);
    // Nach einem Spiel sollen Historie und Statistik aktuell sein
    if (tab == 1) _historyKey.currentState?.reload();
    if (tab == 2) _profilesKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const SetupScreen(),
          HistoryScreen(key: _historyKey),
          ProfilesScreen(key: _profilesKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), label: 'Spielen'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historie'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Spieler'),
        ],
      ),
    );
  }
}
