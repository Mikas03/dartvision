import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../models/match.dart';

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

String formatStat(num v) => v is int ? '$v' : v.toStringAsFixed(1);

/// Liste aller gespeicherten Matches.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<MatchRecord>? _records;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Neu laden (z. B. wenn der Tab wieder sichtbar wird).
  Future<void> reload() async {
    final store = await LocalStore.instance();
    if (mounted) setState(() => _records = store.history);
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('Historie')),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _RecordTile(
                    record: records[i],
                    onTap: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => MatchDetailScreen(record: records[i])));
                      reload();
                    },
                  ),
                ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text('Noch keine Spiele', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Beendete Matches erscheinen hier – mit Ergebnis, Statistik und jedem Wurf.',
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onTap});

  final MatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = record;
    final result = r.players.length == 1
        ? r.players.first.name
        : [
            for (var p = 0; p < r.players.length; p++)
              '${r.players[p].name}${r.players.length == 2 && r.legWins.reduce((a, b) => a + b) > 1 ? ' ${r.legWins[p]}' : ''}',
          ].join(r.players.length == 2 ? ' : ' : ', ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Icon(r.mode.isTraining ? Icons.fitness_center : Icons.sports_esports_outlined, size: 20),
      ),
      title: Text(result, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${r.description}\n${formatDate(r.finishedAt)}'),
      isThreeLine: true,
      trailing: r.winner == null || r.players.length == 1
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(Icons.emoji_events_outlined, size: 18, color: scheme.tertiary),
                Text(r.players[r.winner!].name, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
    );
  }
}

/// Details eines Matches: Statistik je Spieler und jeder Wurf je Leg.
class MatchDetailScreen extends StatelessWidget {
  const MatchDetailScreen({super.key, required this.record});

  final MatchRecord record;

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Match löschen?'),
        content: const Text('Das Match verschwindet aus der Historie und den Statistiken.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await (await LocalStore.instance()).deleteMatch(record.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    Match? match;
    try {
      match = r.restore();
    } catch (_) {
      match = null; // Verlauf nicht lesbar (z. B. ältere Version) – Statistik geht trotzdem
    }
    final keys = [
      for (final k in Match.statLabels.keys)
        if (r.stats.any((s) => s.containsKey(k)) && !(k == 'legs' && r.legWins.reduce((a, b) => a + b) <= 1)) k,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(r.mode.title),
        actions: [
          IconButton(tooltip: 'Löschen', onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(r.description, style: theme.textTheme.titleMedium),
          Text(formatDate(r.finishedAt), style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          // Statistik-Tabelle: Zeilen = Kennzahlen, Spalten = Spieler
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                const SizedBox(),
                for (var p = 0; p < r.players.length; p++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (r.winner == p && r.players.length > 1)
                          Icon(Icons.emoji_events_outlined, size: 16, color: theme.colorScheme.tertiary),
                        Flexible(
                          child: Text(r.players[p].name,
                              overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall, textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
              ]),
              for (final k in keys)
                TableRow(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(Match.statLabels[k]!, style: theme.textTheme.bodyMedium),
                    ),
                    for (var p = 0; p < r.players.length; p++)
                      Text(r.stats[p][k] == null ? '–' : formatStat(r.stats[p][k]!), textAlign: TextAlign.end),
                  ],
                ),
            ],
          ),
          if (match != null) ...[
            const SizedBox(height: 24),
            Text('Würfe', style: theme.textTheme.titleMedium),
            for (var i = 0; i < match.legs.length; i++) _LegTile(match: match, index: i),
          ],
        ],
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  const _LegTile({required this.match, required this.index});

  final Match match;
  final int index;

  @override
  Widget build(BuildContext context) {
    final leg = match.legs[index];
    final winner = leg.winner;
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Leg ${index + 1}${winner == null ? '' : ' · ${match.players[winner].name}'}'),
      children: [
        for (final turn in leg.turns.where((t) => t.darts.isNotEmpty || t.isTotal))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(match.players[turn.player].name, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: Text(
                    turn.isTotal ? 'Summe' : turn.darts.map((d) => d.label).join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Text(leg.turnLabel(turn), style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
