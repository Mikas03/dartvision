import 'hit.dart';

const dartsPerTurn = 3;

/// Wie Würfe eingegeben werden.
enum InputMode {
  /// Jeder Dart einzeln (Feld und Multiplikator) – auch so arbeitet die Kamera.
  perDart,

  /// Nur die Summe der Aufnahme, z. B. 100 (nur bei X01).
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

  /// Summe der geworfenen Punkte (unabhängig davon, was der Modus daraus macht).
  int get thrown => total ?? darts.fold(0, (sum, h) => sum + h.value);

  /// Punkte, die bei Bust nicht zählen.
  int get scored => bust ? 0 : thrown;

  /// Anzahl geworfener Darts (für Statistiken).
  int get dartCount => isTotal ? totalDarts : darts.length;

  Map<String, Object> toJson() => {
        'p': player,
        if (darts.isNotEmpty) 'd': [for (final d in darts) d.label],
        't': ?total,
        if (total != null && totalDarts != dartsPerTurn) 'n': totalDarts,
        if (bust) 'b': true,
        if (finished) 'f': true,
      };
}

enum ThrowResult { ok, bust, turnOver, win }

/// Was ein einzelner Dart im jeweiligen Modus bewirkt.
enum DartOutcome {
  /// Zählt, die Aufnahme geht weiter.
  ok,

  /// Überworfen: die Aufnahme zählt nicht und ist sofort vorbei.
  bust,

  /// Die Aufnahme ist sofort vorbei (z. B. Checkout-Training geschafft), ohne Sieg.
  endTurn,

  /// Der Spieler hat das Spiel (Leg) gewonnen.
  win,
}

/// Gemeinsame Grundlage aller Spielmodi: Aufnahmen à 3 Darts, Spielerwechsel, Rückgängig und
/// Korrektur einzelner Darts. Der Spielstand ergibt sich komplett aus der Liste der Aufnahmen –
/// genau diese Liste wird für Historie und später fürs Online-Spiel gespeichert.
///
/// Ein Modus implementiert [evaluateDart] (was bewirkt ein Dart?), optional [winnerAfterTurn]
/// (Spielende nach Runden) und [botTarget] (worauf zielt der Dartbot?).
abstract class DartGame {
  DartGame({required List<String> players, this.startingPlayer = 0}) : players = List.unmodifiable(players) {
    if (players.isEmpty) throw ArgumentError('Mindestens ein Spieler nötig');
    _turns.add(Turn(startingPlayer % players.length));
  }

  final List<String> players;

  /// Wer das Leg anwirft (wechselt von Leg zu Leg).
  final int startingPlayer;

  final List<Turn> _turns = [];
  int? _winner;

  /// Kurzer Name des Modus, z. B. "501" oder "Cricket".
  String get title;

  /// Zusatzinfo zum Modus, z. B. "Double Out".
  String? get subtitle => null;

  List<Turn> get turns => List.unmodifiable(_turns);
  Turn get currentTurn => _turns.last;
  int get currentPlayer => currentTurn.player;
  int? get winner => _winner;
  bool get isOver => _winner != null;
  int get dartsLeftInTurn => dartsPerTurn - currentTurn.darts.length;

  /// Abgeschlossene Aufnahmen eines Spielers.
  Iterable<Turn> finishedTurnsOf(int player) => _turns.where((t) => t.player == player && t.finished);

  /// Alle Aufnahmen eines Spielers inklusive der laufenden.
  Iterable<Turn> turnsOf(int player) => _turns.where((t) => t.player == player);

  /// Anzahl abgeschlossener Runden eines Spielers.
  int roundsPlayed(int player) => finishedTurnsOf(player).length;

  /// Letzte abgeschlossene Aufnahme eines Spielers.
  Turn? lastTurn(int player) {
    for (final t in _turns.reversed) {
      if (t.player == player && t.finished) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------- Regeln (pro Modus)

  /// Bewertet [hit], der bereits in [turn] eingetragen ist.
  DartOutcome evaluateDart(Turn turn, Hit hit);

  /// Wird nach jeder abgeschlossenen Aufnahme aufgerufen; liefert den Sieger, wenn das Spiel
  /// dadurch endet (z. B. nach der letzten Runde bei Shanghai), sonst null.
  int? winnerAfterTurn(Turn turn) => null;

  /// Ob ein Spieler noch mitspielt (bei Bob's 27 scheidet man aus).
  bool isActive(int player) => true;

  /// Worauf der Dartbot als nächstes zielt.
  Hit botTarget();

  /// Punkte/Wert einer Aufnahme für die Anzeige, z. B. "100", "5 Marks" oder "Treffer".
  String turnLabel(Turn turn) => '${turn.scored}';

  /// Hinweiszeile unter der Aufnahme, z. B. Checkout-Weg oder aktuelles Ziel.
  String? get hint => null;

  // ---------------------------------------------------------------- Ablauf

  ThrowResult throwDart(Hit hit) {
    if (isOver) throw StateError('Spiel ist bereits beendet');
    if (currentTurn.isTotal) throw StateError('Für diese Aufnahme wurde bereits eine Summe eingegeben');

    final turn = currentTurn..darts.add(hit);
    switch (evaluateDart(turn, hit)) {
      case DartOutcome.bust:
        finishTurn(bust: true);
        return ThrowResult.bust;
      case DartOutcome.win:
        turn.finished = true;
        _winner = turn.player;
        return ThrowResult.win;
      case DartOutcome.endTurn:
        finishTurn();
        return isOver ? ThrowResult.win : ThrowResult.turnOver;
      case DartOutcome.ok:
        if (turn.darts.length == dartsPerTurn) {
          finishTurn();
          return isOver ? ThrowResult.win : ThrowResult.turnOver;
        }
        return ThrowResult.ok;
    }
  }

  /// Aufnahme vorzeitig beenden, z. B. wenn Darts danebengingen und nicht erkannt wurden.
  void nextPlayer() {
    if (!isOver) finishTurn();
  }

  bool get canUndo => _turns.length > 1 || currentTurn.darts.isNotEmpty || currentTurn.isTotal;

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

  /// Schließt die laufende Aufnahme ab und gibt an den nächsten aktiven Spieler weiter.
  void finishTurn({bool bust = false}) {
    final turn = currentTurn
      ..bust = bust
      ..finished = true;
    final winner = winnerAfterTurn(turn);
    if (winner != null) {
      _winner = winner;
      return;
    }
    var next = turn.player;
    for (var i = 0; i < players.length; i++) {
      next = (next + 1) % players.length;
      if (isActive(next)) break;
    }
    _turns.add(Turn(next));
  }

  /// Für Modi mit Summeneingabe: trägt die laufende Aufnahme als Summe ein.
  void setTotal(int score, int darts) {
    currentTurn
      ..total = score
      ..totalDarts = darts;
  }

  /// Markiert den aktuellen Spieler als Sieger (z. B. Checkout per Summeneingabe).
  void declareWinner() {
    currentTurn.finished = true;
    _winner = currentPlayer;
  }

  /// Verlauf als JSON (für Historie und Online-Spiel).
  List<Map<String, Object>> turnsToJson() => [for (final t in _turns) t.toJson()];

  /// Spielt einen gespeicherten Verlauf nach (z. B. aus der Historie).
  void replay(List<dynamic> turnsJson) {
    for (final raw in turnsJson.cast<Map<String, dynamic>>()) {
      if (isOver) break;
      final total = raw['t'] as int?;
      if (total != null) {
        replayTotal(total, raw['n'] as int? ?? dartsPerTurn);
        continue;
      }
      for (final label in (raw['d'] as List? ?? const []).cast<String>()) {
        if (isOver || currentTurn.finished) break;
        throwDart(Hit.parse(label));
      }
      final finished = raw['f'] == true;
      if (finished && !isOver && currentTurn.darts.isNotEmpty && currentTurn.player == raw['p']) {
        nextPlayer(); // vorzeitig beendete Aufnahme
      }
    }
  }

  /// Nachspielen einer Summeneingabe; nur X01 unterstützt das.
  void replayTotal(int total, int darts) => throw UnsupportedError('Summeneingabe gibt es nur bei X01');
}
