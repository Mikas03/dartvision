import 'package:flutter/material.dart';

import '../models/cricket_game.dart';
import '../models/match.dart';
import '../models/practice_games.dart';
import '../models/x01_game.dart';

/// Punkteanzeige für alle Modi: Karten pro Spieler, bei Cricket eine Marks-Tabelle.
class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final game = match.leg;
    if (game is CricketGame) return _CricketBoard(match: match, game: game);

    final cards = [for (var p = 0; p < match.players.length; p++) _cardData(game, p)];
    return LayoutBuilder(builder: (context, constraints) {
      final count = cards.length;
      final width = (constraints.maxWidth - 8 * (count - 1)) / count;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              SizedBox(
                width: width < 130 ? 130 : width,
                child: _PlayerCard(match: match, player: i, data: cards[i]),
              ),
            ],
          ],
        ),
      );
    });
  }

  ({String value, List<String> lines}) _cardData(DartGame game, int p) {
    final last = game.lastTurn(p);
    final lastLabel = last == null ? '–' : game.turnLabel(last);
    return switch (game) {
      X01Game g => (
          value: '${g.displayRemaining(p)}',
          lines: ['Ø ${g.average(p).toStringAsFixed(1)}', 'Letzte: $lastLabel'],
        ),
      AroundTheClockGame g => (
          value: switch (g.target(p)) { null => 'Fertig', 25 => 'Bull', final t => '$t' },
          lines: ['Ziel', 'Darts: ${g.dartsThrown(p)}'],
        ),
      ShanghaiGame g => (
          value: '${g.score(p)}',
          lines: ['Punkte', 'Letzte: $lastLabel'],
        ),
      Bobs27Game g => (
          value: '${g.score(p)}',
          lines: [g.isActive(p) ? 'Punkte' : 'Ausgeschieden', 'Letzte: $lastLabel'],
        ),
      CheckoutTrainingGame g => (
          value: '${g.successes(p)}/${g.rounds}',
          lines: ['Checkouts', 'Runden: ${g.roundsPlayed(p)}'],
        ),
      _ => (value: '', lines: const []),
    };
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.match, required this.player, required this.data});

  final Match match;
  final int player;
  final ({String value, List<String> lines}) data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final game = match.leg;
    final active = !game.isOver && game.currentPlayer == player;
    final winner = game.winner == player;
    final info = match.players[player];

    final background = winner
        ? scheme.tertiaryContainer
        : active
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = winner
        ? scheme.onTertiaryContainer
        : active
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (winner)
                  Icon(Icons.emoji_events_outlined, size: 18, color: foreground)
                else if (active)
                  Icon(Icons.arrow_right, size: 18, color: foreground),
                if (info.isBot) Icon(Icons.smart_toy_outlined, size: 16, color: foreground),
                if (info.isBot) const SizedBox(width: 4),
                Expanded(
                  child: Text(info.name,
                      overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: foreground)),
                ),
                if (match.settings.bestOf > 1)
                  Text('${match.legWins[player]}',
                      style: text.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w700)),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(data.value,
                  style: text.displayMedium?.copyWith(color: foreground, fontWeight: FontWeight.w500)),
            ),
            for (final line in data.lines) Text(line, style: text.bodySmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

/// Cricket-Tabelle: Zeilen 20 … 15, Bull; Spalten Spieler; darunter die Punkte.
class _CricketBoard extends StatelessWidget {
  const _CricketBoard({required this.match, required this.game});

  final Match match;
  final CricketGame game;

  static String _symbol(int marks) => switch (marks) { 0 => '', 1 => '/', 2 => 'X', _ => 'Ⓧ' };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = game.state();
    final players = match.players;

    Widget cell(Widget child, {Color? color}) => Container(
          height: 26,
          alignment: Alignment.center,
          color: color,
          child: child,
        );

    Color? columnColor(int p) => !game.isOver && game.currentPlayer == p ? scheme.primaryContainer : null;

    return Table(
      columnWidths: const {0: FixedColumnWidth(52)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          cell(const SizedBox()),
          for (var p = 0; p < players.length; p++)
            cell(
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (players[p].isBot) const Icon(Icons.smart_toy_outlined, size: 14),
                  Flexible(
                    child: Text(
                      ' ${players[p].name}${match.settings.bestOf > 1 ? ' (${match.legWins[p]})' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                  ),
                ],
              ),
              color: columnColor(p),
            ),
        ]),
        for (final n in cricketNumbers)
          TableRow(children: [
            cell(Text(n == 25 ? 'Bull' : '$n', style: text.titleSmall)),
            for (var p = 0; p < players.length; p++)
              cell(
                Text(_symbol(state.marks[p][n]!),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: state.marks[p][n]! >= 3 ? scheme.primary : scheme.onSurface)),
                color: columnColor(p),
              ),
          ]),
        TableRow(children: [
          cell(Text('Punkte', style: text.bodySmall)),
          for (var p = 0; p < players.length; p++)
            cell(Text('${state.points[p]}', style: text.titleMedium), color: columnColor(p)),
        ]),
      ],
    );
  }
}
