import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/x01_game.dart';
import 'camera_screen.dart';
import 'game_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final List<TextEditingController> _names = [
    TextEditingController(text: 'Spieler 1'),
    TextEditingController(text: 'Spieler 2'),
  ];
  int _startScore = 501;
  bool _doubleOut = true;
  InputMode _inputMode = InputMode.perDart;

  static const _inputModeKey = 'input_mode';

  @override
  void initState() {
    super.initState();
    _loadInputMode();
  }

  /// Die zuletzt gewählte Eingabeart wieder vorauswählen.
  Future<void> _loadInputMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = InputMode.values.asNameMap()[prefs.getString(_inputModeKey)];
    if (saved != null && mounted) setState(() => _inputMode = saved);
  }

  Future<void> _setInputMode(InputMode mode) async {
    setState(() => _inputMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inputModeKey, mode.name);
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPlayer() {
    setState(() => _names.add(TextEditingController(text: 'Spieler ${_names.length + 1}')));
  }

  void _removePlayer(int index) {
    setState(() => _names.removeAt(index).dispose());
  }

  void _start() {
    final players = [
      for (var i = 0; i < _names.length; i++)
        _names[i].text.trim().isEmpty ? 'Spieler ${i + 1}' : _names[i].text.trim(),
    ];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(
        createGame: () => X01Game(players: players, startScore: _startScore, doubleOut: _doubleOut),
        inputMode: _inputMode,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neues Spiel'),
        actions: [
          IconButton(
            tooltip: 'Kamera einrichten',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CameraScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Spieler', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < _names.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _names[i],
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: const Icon(Icons.person_outline),
                              labelText: 'Name ${i + 1}',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Spieler entfernen',
                          onPressed: _names.length > 1 ? () => _removePlayer(i) : null,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _names.length < 8 ? _addPlayer : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Spieler hinzufügen'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Spielmodus', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 301, label: Text('301')),
                    ButtonSegment(value: 501, label: Text('501')),
                    ButtonSegment(value: 701, label: Text('701')),
                  ],
                  selected: {_startScore},
                  onSelectionChanged: (s) => setState(() => _startScore = s.first),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Double Out'),
                  subtitle: const Text('Zum Beenden muss ein Doppel getroffen werden'),
                  value: _doubleOut,
                  onChanged: (v) => setState(() => _doubleOut = v),
                ),
                const SizedBox(height: 16),
                Text('Eingabe', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<InputMode>(
                  segments: const [
                    ButtonSegment(
                      value: InputMode.perDart,
                      icon: Icon(Icons.apps),
                      label: Text('Einzelne Darts'),
                    ),
                    ButtonSegment(
                      value: InputMode.turnTotal,
                      icon: Icon(Icons.pin_outlined),
                      label: Text('Gesamtpunktzahl'),
                    ),
                  ],
                  selected: {_inputMode},
                  onSelectionChanged: (s) => _setInputMode(s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _inputMode == InputMode.perDart
                      ? 'Jeden Dart einzeln eintragen, z. B. T20 · T20 · 5 – oder per Kamera.'
                      : 'Nur die Summe der Aufnahme eintragen, z. B. 125.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Spiel starten'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
