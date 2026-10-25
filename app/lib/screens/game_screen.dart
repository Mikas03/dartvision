import 'package:flutter/material.dart';

import '../models/checkout.dart';
import '../models/hit.dart';
import '../models/x01_game.dart';
import '../widgets/input_pad.dart';
import '../widgets/scoreboard.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.createGame});

  /// Erzeugt ein frisches Spiel (auch für "Revanche").
  final X01Game Function() createGame;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late X01Game _game = widget.createGame();
  String? _message;

  void _onHit(Hit hit) {
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

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Scaffold(
      appBar: AppBar(
        title: Text('${game.startScore}${game.doubleOut ? ' · Double Out' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: game.canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(tooltip: 'Neu starten', onPressed: _restart, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Scoreboard(game: game),
                  const SizedBox(height: 12),
                  _TurnRow(game: game),
                  const SizedBox(height: 6),
                  _InfoLine(game: game, message: _message),
                  const Spacer(),
                  InputPad(onHit: _onHit, enabled: !game.isOver),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: game.isOver || game.currentTurn.darts.isEmpty ? null : _nextPlayer,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Aufnahme beenden'),
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

/// Die (bis zu) drei Darts der laufenden Aufnahme.
class _TurnRow extends StatelessWidget {
  const _TurnRow({required this.game});

  final X01Game game;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final darts = game.currentTurn.darts;
    return Row(
      children: [
        for (var i = 0; i < dartsPerTurn; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                i < darts.length ? darts[i].label : '–',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: i < darts.length ? scheme.onSurface : scheme.outline,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            '${game.currentTurn.thrown}',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
      return Text(message!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: scheme.primary));
    }
    if (game.isOver) return const SizedBox(height: 24);

    final rest = game.displayRemaining(game.currentPlayer);
    final way = suggestCheckout(rest, darts: game.dartsLeftInTurn, doubleOut: game.doubleOut);
    return Text(
      way == null ? ' ' : 'Checkout: ${way.join(' · ')}',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
    );
  }
}
