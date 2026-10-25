import 'checkout.dart';
import 'dart_game.dart';
import 'hit.dart';

export 'dart_game.dart';

/// Wie ein X01-Leg beendet werden muss.
enum OutRule {
  /// Mit jedem Feld.
  straight,

  /// Mit einem Doppel (Standard).
  double,

  /// Mit einem Doppel oder Triple.
  master,
}

/// X01 (301, 501, 701 …): Punkte von der Startzahl abziehen, genau auf 0 enden.
class X01Game extends DartGame {
  X01Game({
    required super.players,
    super.startingPlayer,
    this.startScore = 501,
    bool doubleOut = true,
    bool masterOut = false,
    this.doubleIn = false,
  }) : outRule = !doubleOut
            ? OutRule.straight
            : masterOut
                ? OutRule.master
                : OutRule.double;

  final int startScore;
  final OutRule outRule;

  /// Punkte zählen erst ab dem ersten Doppel.
  final bool doubleIn;

  bool get doubleOut => outRule != OutRule.straight;

  @override
  String get title => '$startScore';

  @override
  String? get subtitle {
    final parts = [
      if (doubleIn) 'Double In',
      switch (outRule) { OutRule.straight => 'Single Out', OutRule.double => 'Double Out', OutRule.master => 'Master Out' },
    ];
    return parts.join(' · ');
  }

  /// Punkte, die eine Aufnahme zählt (bei Double In erst ab dem ersten Doppel).
  int turnPoints(Turn turn) {
    if (turn.bust) return 0;
    if (!doubleIn || turn.isTotal || _isInBefore(turn)) return turn.thrown;
    final first = turn.darts.indexWhere((d) => d.isDouble);
    if (first < 0) return 0;
    return turn.darts.skip(first).fold(0, (sum, d) => sum + d.value);
  }

  /// Ob der Spieler vor [turn] schon "drin" ist (Double In).
  bool _isInBefore(Turn turn) {
    for (final t in turns) {
      if (identical(t, turn)) return false;
      if (t.player == turn.player && t.finished && !t.bust && (t.isTotal ? t.thrown > 0 : t.darts.any((d) => d.isDouble))) {
        return true;
      }
    }
    return false;
  }

  /// Ob der aktuelle Spieler noch ein Doppel zum Reinkommen braucht.
  bool get needsDoubleIn => doubleIn && turnPoints(currentTurn) == 0 && !_isInBefore(currentTurn);

  /// Restpunkte vor der laufenden Aufnahme.
  int remaining(int player) => startScore - finishedTurnsOf(player).fold(0, (sum, t) => sum + turnPoints(t));

  /// Restpunkte inklusive der Darts der laufenden Aufnahme (für die Anzeige).
  int displayRemaining(int player) {
    if (player != currentPlayer || currentTurn.finished) return remaining(player);
    return remaining(player) - turnPoints(currentTurn);
  }

  bool _validFinish(Hit hit) => switch (outRule) {
        OutRule.straight => true,
        OutRule.double => hit.isDouble,
        OutRule.master => hit.isDouble || hit.multiplier == 3,
      };

  @override
  DartOutcome evaluateDart(Turn turn, Hit hit) {
    final rest = remaining(turn.player) - turnPoints(turn);
    if (rest < 0 || (doubleOut && rest == 1) || (rest == 0 && !_validFinish(hit))) return DartOutcome.bust;
    if (rest == 0) return DartOutcome.win;
    return DartOutcome.ok;
  }

  @override
  String turnLabel(Turn turn) => turn.bust ? 'Bust' : '${turnPoints(turn)}';

  /// Checkout-Weg für den aktuellen Spieler mit den verbleibenden Darts, oder null.
  List<Hit>? get checkoutWay {
    if (isOver || needsDoubleIn) return null;
    return suggestCheckout(displayRemaining(currentPlayer), darts: dartsLeftInTurn, doubleOut: doubleOut);
  }

  @override
  String? get hint {
    if (isOver) return null;
    if (needsDoubleIn) return 'Erst ein Doppel treffen (Double In)';
    final way = checkoutWay;
    return way == null ? null : 'Checkout: ${way.join(' · ')}';
  }

  @override
  Hit botTarget() {
    if (needsDoubleIn) return const Hit.double(20);
    final rest = displayRemaining(currentPlayer);
    final way = suggestCheckout(rest, darts: dartsLeftInTurn, doubleOut: doubleOut) ??
        suggestCheckout(rest, darts: 2, doubleOut: doubleOut) ??
        suggestCheckout(rest, darts: 3, doubleOut: doubleOut);
    return way?.first ?? const Hit.triple(20);
  }

  // ---------------------------------------------------------------- Summeneingabe

  /// Trägt die Summe einer ganzen Aufnahme ein (Eingabeart [InputMode.turnTotal]).
  ///
  /// [darts] ist nur beim Checkout relevant (mit wie vielen Darts ausgecheckt wurde).
  /// Wirft einen [ArgumentError] bei unmöglichen Eingaben, z. B. 179 oder einem Checkout,
  /// der mit [darts] Darts nicht geht.
  ThrowResult enterTurnTotal(int score, {int darts = dartsPerTurn}) {
    if (isOver) throw StateError('Spiel ist bereits beendet');
    if (currentTurn.darts.isNotEmpty) throw StateError('In dieser Aufnahme wurden schon einzelne Darts eingetragen');
    if (!isPossibleScore(score)) throw ArgumentError('$score kann man mit drei Darts nicht werfen');

    final rest = remaining(currentPlayer) - score;
    if (rest == 0 && suggestCheckout(score, darts: darts, doubleOut: doubleOut) == null) {
      throw ArgumentError(darts == dartsPerTurn
          ? '$score lässt sich nicht auschecken'
          : '$score lässt sich nicht mit $darts ${darts == 1 ? 'Dart' : 'Darts'} auschecken');
    }
    setTotal(score, dartsPerTurn);
    if (rest < 0 || (doubleOut && rest == 1)) {
      finishTurn(bust: true);
      return ThrowResult.bust;
    }
    if (rest == 0) {
      setTotal(score, darts);
      declareWinner();
      return ThrowResult.win;
    }
    finishTurn();
    return ThrowResult.turnOver;
  }

  @override
  void replayTotal(int total, int darts) => enterTurnTotal(total, darts: darts);

  // ---------------------------------------------------------------- Statistik

  /// 3-Dart-Average.
  double average(int player) {
    final own = turnsOf(player);
    final darts = own.fold(0, (sum, t) => sum + t.dartCount);
    if (darts == 0) return 0;
    final points = own.fold(0, (sum, t) => sum + turnPoints(t));
    return points / darts * dartsPerTurn;
  }

  /// Average der ersten 9 Darts (erste drei Aufnahmen).
  double first9Average(int player) {
    final own = turnsOf(player).where((t) => t.finished).take(3).toList();
    final darts = own.fold(0, (sum, t) => sum + t.dartCount);
    if (darts == 0) return 0;
    return own.fold(0, (sum, t) => sum + turnPoints(t)) / darts * dartsPerTurn;
  }

  /// Anzahl Aufnahmen mit mindestens [points] Punkten.
  int countAtLeast(int player, int points) => finishedTurnsOf(player).where((t) => turnPoints(t) >= points).length;

  /// Wert des Checkouts, falls [player] das Leg gewonnen hat.
  int? checkout(int player) => winner == player ? turnPoints(currentTurn) : null;

  /// Geworfene Darts eines Spielers.
  int dartsThrown(int player) => turnsOf(player).fold(0, (sum, t) => sum + t.dartCount);
}
