import 'hit.dart';

const dartsPerTurn = 3;

/// Eine Aufnahme (bis zu 3 Darts) eines Spielers.
class Turn {
  Turn(this.player);

  final int player;
  final List<Hit> darts = [];
  bool bust = false;
  bool finished = false;

  int get thrown => darts.fold(0, (sum, h) => sum + h.value);

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
    final darts = own.fold(0, (sum, t) => sum + t.darts.length);
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

  /// Aufnahme vorzeitig beenden, z. B. wenn Darts nicht gezählt werden sollen.
  void nextPlayer() {
    if (!isOver) _finishTurn();
  }

  bool get canUndo => _turns.length > 1 || currentTurn.darts.isNotEmpty;

  /// Nimmt den letzten Dart zurück, auch aus einer bereits beendeten Aufnahme.
  void undo() {
    if (!canUndo) return;
    if (currentTurn.darts.isEmpty && !currentTurn.finished) {
      _turns.removeLast();
    }
    _winner = null;
    final turn = currentTurn
      ..finished = false
      ..bust = false;
    if (turn.darts.isNotEmpty) turn.darts.removeLast();
  }

  /// Aufnahme, deren Darts angezeigt und korrigiert werden können: die laufende,
  /// oder – solange darin noch kein Dart ist – die vorige.
  Turn? get correctableTurn {
    if (currentTurn.darts.isNotEmpty) return currentTurn;
    if (_turns.length > 1) return _turns[_turns.length - 2];
    return null;
  }

  /// Ersetzt Dart Nr. [index] der [correctableTurn] durch [hit] und rechnet alles danach neu
  /// (z. B. wenn die Kamera ein Feld falsch erkannt hat).
  void correctDart(int index, Hit hit) {
    final turn = correctableTurn;
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
