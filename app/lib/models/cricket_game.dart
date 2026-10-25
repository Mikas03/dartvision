import 'dart_game.dart';
import 'hit.dart';

/// Die Cricket-Zahlen: 20 bis 15 und Bull.
const cricketNumbers = [20, 19, 18, 17, 16, 15, 25];

/// Cricket: Jede der Zahlen 15–20 und Bull dreimal treffen ("schließen").
/// Weitere Treffer auf eine selbst geschlossene Zahl geben Punkte, solange ein Gegner sie noch
/// offen hat. Gewonnen hat, wer alles geschlossen hat und nicht weniger Punkte hat.
///
/// Bei **Cut-Throat** gehen die Punkte an die Gegner, die die Zahl noch offen haben;
/// gewonnen hat, wer alles geschlossen hat und die wenigsten Punkte hat.
class CricketGame extends DartGame {
  CricketGame({required super.players, super.startingPlayer, this.cutThroat = false});

  final bool cutThroat;

  @override
  String get title => 'Cricket';

  @override
  String? get subtitle => cutThroat ? 'Cut-Throat' : null;

  /// Treffer (Marks) eines Darts auf eine Cricket-Zahl; Bull innen zählt doppelt.
  static int marksOf(Hit hit) => cricketNumbers.contains(hit.segment) ? hit.multiplier : 0;

  /// Marks und Punkte aller Spieler, berechnet aus allen bisherigen Darts.
  ({List<Map<int, int>> marks, List<int> points}) state() {
    final marks = [for (var i = 0; i < players.length; i++) {for (final n in cricketNumbers) n: 0}];
    final points = List.filled(players.length, 0);
    for (final turn in turns) {
      for (final hit in turn.darts) {
        final m = marksOf(hit);
        if (m > 0) {
          final own = marks[turn.player];
          final before = own[hit.segment]!;
          final extra = (before + m - 3).clamp(0, m);
          own[hit.segment] = (before + m).clamp(0, 3);
          if (extra > 0) {
            final value = extra * (hit.segment == 25 ? 25 : hit.segment);
            final open = [
              for (var p = 0; p < players.length; p++)
                if (p != turn.player && marks[p][hit.segment]! < 3) p,
            ];
            if (cutThroat) {
              for (final p in open) {
                points[p] += value;
              }
            } else if (open.isNotEmpty) {
              points[turn.player] += value;
            }
          }
        }
      }
    }
    return (marks: marks, points: points);
  }

  List<Map<int, int>> get marks => state().marks;
  List<int> get points => state().points;

  bool _closedAll(Map<int, int> marks) => marks.values.every((m) => m >= 3);

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) {
    final s = state();
    final me = turn.player;
    if (!_closedAll(s.marks[me])) return DartOutcome.ok;
    final others = [for (var p = 0; p < players.length; p++) if (p != me) s.points[p]];
    if (others.isEmpty) return DartOutcome.win;
    final leading = cutThroat
        ? others.every((p) => s.points[me] <= p)
        : others.every((p) => s.points[me] >= p);
    return leading ? DartOutcome.win : DartOutcome.ok;
  }

  /// Marks einer Aufnahme (für die Anzeige).
  int turnMarks(Turn turn) => turn.darts.fold(0, (sum, h) => sum + marksOf(h));

  @override
  String turnLabel(Turn turn) {
    final m = turnMarks(turn);
    return m == 1 ? '1 Mark' : '$m Marks';
  }

  @override
  String? get hint {
    if (isOver) return null;
    final open = [
      for (final n in cricketNumbers)
        if (marks[currentPlayer][n]! < 3) n == 25 ? 'Bull' : '$n',
    ];
    return open.isEmpty ? 'Alles zu – jetzt Punkte machen' : 'Offen: ${open.join(' · ')}';
  }

  @override
  Hit botTarget() {
    final s = state();
    final me = currentPlayer;
    // Zuerst eigene offene Zahlen schließen (von 20 abwärts)
    for (final n in cricketNumbers) {
      if (s.marks[me][n]! < 3) return n == 25 ? Hit.bull : Hit.triple(n);
    }
    // Alles zu: auf Zahlen punkten, die ein Gegner noch offen hat
    for (final n in cricketNumbers) {
      final someoneOpen = [for (var p = 0; p < players.length; p++) if (p != me) s.marks[p][n]!].any((m) => m < 3);
      if (someoneOpen) return n == 25 ? Hit.bull : Hit.triple(n);
    }
    return const Hit.triple(20);
  }

  // ---------------------------------------------------------------- Statistik

  /// Marks pro Runde (3 Darts) – die übliche Cricket-Statistik.
  double marksPerRound(int player) {
    final own = turnsOf(player);
    final darts = own.fold(0, (sum, t) => sum + t.darts.length);
    if (darts == 0) return 0;
    return own.fold(0, (sum, t) => sum + turnMarks(t)) / darts * dartsPerTurn;
  }
}
