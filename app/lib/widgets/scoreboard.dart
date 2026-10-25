import 'package:flutter/material.dart';

import '../models/x01_game.dart';

class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.game});

  final X01Game game;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final count = game.players.length;
      final width = (constraints.maxWidth - 8 * (count - 1)) / count;
      final cards = [
        for (var i = 0; i < count; i++)
          SizedBox(width: width < 130 ? 130 : width, child: _PlayerCard(game: game, player: i)),
      ];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              cards[i],
            ],
          ],
        ),
      );
    });
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.game, required this.player});

  final X01Game game;
  final int player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = !game.isOver && game.currentPlayer == player;
    final winner = game.winner == player;
    final last = game.lastTurn(player);

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
                if (active) Icon(Icons.arrow_right, size: 18, color: foreground),
                if (winner) Icon(Icons.emoji_events_outlined, size: 18, color: foreground),
                Expanded(
                  child: Text(game.players[player], overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: foreground)),
                ),
              ],
            ),
            Text(
              game.displayRemaining(player).toString(),
              style: text.displayMedium?.copyWith(color: foreground, fontWeight: FontWeight.w500),
            ),
            Text('Ø ${game.average(player).toStringAsFixed(1)}', style: text.bodySmall?.copyWith(color: foreground)),
            Text(
              last == null ? 'Letzte: –' : 'Letzte: ${last.bust ? 'Bust' : last.scored}',
              style: text.bodySmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
