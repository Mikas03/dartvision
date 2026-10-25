import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/storage.dart';
import 'history_screen.dart';

/// Spielerprofile auf diesem Gerät mit Statistik über alle gespeicherten Matches.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => ProfilesScreenState();
}

class ProfilesScreenState extends State<ProfilesScreen> {
  List<PlayerProfile>? _profiles;
  List<MatchRecord> _history = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final store = await LocalStore.instance();
    if (mounted) {
      setState(() {
        _profiles = store.profiles;
        _history = store.history;
      });
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Speichern')),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _askName('Neuer Spieler');
    if (name == null || name.trim().isEmpty) return;
    await (await LocalStore.instance()).addProfile(name);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('Spieler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Spieler'),
      ),
      body: profiles == null
          ? const Center(child: CircularProgressIndicator())
          : profiles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Lege Spieler an, um Statistiken über mehrere Spiele zu sammeln. '
                      'Später lassen sich Profile mit einem Account verbinden.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final p in profiles)
                      Builder(builder: (context) {
                        final stats = ProfileStats(p.id, _history);
                        final avg = stats.averageX01;
                        return ListTile(
                          leading: CircleAvatar(child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
                          title: Text(p.name),
                          subtitle: Text([
                            '${stats.matches} Spiele · ${stats.wins} Siege',
                            if (avg != null) 'Ø ${avg.toStringAsFixed(1)}',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ProfileDetailScreen(profile: p, history: _history),
                            ));
                            reload();
                          },
                        );
                      }),
                  ],
                ),
    );
  }
}

class ProfileDetailScreen extends StatelessWidget {
  const ProfileDetailScreen({super.key, required this.profile, required this.history});

  final PlayerProfile profile;
  final List<MatchRecord> history;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Umbenennen'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Speichern')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await (await LocalStore.instance()).renameProfile(profile.id, name);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${profile.name} löschen?'),
        content: const Text('Gespeicherte Matches bleiben in der Historie erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await (await LocalStore.instance()).deleteProfile(profile.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = ProfileStats(profile.id, history);
    final matches = history.where((r) => r.players.any((p) => p.profileId == profile.id)).toList();
    final tiles = <(String, String)>[
      ('Spiele', '${stats.matches}'),
      ('Siege', '${stats.wins}'),
      if (stats.averageX01 != null) ('X01-Average', stats.averageX01!.toStringAsFixed(1)),
      if (stats.highestCheckout > 0) ('Höchster Checkout', '${stats.highestCheckout}'),
      ('180er', '${stats.count180}'),
      ('140+', '${stats.count140}'),
      ('100+', '${stats.count100}'),
      if (stats.averageMpr != null) ('Cricket MPR', stats.averageMpr!.toStringAsFixed(2)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.name),
        actions: [
          IconButton(tooltip: 'Umbenennen', onPressed: () => _rename(context), icon: const Icon(Icons.edit_outlined)),
          IconButton(tooltip: 'Löschen', onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in tiles)
                Container(
                  width: 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      Text(value, style: theme.textTheme.headlineSmall),
                    ],
                  ),
                ),
            ],
          ),
          if (stats.x01Averages.length >= 2) ...[
            const SizedBox(height: 24),
            Text('X01-Average der letzten Spiele', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _AverageChart(
                  values: stats.x01Averages.length > 20
                      ? stats.x01Averages.sublist(stats.x01Averages.length - 20)
                      : stats.x01Averages,
                  color: theme.colorScheme.primary,
                  gridColor: theme.colorScheme.outlineVariant,
                  textColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Letzte Spiele', style: theme.textTheme.titleMedium),
          for (final r in matches.take(20))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.description),
              subtitle: Text(formatDate(r.finishedAt)),
              trailing: r.winner != null && r.players[r.winner!].profileId == profile.id
                  ? Icon(Icons.emoji_events_outlined, color: theme.colorScheme.tertiary)
                  : null,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(record: r))),
            ),
        ],
      ),
    );
  }
}

/// Einfaches Säulendiagramm des Averages je Match (ältestes links).
class _AverageChart extends CustomPainter {
  _AverageChart({required this.values, required this.color, required this.gridColor, required this.textColor});

  final List<double> values;
  final Color color;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (values.reduce(math.max) / 20).ceil() * 20.0;
    const left = 28.0, bottom = 4.0;
    final chartH = size.height - bottom;
    final grid = Paint()..color = gridColor;
    for (var v = 0.0; v <= top; v += top / 2) {
      final y = chartH - v / top * chartH;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(0), style: TextStyle(fontSize: 10, color: textColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    final slot = (size.width - left) / values.length;
    final bar = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / top * chartH;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left + i * slot + slot * 0.15, chartH - h, slot * 0.7, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(_AverageChart old) => old.values != values;
}
