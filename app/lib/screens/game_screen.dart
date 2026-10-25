import 'dart:async';

import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../models/bot.dart';
import '../models/checkout.dart';
import '../models/hit.dart';
import '../models/match.dart';
import '../models/x01_game.dart';
import '../services/speech.dart';
import '../vision/calibration.dart';
import '../vision/live_detection.dart';
import '../widgets/board_overlay.dart';
import '../widgets/input_pad.dart';
import '../widgets/live_preview.dart';
import '../widgets/score_pad.dart';
import '../widgets/scoreboard.dart';
import 'camera_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.match, this.inputMode = InputMode.perDart});

  final Match match;

  /// Eingabeart zu Beginn (Gesamtpunktzahl nur bei X01); lässt sich im Spiel umschalten.
  final InputMode inputMode;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late Match _match = widget.match;
  late Map<int, DartBot> _bots = _match.createBots();
  late InputMode _inputMode = _match.settings.mode.supportsTotalInput ? widget.inputMode : InputMode.perDart;
  String? _message;
  Timer? _botTimer;

  /// Läuft, solange die Kamera die Darts zählt.
  LiveDetection? _live;

  DartGame get _game => _match.leg;
  X01Game? get _x01 => _match.leg is X01Game ? _match.leg as X01Game : null;

  /// Ob gerade ein Bot an der Reihe ist (dann sind die Eingaben gesperrt).
  bool get _botTurn => !_game.isOver && _match.players[_game.currentPlayer].isBot;

  String _name(int player) => _match.players[player].name;

  @override
  void initState() {
    super.initState();
    _scheduleBot();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _live?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Spielzüge

  void _onHit(Hit hit, {bool fromBot = false}) {
    if (_game.isOver || (_botTurn && !fromBot)) return;
    final player = _game.currentPlayer;
    final turn = _game.currentTurn;
    _handleResult(_game.throwDart(hit), player, turn);
  }

  /// Gemeinsame Auswertung nach jedem Wurf/jeder Eingabe: Meldung, Ansage, Leg-Ende, Bot.
  void _handleResult(ThrowResult result, int player, Turn turn) {
    final label = _game.turnLabel(turn);
    setState(() {
      _message = switch (result) {
        ThrowResult.bust => 'Bust!',
        ThrowResult.win || ThrowResult.ok => null,
        ThrowResult.turnOver when _x01 != null && _x01!.turnPoints(turn) == 180 => 'Hundertachtzig!',
        ThrowResult.turnOver => '${_name(player)}: $label',
      };
    });
    if (result == ThrowResult.bust || result == ThrowResult.turnOver) _announceTurn(turn);
    if (result == ThrowResult.win) {
      _onLegWon(_game.winner!);
    } else {
      _scheduleBot();
    }
  }

  void _announceTurn(Turn turn) {
    final x01 = _x01;
    if (x01 == null) {
      Speech.say(_game.turnLabel(turn));
      return;
    }
    final points = x01.turnPoints(turn);
    var text = turn.bust ? 'Bust' : (points == 180 ? 'Hundertachtzig!' : '$points');
    final next = x01.currentPlayer;
    final rest = x01.remaining(next);
    if (!x01.isOver && suggestCheckout(rest, doubleOut: x01.doubleOut) != null) {
      text += '. ${_name(next)}, du brauchst $rest';
    }
    Speech.say(text);
  }

  /// Eingabe der Gesamtpunktzahl (X01). Liefert eine Fehlermeldung für das Zahlenfeld oder null.
  Future<String?> _onTotal(int score) async {
    final x01 = _x01;
    if (x01 == null || x01.isOver || _botTurn) return null;
    final player = x01.currentPlayer;
    var darts = dartsPerTurn;
    if (score == x01.remaining(player) && score > 0) {
      // Checkout: mit wie vielen Darts? (für den Average) – nur mögliche Anzahlen anbieten
      final options = [
        for (var n = 1; n <= dartsPerTurn; n++)
          if (suggestCheckout(score, darts: n, doubleOut: x01.doubleOut) != null) n,
      ];
      if (options.isEmpty) return '$score lässt sich nicht auschecken';
      if (options.length == 1) {
        darts = options.single;
      } else {
        final chosen = await _askCheckoutDarts(score, options);
        if (chosen == null || !mounted) return null;
        darts = chosen;
      }
    }

    final turn = x01.currentTurn;
    final ThrowResult result;
    try {
      result = x01.enterTurnTotal(score, darts: darts);
    } on ArgumentError catch (e) {
      return e.message as String;
    }
    _handleResult(result, player, turn);
    return null;
  }

  Future<int?> _askCheckoutDarts(int score, List<int> options) {
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Checkout $score'),
        content: const Text('Mit wie vielen Darts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          for (final n in options) FilledButton.tonal(onPressed: () => Navigator.pop(context, n), child: Text('$n')),
        ],
      ),
    );
  }

  void _toggleInputMode() => setState(() {
        _inputMode = _inputMode == InputMode.perDart ? InputMode.turnTotal : InputMode.perDart;
      });

  /// Rückgängig – Bot-Würfe werden mit zurückgenommen, bis wieder ein Mensch dran ist.
  void _undo() {
    _botTimer?.cancel();
    setState(() {
      _match.undo();
      while (_match.canUndo && _botTurn) {
        _match.undo();
      }
      _message = null;
    });
    _scheduleBot();
  }

  void _nextPlayer() {
    if (_game.isOver) return;
    final player = _game.currentPlayer;
    final turn = _game.currentTurn;
    _game.nextPlayer();
    _handleResult(_game.isOver ? ThrowResult.win : ThrowResult.turnOver, player, turn);
  }

  void _restart() {
    _botTimer?.cancel();
    setState(() {
      _match = Match(settings: _match.settings, players: _match.players);
      _bots = _match.createBots();
      _message = null;
    });
    _scheduleBot();
  }

  Future<void> _correct(int index) async {
    final turn = _game.correctableTurn;
    if (turn == null) return;
    if (turn.isTotal) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Eingegebene Summe ändern: Rückgängig und neu eingeben')));
      return;
    }
    _botTimer?.cancel();
    final hit = await _pickHit('Dart ${index + 1} korrigieren (erkannt: ${turn.darts[index].label})');
    if (hit == null || !mounted) {
      _scheduleBot();
      return;
    }
    final wasOver = _game.isOver;
    setState(() {
      _game.correctDart(index, hit);
      _message = 'Korrigiert: ${hit.label}';
    });
    if (!wasOver && _game.isOver) {
      _onLegWon(_game.winner!);
    } else {
      _scheduleBot();
    }
  }

  /// Tastenfeld als Bottom Sheet; liefert das gewählte Feld oder null.
  Future<Hit?> _pickHit(String title) {
    return showModalBottomSheet<Hit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              InputPad(onHit: (hit) => Navigator.pop(context, hit)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manualDart() async {
    final hit = await _pickHit('Dart eintragen');
    if (hit != null && mounted) _onHit(hit);
  }

  // ---------------------------------------------------------------- Bot

  void _scheduleBot() {
    _botTimer?.cancel();
    if (!mounted || !_botTurn) return;
    _botTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || !_botTurn) return;
      final bot = _bots[_game.currentPlayer]!;
      _onHit(bot.throwAt(_game.botTarget()), fromBot: true);
    });
  }

  // ---------------------------------------------------------------- Leg- und Match-Ende

  Future<void> _onLegWon(int player) async {
    _botTimer?.cancel();
    if (_match.isOver) return _onMatchWon(player);
    Speech.say('Game shot! Leg an ${_name(player)}');
    final wins = _match.legWins;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag_outlined),
        title: Text('Leg an ${_name(player)}'),
        content: Text('Stand: ${wins.join(' : ')}\n${_legSummary(player)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'undo'), child: const Text('Rückgängig')),
          FilledButton(onPressed: () => Navigator.pop(context, 'next'), child: const Text('Nächstes Leg')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'undo') return _undo();
    setState(() {
      _match.startNextLeg();
      _message = null;
    });
    _scheduleBot();
  }

  Future<void> _onMatchWon(int player) async {
    final solo = _match.players.length == 1;
    Speech.say(solo ? 'Geschafft!' : 'Game shot and the match! ${_name(player)}');
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.emoji_events_outlined),
        title: Text(solo ? 'Fertig!' : '${_name(player)} gewinnt'),
        content: Text([
          if (_match.settings.bestOf > 1) 'Legs: ${_match.legWins.join(' : ')}',
          _legSummary(player),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'undo'), child: const Text('Rückgängig')),
          TextButton(onPressed: () => Navigator.pop(context, 'menu'), child: const Text('Menü')),
          FilledButton(onPressed: () => Navigator.pop(context, 'rematch'), child: const Text('Revanche')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'undo') return _undo();
    // Erst beim Verlassen speichern – "Rückgängig" soll kein halbes Match in die Historie schreiben
    await (await LocalStore.instance()).saveMatch(_match);
    if (!mounted) return;
    if (action == 'rematch') {
      _restart();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Kurze Statistik für die Dialoge.
  String _legSummary(int player) {
    final stats = _match.stats()[player];
    final parts = [
      for (final key in const ['average', 'mpr', 'score', 'checkouts', 'darts'])
        if (stats[key] != null) '${Match.statLabels[key]}: ${_format(stats[key]!)}',
    ];
    return parts.take(2).join(' · ');
  }

  static String _format(num v) => v is int ? '$v' : v.toStringAsFixed(1);

  // ---------------------------------------------------------------- Kamera

  void _onDetected(Hit hit, Offset tip) {
    if (!mounted || _game.isOver || _botTurn) return;
    _onHit(hit);
  }

  /// Darts wurden gezogen. Stecken weniger als 3 in der Aufnahme, gingen die übrigen daneben.
  void _onCleared() {
    if (!mounted || _game.isOver || _botTurn) return;
    final turn = _game.currentTurn;
    if (turn.darts.isNotEmpty && !turn.finished) _nextPlayer();
  }

  Future<void> _toggleCamera() async {
    if (_live != null) {
      setState(() {
        _live!.dispose();
        _live = null;
      });
      return;
    }

    var calibration = await BoardCalibration.load();
    if (!mounted) return;
    var useDemo = false;
    if (calibration == null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.videocam_outlined),
          title: const Text('Kamera noch nicht eingerichtet'),
          content: const Text(
            'Stell das Handy fest auf und kalibriere die Scheibe einmal. '
            'Oder probier die Erkennung mit der Demo-Szene aus.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            TextButton(onPressed: () => Navigator.pop(context, 'demo'), child: const Text('Demo-Szene')),
            FilledButton(onPressed: () => Navigator.pop(context, 'setup'), child: const Text('Einrichten')),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'setup') {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CameraScreen()));
        calibration = await BoardCalibration.load();
        if (!mounted || calibration == null) return;
      }
      useDemo = choice == 'demo';
    }

    final live = LiveDetection(onDart: _onDetected, onCleared: _onCleared)..addListener(_onLiveChanged);
    setState(() => _live = live);
    if (useDemo) {
      await live.startDemo();
    } else {
      live.calibration = calibration;
      await live.startCamera();
    }
    if (!identical(_live, live)) return; // in der Zwischenzeit ausgeschaltet
    if (live.isDemo || live.cameraRunning) live.setDetecting(true);
  }

  Future<void> _switchToDemo() async {
    final live = _live;
    if (live == null) return;
    await live.startDemo();
    live.setDetecting(true);
  }

  void _onLiveChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeech() async {
    final store = await LocalStore.instance();
    setState(() => Speech.enabled = !Speech.enabled);
    await store.setSpeechEnabled(Speech.enabled);
    if (Speech.enabled) {
      Speech.unlock();
      Speech.say('Sprachansage an');
    }
  }

  // ---------------------------------------------------------------- Oberfläche

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final live = _live;
    final x01 = _x01;
    final totalInput = x01 != null && _inputMode == InputMode.turnTotal && live == null;
    final inputEnabled = !game.isOver && !_botTurn;
    final subtitle = [
      ?game.subtitle,
      if (_match.settings.bestOf > 1) 'Leg ${_match.legs.length} · Best of ${_match.settings.bestOf}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(game.title),
            if (subtitle.isNotEmpty) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (live == null && x01 != null)
            IconButton(
              tooltip: _inputMode == InputMode.perDart
                  ? 'Eingabe: einzelne Darts (umschalten auf Gesamtpunktzahl)'
                  : 'Eingabe: Gesamtpunktzahl (umschalten auf einzelne Darts)',
              onPressed: _toggleInputMode,
              icon: Icon(_inputMode == InputMode.perDart ? Icons.apps : Icons.pin_outlined),
            ),
          IconButton(
            tooltip: live == null ? 'Mit Kamera zählen' : 'Kamera aus',
            onPressed: _toggleCamera,
            isSelected: live != null,
            icon: const Icon(Icons.videocam_off_outlined),
            selectedIcon: const Icon(Icons.videocam),
          ),
          IconButton(tooltip: 'Rückgängig', onPressed: _match.canUndo ? _undo : null, icon: const Icon(Icons.undo)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'speech' ? _toggleSpeech() : _restart(),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(value: 'speech', checked: Speech.enabled, child: const Text('Sprachansage')),
              const PopupMenuItem(value: 'restart', child: Text('Neu starten')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Auf kleinen Bildschirmen (z. B. iPhone SE im Browser) scrollen statt abschneiden
                final compact = live == null && constraints.maxHeight < 640;
                final column = Column(
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Scoreboard(match: _match),
                    // Bei der Gesamtpunktzahl gibt es keine einzelnen Darts; die letzte Aufnahme steht in der Punktetafel
                    if (!totalInput) ...[
                      const SizedBox(height: 12),
                      _TurnRow(game: game, onTapDart: _correct),
                    ] else
                      const SizedBox(height: 8),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: _InfoLine(
                        text: _message ?? (_botTurn ? '${_name(game.currentPlayer)} wirft …' : game.hint),
                        highlight: _message != null,
                      ),
                    ),
                    if (live == null) ...[
                      compact ? const SizedBox(height: 8) : const Spacer(),
                      if (!totalInput)
                        InputPad(onHit: _onHit, enabled: inputEnabled)
                      else
                        ScorePad(
                          onSubmit: _onTotal,
                          enabled: inputEnabled && game.currentTurn.darts.isEmpty,
                          disabledHint: !inputEnabled ? null : 'Erst die angefangene Aufnahme beenden',
                          remaining: game.isOver ? null : x01.remaining(x01.currentPlayer),
                        ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Expanded(child: _buildCamera(live)),
                    ],
                    if (!totalInput) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (live != null) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: inputEnabled ? _manualDart : null,
                                icon: const Icon(Icons.dialpad),
                                label: const Text('Eintragen'),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !inputEnabled || game.currentTurn.darts.isEmpty ? null : _nextPlayer,
                              icon: const Icon(Icons.skip_next),
                              label: const Text('Aufnahme beenden'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: compact ? SingleChildScrollView(child: column) : column,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCamera(LiveDetection live) {
    final scheme = Theme.of(context).colorScheme;
    final running = live.isDemo || live.cameraRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: running
                  ? LivePreview(
                      live: live,
                      overlay: (context, size) => CustomPaint(
                        painter: BoardOverlayPainter(
                          points: const [],
                          calibration: null,
                          activeHandle: null,
                          detected: List.of(live.detected),
                          color: Colors.lightGreenAccent,
                        ),
                      ),
                    )
                  : CameraStatus(live: live, onDemo: _switchToDemo),
            ),
          ),
        ),
        if (running)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: live.detecting ? Colors.redAccent : scheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${live.isDemo ? 'Demo-Szene' : 'Kamera'} · ${live.fps} Bilder/s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: live.resetEmptyBoard, child: const Text('Scheibe ist leer')),
              ],
            ),
          ),
      ],
    );
  }
}

/// Die Darts der laufenden Aufnahme – oder, solange darin noch keiner ist, die der vorigen.
/// Antippen eines Darts öffnet die Korrektur.
class _TurnRow extends StatelessWidget {
  const _TurnRow({required this.game, required this.onTapDart});

  final DartGame game;
  final ValueChanged<int> onTapDart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final turn = game.correctableTurn ?? game.currentTurn;
    final previous = !identical(turn, game.currentTurn);
    final darts = turn.darts;
    final total = turn.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 20,
          child: !previous
              ? null
              : Text(
                  'Letzte Aufnahme: ${game.players[turn.player]}${turn.bust ? ' (Bust)' : ''}'
                  '${turn.isTotal ? '' : ' – antippen zum Korrigieren'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        Row(
          children: [
            if (total != null)
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    turn.finished && !turn.bust && game.winner == turn.player
                        ? 'Checkout mit ${turn.totalDarts} ${turn.totalDarts == 1 ? 'Dart' : 'Darts'}'
                        : 'Gesamtpunktzahl eingegeben',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (var i = 0; i < dartsPerTurn; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: i < darts.length ? () => onTapDart(i) : null,
                      child: Ink(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            i < darts.length ? darts[i].label : '–',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: i >= darts.length
                                  ? scheme.outline
                                  : previous
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  game.turnLabel(turn),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: previous ? scheme.onSurfaceVariant : null),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Meldung (Bust, 180, …) oder Hinweis des Modus (Checkout-Weg, Ziel, …).
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.text, required this.highlight});

  final String? text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text ?? ' ',
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: highlight
          ? TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: scheme.primary)
          : TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
    );
  }
}
