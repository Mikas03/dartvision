import 'package:flutter/material.dart';

import '../models/checkout.dart';
import '../models/hit.dart';
import '../models/x01_game.dart';
import '../vision/calibration.dart';
import '../vision/live_detection.dart';
import '../widgets/board_overlay.dart';
import '../widgets/input_pad.dart';
import '../widgets/live_preview.dart';
import '../widgets/score_pad.dart';
import '../widgets/scoreboard.dart';
import 'camera_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.createGame, this.inputMode = InputMode.perDart});

  /// Erzeugt ein frisches Spiel (auch für "Revanche").
  final X01Game Function() createGame;

  /// Eingabeart zu Beginn; lässt sich im Spiel umschalten.
  final InputMode inputMode;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late X01Game _game = widget.createGame();
  late InputMode _inputMode = widget.inputMode;
  String? _message;

  /// Läuft, solange die Kamera die Darts zählt.
  LiveDetection? _live;

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Spielzüge

  void _onHit(Hit hit) {
    if (_game.isOver) return;
    final player = _game.currentPlayer;
    final turn = _game.currentTurn;
    final result = _game.throwDart(hit);
    setState(() {
      _message = switch (result) {
        ThrowResult.bust => 'Bust!',
        ThrowResult.win => null,
        _ when turn.darts.length == dartsPerTurn && turn.thrown == 180 => 'Hundertachtzig!',
        ThrowResult.turnOver => '${_game.players[player]}: ${turn.thrown}',
        ThrowResult.ok => null,
      };
    });
    if (result == ThrowResult.win) _showWinner(player);
  }

  /// Eingabe der Gesamtpunktzahl. Liefert eine Fehlermeldung für das Zahlenfeld oder null.
  Future<String?> _onTotal(int score) async {
    if (_game.isOver) return null;
    final player = _game.currentPlayer;
    var darts = dartsPerTurn;
    if (score == _game.remaining(player) && score > 0) {
      // Checkout: mit wie vielen Darts? (für den Average) – nur mögliche Anzahlen anbieten
      final options = [
        for (var n = 1; n <= dartsPerTurn; n++)
          if (suggestCheckout(score, darts: n, doubleOut: _game.doubleOut) != null) n,
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

    final ThrowResult result;
    try {
      result = _game.enterTurnTotal(score, darts: darts);
    } on ArgumentError catch (e) {
      return e.message as String;
    }
    setState(() {
      _message = switch (result) {
        ThrowResult.bust => 'Bust!',
        ThrowResult.win => null,
        _ when score == 180 => 'Hundertachtzig!',
        _ => '${_game.players[player]}: $score',
      };
    });
    if (result == ThrowResult.win) _showWinner(player);
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

  void _undo() => setState(() {
    _game.undo();
    _message = null;
  });

  void _nextPlayer() => setState(() {
    _game.nextPlayer();
    _message = null;
  });

  void _restart() => setState(() {
    _game = widget.createGame();
    _message = null;
  });

  Future<void> _correct(int index) async {
    final turn = _game.correctableTurn;
    if (turn == null) return;
    if (turn.isTotal) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Eingegebene Summe ändern: Rückgängig und neu eingeben')));
      return;
    }
    final hit = await _pickHit('Dart ${index + 1} korrigieren (erkannt: ${turn.darts[index].label})');
    if (hit == null || !mounted) return;
    final wasOver = _game.isOver;
    setState(() {
      _game.correctDart(index, hit);
      _message = 'Korrigiert: ${hit.label}';
    });
    if (!wasOver && _game.isOver) _showWinner(_game.winner!);
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

  Future<void> _showWinner(int player) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.emoji_events_outlined),
        title: Text('${_game.players[player]} gewinnt'),
        content: Text('Average: ${_game.average(player).toStringAsFixed(1)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'undo'), child: const Text('Rückgängig')),
          TextButton(onPressed: () => Navigator.pop(context, 'menu'), child: const Text('Menü')),
          FilledButton(onPressed: () => Navigator.pop(context, 'rematch'), child: const Text('Revanche')),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'undo':
        _undo();
      case 'rematch':
        _restart();
      case 'menu':
        Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------- Kamera

  void _onDetected(Hit hit, Offset tip) {
    if (!mounted || _game.isOver) return;
    _onHit(hit);
  }

  /// Darts wurden gezogen. Stecken weniger als 3 in der Aufnahme, gingen die übrigen daneben.
  void _onCleared() {
    if (!mounted || _game.isOver) return;
    final turn = _game.currentTurn;
    if (turn.darts.isNotEmpty && !turn.finished) {
      final player = _game.players[_game.currentPlayer];
      _nextPlayer();
      setState(() => _message = '$player: ${turn.thrown}');
    }
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

  // ---------------------------------------------------------------- Oberfläche

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final live = _live;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${game.startScore}'),
            if (game.doubleOut) Text('Double Out', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (live == null)
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
          IconButton(tooltip: 'Rückgängig', onPressed: game.canUndo ? _undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Neu starten', onPressed: _restart, icon: const Icon(Icons.refresh)),
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
                    Scoreboard(game: game),
                    // Bei der Gesamtpunktzahl gibt es keine einzelnen Darts; die letzte Aufnahme steht in der Punktetafel
                    if (live != null || _inputMode == InputMode.perDart) ...[
                      const SizedBox(height: 12),
                      _TurnRow(game: game, onTapDart: _correct),
                    ] else
                      const SizedBox(height: 8),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: _InfoLine(game: game, message: _message),
                    ),
                    if (live == null) ...[
                      compact ? const SizedBox(height: 8) : const Spacer(),
                      if (_inputMode == InputMode.perDart)
                        InputPad(onHit: _onHit, enabled: !game.isOver)
                      else
                        ScorePad(
                          onSubmit: _onTotal,
                          enabled: !game.isOver && game.currentTurn.darts.isEmpty,
                          disabledHint: game.isOver ? null : 'Erst die angefangene Aufnahme beenden',
                          remaining: game.isOver ? null : game.remaining(game.currentPlayer),
                        ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Expanded(child: _buildCamera(live)),
                    ],
                    if (live != null || _inputMode == InputMode.perDart) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (live != null) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: game.isOver ? null : _manualDart,
                                icon: const Icon(Icons.dialpad),
                                label: const Text('Eintragen'),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: game.isOver || game.currentTurn.darts.isEmpty ? null : _nextPlayer,
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

  final X01Game game;
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
              width: 52,
              child: Text(
                '${previous ? turn.scored : turn.thrown}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(color: previous ? scheme.onSurfaceVariant : null),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Meldung (Bust, 180, ...) oder Checkout-Vorschlag.
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.game, required this.message});

  final X01Game game;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (message != null) {
      return Text(
        message!,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: scheme.primary),
      );
    }
    if (game.isOver) return const SizedBox();

    final rest = game.displayRemaining(game.currentPlayer);
    final way = suggestCheckout(rest, darts: game.dartsLeftInTurn, doubleOut: game.doubleOut);
    return Text(
      way == null ? ' ' : 'Checkout: ${way.join(' · ')}',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
    );
  }
}
