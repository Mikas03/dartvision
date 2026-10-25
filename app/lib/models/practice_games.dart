import 'dart:math' as math;

import 'checkout.dart';
import 'dart_game.dart';
import 'hit.dart';

/// Around the Clock: 1 bis 20 der Reihe nach treffen (egal ob Single, Double oder Triple),
/// zum Schluss Bull. Mit [multiplesCount] bringt ein Double 2 Felder weiter, ein Triple 3.
class AroundTheClockGame extends DartGame {
  AroundTheClockGame({required super.players, super.startingPlayer, this.multiplesCount = false});

  final bool multiplesCount;

  /// Ziele in Reihenfolge: 1 … 20, dann Bull (25).
  static final targets = List<int>.unmodifiable([for (var i = 1; i <= 20; i++) i, 25]);

  @override
  String get title => 'Around the Clock';

  @override
  String? get subtitle => multiplesCount ? 'Double/Triple zählen mehrfach' : null;

  /// Index des nächsten Ziels von [player] (21 = fertig), berechnet aus allen Darts.
  int progress(int player) {
    var index = 0;
    for (final turn in turnsOf(player)) {
      for (final hit in turn.darts) {
        if (index >= targets.length || hit.segment != targets[index]) continue;
        if (hit.segment == 25) {
          index++;
        } else {
          // Mehrfach-Sprünge enden spätestens vor Bull – Bull muss man selbst treffen
          index = math.min(index + (multiplesCount ? hit.multiplier : 1), 20);
        }
      }
    }
    return index;
  }

  /// Nächstes Ziel von [player], null wenn fertig.
  int? target(int player) {
    final i = progress(player);
    return i < targets.length ? targets[i] : null;
  }

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) =>
      progress(turn.player) >= targets.length ? DartOutcome.win : DartOutcome.ok;

  @override
  String turnLabel(Turn turn) {
    final hits = turn.darts.where((h) => h.multiplier > 0).length;
    return hits == 1 ? '1 Treffer' : '$hits Treffer';
  }

  @override
  String? get hint {
    final t = target(currentPlayer);
    return isOver || t == null ? null : 'Ziel: ${t == 25 ? 'Bull' : t}';
  }

  @override
  Hit botTarget() {
    final t = target(currentPlayer) ?? 25;
    return t == 25 ? Hit.outerBull : Hit.single(t);
  }

  /// Darts, die [player] bis zum Ziel gebraucht hat (oder bisher).
  int dartsThrown(int player) => turnsOf(player).fold(0, (sum, t) => sum + t.darts.length);
}

/// Shanghai: 7 Runden. In Runde n zählt nur die Zahl n (Single n, Double 2n, Triple 3n).
/// Wer in einer Aufnahme Single, Double und Triple der Rundenzahl trifft ("Shanghai"),
/// gewinnt sofort. Sonst gewinnt nach 7 Runden die höchste Punktzahl.
class ShanghaiGame extends DartGame {
  ShanghaiGame({required super.players, super.startingPlayer, this.rounds = 7});

  final int rounds;

  @override
  String get title => 'Shanghai';

  /// Runde (1-basiert) einer Aufnahme von [player] mit Index [turnIndex] seiner Aufnahmen.
  int roundOf(Turn turn) => turnsOf(turn.player).toList().indexOf(turn) + 1;

  int get currentRound => roundOf(currentTurn);

  int turnPoints(Turn turn) {
    final round = roundOf(turn);
    return turn.darts.where((h) => h.segment == round).fold(0, (sum, h) => sum + h.value);
  }

  int score(int player) => turnsOf(player).fold(0, (sum, t) => sum + turnPoints(t));

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) {
    final round = roundOf(turn);
    final multipliers = turn.darts.where((h) => h.segment == round).map((h) => h.multiplier).toSet();
    return multipliers.containsAll(const [1, 2, 3]) ? DartOutcome.win : DartOutcome.ok;
  }

  @override
  int? winnerAfterTurn(Turn turn) {
    // Alle haben die letzte Runde gespielt?
    if (List.generate(players.length, roundsPlayed).any((r) => r < rounds)) return null;
    final scores = List.generate(players.length, score);
    final best = scores.reduce(math.max);
    return scores.indexOf(best);
  }

  @override
  String turnLabel(Turn turn) => '${turnPoints(turn)}';

  @override
  String? get hint => isOver ? null : 'Runde $currentRound von $rounds: nur die $currentRound zählt';

  @override
  Hit botTarget() {
    final round = currentRound;
    final hit = currentTurn.darts.where((h) => h.segment == round).map((h) => h.multiplier).toSet();
    // Auf den fehlenden Teil des Shanghai zielen
    if (!hit.contains(3)) return Hit.triple(round);
    if (!hit.contains(2)) return Hit.double(round);
    return Hit.single(round);
  }
}

/// Bob's 27 (Doppel-Training): Start mit 27 Punkten, Runde für Runde D1 bis D20 und Bull.
/// Jeder Treffer bringt den Wert des Doppels; ohne Treffer in einer Runde wird der Wert
/// abgezogen. Wer auf 0 oder darunter fällt, ist raus.
class Bobs27Game extends DartGame {
  Bobs27Game({required super.players, super.startingPlayer});

  static const startScore = 27;

  /// Ziele: D1 … D20, dann Bull.
  static final targets = List<int>.unmodifiable([for (var i = 1; i <= 20; i++) i, 25]);

  @override
  String get title => "Bob's 27";

  int _targetOf(int round) => targets[(round - 1).clamp(0, targets.length - 1)];

  int roundOf(Turn turn) => turnsOf(turn.player).toList().indexOf(turn) + 1;

  int turnPoints(Turn turn) {
    final target = _targetOf(roundOf(turn));
    final value = target == 25 ? 50 : 2 * target;
    final hits = turn.darts.where((h) => h.segment == target && h.isDouble).length;
    if (hits > 0) return hits * value;
    return turn.finished ? -value : 0;
  }

  int score(int player) => startScore + turnsOf(player).fold(0, (sum, t) => sum + turnPoints(t));

  /// Doppel, auf das der aktuelle Spieler wirft.
  int get currentTarget => _targetOf(roundOf(currentTurn));

  @override
  bool isActive(int player) => score(player) > 0 && roundsPlayed(player) < targets.length;

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) => DartOutcome.ok;

  @override
  int? winnerAfterTurn(Turn turn) {
    if (List.generate(players.length, isActive).any((a) => a)) return null;
    final scores = List.generate(players.length, score);
    return scores.indexOf(scores.reduce(math.max));
  }

  @override
  String turnLabel(Turn turn) {
    final p = turnPoints(turn);
    return p > 0 ? '+$p' : '$p';
  }

  @override
  String? get hint => isOver ? null : 'Ziel: ${currentTarget == 25 ? 'Bull' : 'D$currentTarget'}';

  @override
  Hit botTarget() => currentTarget == 25 ? Hit.bull : Hit.double(currentTarget);
}

/// Checkout-Training: In jeder Runde gibt es einen zufälligen Rest (2–170), der mit einer
/// Aufnahme (3 Darts) und Doppel ausgecheckt werden soll. Alle Spieler bekommen dieselben
/// Aufgaben. Nach [rounds] Runden gewinnt, wer die meisten Checkouts geschafft hat.
class CheckoutTrainingGame extends DartGame {
  CheckoutTrainingGame({required super.players, super.startingPlayer, this.rounds = 10, int? seed})
      : seed = seed ?? DateTime.now().millisecondsSinceEpoch % 100000 {
    final rng = math.Random(this.seed);
    while (_targets.length < rounds) {
      final t = 2 + rng.nextInt(169);
      if (suggestCheckout(t) != null) _targets.add(t);
    }
  }

  final int rounds;

  /// Startwert des Zufallsgenerators – gespeichert, damit Historie und Online-Gegner
  /// dieselben Aufgaben haben.
  final int seed;
  final List<int> _targets = [];

  List<int> get targets => List.unmodifiable(_targets);

  @override
  String get title => 'Checkout-Training';

  int roundOf(Turn turn) => turnsOf(turn.player).toList().indexOf(turn) + 1;

  int targetOf(Turn turn) => _targets[(roundOf(turn) - 1).clamp(0, rounds - 1)];

  int get currentTarget => targetOf(currentTurn);

  /// Rest in der laufenden Aufnahme.
  int get currentRest => currentTarget - currentTurn.thrown;

  bool succeeded(Turn turn) {
    if (turn.darts.isEmpty) return false;
    return turn.thrown == targetOf(turn) && turn.darts.last.isDouble && !turn.bust;
  }

  int successes(int player) => finishedTurnsOf(player).where(succeeded).length;

  @override
  bool isActive(int player) => roundsPlayed(player) < rounds;

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) {
    final rest = targetOf(turn) - turn.thrown;
    if (rest < 0 || rest == 1 || (rest == 0 && !hit.isDouble)) return DartOutcome.bust;
    if (rest == 0) return DartOutcome.endTurn;
    return DartOutcome.ok;
  }

  @override
  int? winnerAfterTurn(Turn turn) {
    if (List.generate(players.length, isActive).any((a) => a)) return null;
    final s = List.generate(players.length, successes);
    return s.indexOf(s.reduce(math.max));
  }

  @override
  String turnLabel(Turn turn) => succeeded(turn) ? 'Geschafft' : (turn.finished ? 'Verfehlt' : '${turn.thrown}');

  @override
  String? get hint {
    if (isOver) return null;
    final way = suggestCheckout(currentRest, darts: dartsLeftInTurn);
    return 'Runde ${roundOf(currentTurn)}/$rounds · Rest $currentRest'
        '${way == null ? '' : ' · ${way.join(' · ')}'}';
  }

  @override
  Hit botTarget() {
    final rest = currentRest;
    final way = suggestCheckout(rest, darts: dartsLeftInTurn) ?? suggestCheckout(rest, darts: 3);
    return way?.first ?? const Hit.triple(20);
  }
}
