import 'checkout.dart';
import 'hit.dart';

const dartsPerTurn = 3;

/// Wie Würfe eingegeben werden.
enum InputMode {
  /// Jeder Dart einzeln (Feld und Multiplikator) – auch so arbeitet die Kamera.
  perDart,

  /// Nur die Summe der Aufnahme, z. B. 100.
  turnTotal,
}

/// Eine Aufnahme (bis zu 3 Darts) eines Spielers.
class Turn {
  Turn(this.player);

  final int player;
  final List<Hit> darts = [];
  bool bust = false;
  bool finished = false;

  /// Bei Eingabe der Gesamtpunktzahl: die Summe (die einzelnen Darts sind dann unbekannt).
  int? total;

  /// Bei Eingabe der Gesamtpunktzahl: wie viele Darts geworfen wurden (3, außer beim Checkout).
  int totalDarts = dartsPerTurn;

  bool get isTotal => total != null;

  int get thrown => total ?? darts.fold(0, (sum, h) => sum + h.value);

  /// Anzahl geworfener Darts (für den Average).
  int get dartCount => isTotal ? totalDarts : darts.length;

  /// Punkte, die tatsächlich abgezogen werden (bei Bust 0).
  int get scored => bust ? 0 : thrown;
}

enum ThrowResult { ok, bust, turnOver, win }

/// X01-Spiel (301, 501, ...). Der Spielstand wird komplett aus der Liste der Aufnahmen
/// berechnet, dadurch funktioniert Rückgängig auch über Aufnahmen hinweg.
class X01Game {
  X01Game({required List<String> players, this.startScore = 501, this.doubleOut = true})
      : players = List.unmodifiable(players) {
    if (players.isEmpty) throw ArgumentError('Mindestens ein Spieler nötig');
    _turns.add(Turn(0));
  }

  final List<String> players;
  final int startScore;
  final bool doubleOut;

  final List<Turn> _turns = [];
  int? _winner;

  List<Turn> get turns => List.unmodifiable(_turns);
  Turn get currentTurn => _turns.last;
  int get currentPlayer => currentTurn.player;
  int? get winner => _winner;
  bool get isOver => _winner != null;
  int get dartsLeftInTurn => dartsPerTurn - currentTurn.darts.length;

  /// Restpunkte vor der laufenden Aufnahme.
  int remaining(int player) =>
      startScore -
      _turns.where((t) => t.player == player && t.finished).fold(0, (sum, t) => sum + t.scored);

  /// Restpunkte inklusive der Darts der laufenden Aufnahme (für die Anzeige).
  int displayRemaining(int player) {
    if (player != currentPlayer || currentTurn.finished) return remaining(player);
    return remaining(player) - currentTurn.thrown;
  }

  /// 3-Dart-Average.
  double average(int player) {
    final own = _turns.where((t) => t.player == player);
    final darts = own.fold(0, (sum, t) => sum + t.dartCount);
    if (darts == 0) return 0;
    final points = own.fold(0, (sum, t) => sum + (t.finished ? t.scored : t.thrown));
    return points / darts * dartsPerTurn;
  }

  /// Letzte abgeschlossene Aufnahme eines Spielers.
  Turn? lastTurn(int player) {
    for (final t in _turns.reversed) {
      if (t.player == player && t.finished) return t;
    }
    return null;
  }

  ThrowResult throwDart(Hit hit) {
    if (isOver) throw StateError('Spiel ist bereits beendet');

    currentTurn.darts.add(hit);
    final rest = remaining(currentPlayer) - currentTurn.thrown;

    if (rest < 0 || (doubleOut && rest == 1) || (rest == 0 && doubleOut && !hit.isDouble)) {
      _finishTurn(bust: true);
      return ThrowResult.bust;
    }
    if (rest == 0) {
      currentTurn.finished = true;
      _winner = currentPlayer;
      return ThrowResult.win;
    }
    if (currentTurn.darts.length == dartsPerTurn) {
      _finishTurn();
      return ThrowResult.turnOver;
    }
    return ThrowResult.ok;
  }

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
    final turn = currentTurn
      ..total = score
      ..totalDarts = dartsPerTurn;
    if (rest < 0 || (doubleOut && rest == 1)) {
      _finishTurn(bust: true);
      return ThrowResult.bust;
    }
    if (rest == 0) {
      if (suggestCheckout(score, darts: darts, doubleOut: doubleOut) == null) {
        turn.total = null;
        throw ArgumentError(darts == dartsPerTurn
            ? '$score lässt sich nicht auschecken'
            : '$score lässt sich nicht mit $darts ${darts == 1 ? 'Dart' : 'Darts'} auschecken');
      }
      turn
        ..totalDarts = darts
        ..finished = true;
      _winner = currentPlayer;
      return ThrowResult.win;
    }
    _finishTurn();
    return ThrowResult.turnOver;
  }

  /// Aufnahme vorzeitig beenden, z. B. wenn Darts nicht gezählt werden sollen.
  void nextPlayer() {
    if (!isOver) _finishTurn();
  }

  bool get canUndo => _turns.length > 1 || currentTurn.darts.isNotEmpty;

  /// Nimmt den letzten Dart zurück (bzw. die zuletzt eingegebene Gesamtpunktzahl),
  /// auch aus einer bereits beendeten Aufnahme.
  void undo() {
    if (!canUndo) return;
    if (currentTurn.darts.isEmpty && !currentTurn.isTotal && !currentTurn.finished) {
      _turns.removeLast();
    }
    _winner = null;
    final turn = currentTurn
      ..finished = false
      ..bust = false;
    if (turn.isTotal) {
      turn.total = null;
    } else if (turn.darts.isNotEmpty) {
      turn.darts.removeLast();
    }
  }

  /// Aufnahme, deren Darts angezeigt und korrigiert werden können: die laufende,
  /// oder – solange darin noch kein Dart ist – die vorige.
  Turn? get correctableTurn {
    if (currentTurn.darts.isNotEmpty || currentTurn.isTotal) return currentTurn;
    if (_turns.length > 1) return _turns[_turns.length - 2];
    return null;
  }

  /// Ersetzt Dart Nr. [index] der [correctableTurn] durch [hit] und rechnet alles danach neu
  /// (z. B. wenn die Kamera ein Feld falsch erkannt hat).
  void correctDart(int index, Hit hit) {
    final turn = correctableTurn;
    if (turn != null && turn.isTotal) {
      throw StateError('Bei eingegebener Gesamtpunktzahl gibt es keine einzelnen Darts');
    }
    if (turn == null || index < 0 || index >= turn.darts.length) {
      throw RangeError('Kein Dart $index zum Korrigieren');
    }
    final later = turn.darts.sublist(index + 1);
    // Wurde die Aufnahme vorzeitig beendet (Darts gezogen), soll sie das danach wieder sein
    final endedEarly = turn.finished && !turn.bust && !isOver && turn.darts.length < dartsPerTurn;

    // Darts ab [index] zurücknehmen; das öffnet die Aufnahme bei Bedarf wieder
    while (turn.darts.length > index) {
      undo();
    }
    throwDart(hit);
    for (final h in later) {
      if (isOver || turn.finished || !identical(currentTurn, turn)) break;
      throwDart(h);
    }
    if (endedEarly && identical(currentTurn, turn) && !turn.finished) nextPlayer();
  }

  void _finishTurn({bool bust = false}) {
    currentTurn
      ..bust = bust
      ..finished = true;
    _turns.add(Turn((currentPlayer + 1) % players.length));
  }
}
