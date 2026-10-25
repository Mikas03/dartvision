import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../models/bot.dart';
import '../models/match.dart';
import '../models/x01_game.dart';
import '../services/speech.dart';
import 'camera_screen.dart';
import 'game_screen.dart';

/// Neues Spiel einrichten: Modus, Optionen, Legs, Spieler (Profile, Gäste, Bots).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  MatchSettings _settings = const MatchSettings();
  List<MatchPlayer> _players = const [MatchPlayer(name: 'Spieler 1'), MatchPlayer(name: 'Spieler 2')];
  InputMode _inputMode = InputMode.perDart;
  List<PlayerProfile> _profiles = [];

  static const _inputModeKey = 'input_mode';
  static const _lastSetupKey = 'last_setup';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Letzte Einstellungen und Spieler wieder vorauswählen.
  Future<void> _load() async {
    final store = await LocalStore.instance();
    Speech.enabled = store.speechEnabled;
    final profiles = store.profiles;
    final mode = InputMode.values.asNameMap()[store.getString(_inputModeKey)];
    MatchSettings? settings;
    List<MatchPlayer>? players;
    final raw = store.getString(_lastSetupKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        settings = MatchSettings.fromJson(json['settings'] as Map<String, dynamic>);
        players = [
          for (final p in (json['players'] as List).cast<Map<String, dynamic>>()) MatchPlayer.fromJson(p),
        ].where((p) => p.profileId == null || profiles.any((pr) => pr.id == p.profileId)).toList();
      } catch (_) {
        // veraltete Daten – Standard verwenden
      }
    }
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      if (mode != null) _inputMode = mode;
      if (settings != null) _settings = settings;
      if (players != null && players.isNotEmpty) _players = _withCurrentNames(players);
    });
  }

  /// Profilnamen können sich geändert haben.
  List<MatchPlayer> _withCurrentNames(List<MatchPlayer> players) => [
        for (final p in players)
          if (p.profileId != null)
            MatchPlayer(name: _profiles.firstWhere((pr) => pr.id == p.profileId).name, profileId: p.profileId)
          else
            p,
      ];

  Future<void> _setInputMode(InputMode mode) async {
    setState(() => _inputMode = mode);
    await (await LocalStore.instance()).setString(_inputModeKey, mode.name);
  }

  void _update(MatchSettings settings) => setState(() => _settings = settings);

  Future<void> _start() async {
    final store = await LocalStore.instance();
    await store.setString(
      _lastSetupKey,
      jsonEncode({'settings': _settings.toJson(), 'players': [for (final p in _players) p.toJson()]}),
    );
    if (Speech.enabled) Speech.unlock(); // Safari erlaubt Sprachausgabe erst nach einem Tipp
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(match: Match(settings: _settings, players: _players), inputMode: _inputMode),
    ));
  }

  // ---------------------------------------------------------------- Spieler

  Future<void> _addPlayer() async {
    final store = await LocalStore.instance();
    if (!mounted) return;
    final used = {for (final p in _players) ?p.profileId};
    final result = await showModalBottomSheet<MatchPlayer>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _AddPlayerSheet(
        profiles: [for (final p in store.profiles) if (!used.contains(p.id)) p],
        guestName: 'Spieler ${_players.length + 1}',
      ),
    );
    if (result == null) return;
    setState(() {
      _profiles = store.profiles;
      _players = [..._players, result];
    });
  }

  void _addBot() => setState(() => _players = [..._players, MatchPlayer.bot(5)]);

  void _setBotLevel(int index, int level) => setState(() {
        _players = [..._players]..[index] = MatchPlayer.bot(level);
      });

  void _removePlayer(int index) => setState(() => _players = [..._players]..removeAt(index));

  void _movePlayer(int oldIndex, int newIndex) => setState(() {
        final list = [..._players];
        list.insert(newIndex, list.removeAt(oldIndex));
        _players = list;
      });

  // ---------------------------------------------------------------- Oberfläche

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = _settings.mode;
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
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _Section('Spielmodus'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in GameMode.values)
                      ChoiceChip(
                        label: Text(m.title),
                        avatar: m.isTraining ? const Icon(Icons.fitness_center, size: 16) : null,
                        selected: m == mode,
                        onSelected: (_) => _update(_settings.copyWith(mode: m)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(mode.description,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                ..._modeOptions(),
                if (!mode.isTraining) ...[
                  const SizedBox(height: 12),
                  const _Section('Legs'),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 Leg')),
                      ButtonSegment(value: 3, label: Text('Bo3')),
                      ButtonSegment(value: 5, label: Text('Bo5')),
                      ButtonSegment(value: 7, label: Text('Bo7')),
                    ],
                    selected: {_settings.bestOf},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _update(_settings.copyWith(bestOf: s.first)),
                  ),
                ],
                const SizedBox(height: 20),
                const _Section('Spieler'),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _movePlayer,
                  children: [
                    for (var i = 0; i < _players.length; i++)
                      _PlayerTile(
                        key: ValueKey('player-$i-${_players[i].name}-${_players[i].botLevel}'),
                        index: i,
                        player: _players[i],
                        canRemove: _players.length > 1,
                        onRemove: () => _removePlayer(i),
                        onBotLevel: (level) => _setBotLevel(i, level),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _players.length < 8 ? _addPlayer : null,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Spieler hinzufügen'),
                    ),
                    TextButton.icon(
                      onPressed: _players.length < 8 ? _addBot : null,
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Bot hinzufügen'),
                    ),
                  ],
                ),
                if (mode.supportsTotalInput) ...[
                  const SizedBox(height: 16),
                  const _Section('Eingabe'),
                  SegmentedButton<InputMode>(
                    segments: const [
                      ButtonSegment(value: InputMode.perDart, icon: Icon(Icons.apps), label: Text('Einzelne Darts')),
                      ButtonSegment(
                          value: InputMode.turnTotal, icon: Icon(Icons.pin_outlined), label: Text('Gesamtpunktzahl')),
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
                ],
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

  List<Widget> _modeOptions() {
    final s = _settings;
    switch (s.mode) {
      case GameMode.x01:
        return [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 301, label: Text('301')),
              ButtonSegment(value: 501, label: Text('501')),
              ButtonSegment(value: 701, label: Text('701')),
            ],
            selected: {s.startScore},
            onSelectionChanged: (v) => _update(s.copyWith(startScore: v.first)),
          ),
          const SizedBox(height: 12),
          SegmentedButton<OutRule>(
            segments: const [
              ButtonSegment(value: OutRule.straight, label: Text('Single Out')),
              ButtonSegment(value: OutRule.double, label: Text('Double Out')),
              ButtonSegment(value: OutRule.master, label: Text('Master Out')),
            ],
            selected: {s.outRule},
            showSelectedIcon: false,
            onSelectionChanged: (v) => _update(s.copyWith(outRule: v.first)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Double In'),
            subtitle: const Text('Punkte zählen erst ab dem ersten Doppel'),
            value: s.doubleIn,
            onChanged: (v) => _update(s.copyWith(doubleIn: v)),
          ),
        ];
      case GameMode.cricket:
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cut-Throat'),
            subtitle: const Text('Punkte gehen an die Gegner – wenig Punkte gewinnt'),
            value: s.cutThroat,
            onChanged: (v) => _update(s.copyWith(cutThroat: v)),
          ),
        ];
      case GameMode.aroundTheClock:
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Double/Triple zählen mehrfach'),
            subtitle: const Text('Double bringt 2 Felder weiter, Triple 3'),
            value: s.multiplesCount,
            onChanged: (v) => _update(s.copyWith(multiplesCount: v)),
          ),
        ];
      case GameMode.checkoutTraining:
        return [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5, label: Text('5 Runden')),
              ButtonSegment(value: 10, label: Text('10 Runden')),
              ButtonSegment(value: 20, label: Text('20 Runden')),
            ],
            selected: {s.trainingRounds},
            onSelectionChanged: (v) => _update(s.copyWith(trainingRounds: v.first)),
          ),
        ];
      case GameMode.shanghai:
      case GameMode.bobs27:
        return const [];
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    super.key,
    required this.index,
    required this.player,
    required this.canRemove,
    required this.onRemove,
    required this.onBotLevel,
  });

  final int index;
  final MatchPlayer player;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<int> onBotLevel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = player.botLevel;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator)),
                ),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: player.isBot ? scheme.tertiaryContainer : scheme.primaryContainer,
                  child: Icon(
                    player.isBot
                        ? Icons.smart_toy_outlined
                        : (player.profileId != null ? Icons.person : Icons.person_outline),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(player.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        level != null
                            ? DartBot.describe(level)
                            : player.profileId != null
                                ? 'Profil'
                                : 'Gast',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Entfernen', onPressed: canRemove ? onRemove : null, icon: const Icon(Icons.close)),
              ],
            ),
            if (level != null)
              Slider(
                value: level.toDouble(),
                min: 1,
                max: DartBot.maxLevel.toDouble(),
                divisions: DartBot.maxLevel - 1,
                label: 'Stufe $level',
                onChanged: (v) => onBotLevel(v.round()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Auswahl beim Hinzufügen eines Spielers: vorhandenes Profil, neues Profil oder Gast.
class _AddPlayerSheet extends StatefulWidget {
  const _AddPlayerSheet({required this.profiles, required this.guestName});

  final List<PlayerProfile> profiles;
  final String guestName;

  @override
  State<_AddPlayerSheet> createState() => _AddPlayerSheetState();
}

class _AddPlayerSheetState extends State<_AddPlayerSheet> {
  final _name = TextEditingController();
  bool _saveAsProfile = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim().isEmpty ? widget.guestName : _name.text.trim();
    if (_saveAsProfile) {
      final profile = await (await LocalStore.instance()).addProfile(name);
      if (mounted) Navigator.pop(context, MatchPlayer(name: profile.name, profileId: profile.id));
    } else {
      Navigator.pop(context, MatchPlayer(name: name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.profiles.isNotEmpty) ...[
              Text('Profil wählen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in widget.profiles)
                    ActionChip(
                      avatar: const Icon(Icons.person, size: 18),
                      label: Text(p.name),
                      onPressed: () => Navigator.pop(context, MatchPlayer(name: p.name, profileId: p.id)),
                    ),
                ],
              ),
              const Divider(height: 32),
            ],
            Text('Neuer Spieler', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: widget.profiles.isEmpty,
              decoration: InputDecoration(border: const OutlineInputBorder(), hintText: widget.guestName),
              onSubmitted: (_) => _submit(),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _saveAsProfile,
              onChanged: (v) => setState(() => _saveAsProfile = v ?? true),
              title: const Text('Als Profil speichern'),
              subtitle: const Text('Für Statistiken über mehrere Spiele'),
            ),
            FilledButton(onPressed: _submit, child: const Text('Hinzufügen')),
          ],
        ),
      ),
    );
  }
}
