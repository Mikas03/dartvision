import 'package:dartvision_app/models/hit.dart';
import 'package:dartvision_app/models/x01_game.dart';
import 'package:flutter_test/flutter_test.dart';

List<ThrowResult> throwAll(X01Game game, List<Hit> hits) => [for (final h in hits) game.throwDart(h)];

void main() {
  test('normale Aufnahme', () {
    final game = X01Game(players: ['A', 'B']);
    expect(throwAll(game, [const Hit.triple(20), const Hit.triple(20), const Hit.triple(20)]),
        [ThrowResult.ok, ThrowResult.ok, ThrowResult.turnOver]);
    expect(game.remaining(0), 321);
    expect(game.currentPlayer, 1);
    expect(game.average(0), 180);
  });

  test('Bust über null', () {
    final game = X01Game(players: ['A'], startScore: 40);
    expect(game.throwDart(const Hit.triple(20)), ThrowResult.bust);
    expect(game.remaining(0), 40);
  });

  test('Bust bei Rest 1 mit Double Out', () {
    final game = X01Game(players: ['A'], startScore: 21);
    expect(game.throwDart(const Hit.single(20)), ThrowResult.bust);
  });

  test('Checkout braucht ein Doppel', () {
    final game = X01Game(players: ['A'], startScore: 40);
    expect(throwAll(game, [const Hit.single(20), const Hit.single(20)]), [ThrowResult.ok, ThrowResult.bust]);
    expect(game.throwDart(const Hit.double(20)), ThrowResult.win);
    expect(game.winner, 0);
  });

  test('Single Out', () {
    final game = X01Game(players: ['A'], startScore: 20, doubleOut: false);
    expect(game.throwDart(const Hit.single(20)), ThrowResult.win);
  });

  test('Rückgängig über Aufnahmen hinweg', () {
    final game = X01Game(players: ['A', 'B']);
    throwAll(game, [const Hit.triple(20), const Hit.triple(20), const Hit.triple(20)]);
    expect(game.currentPlayer, 1);

    game.undo();
    expect(game.currentPlayer, 0);
    expect(game.currentTurn.darts, [const Hit.triple(20), const Hit.triple(20)]);
    expect(game.displayRemaining(0), 381);

    game.throwDart(const Hit.single(1));
    expect(game.remaining(0), 380);
  });

  test('Rückgängig nach Sieg', () {
    final game = X01Game(players: ['A'], startScore: 40);
    game.throwDart(const Hit.double(20));
    expect(game.isOver, isTrue);
    game.undo();
    expect(game.isOver, isFalse);
    expect(game.displayRemaining(0), 40);
  });

  test('Rückgängig nach Bust stellt den Stand wieder her', () {
    final game = X01Game(players: ['A'], startScore: 40);
    game.throwDart(const Hit.triple(20));
    game.undo();
    expect(game.currentTurn.darts, isEmpty);
    expect(game.currentTurn.bust, isFalse);
    expect(game.canUndo, isFalse);
  });

  group('Korrigieren', () {
    test('Dart in der laufenden Aufnahme', () {
      final game = X01Game(players: ['A', 'B']);
      throwAll(game, [const Hit.triple(20), const Hit.single(5)]);
      game.correctDart(0, const Hit.single(20));
      expect(game.currentTurn.darts, [const Hit.single(20), const Hit.single(5)]);
      expect(game.displayRemaining(0), 476);
    });

    test('letzter Dart, nachdem schon der nächste Spieler dran ist', () {
      final game = X01Game(players: ['A', 'B']);
      throwAll(game, [const Hit.triple(20), const Hit.triple(20), const Hit.triple(5)]);
      expect(game.currentPlayer, 1);
      expect(game.correctableTurn!.player, 0);

      game.correctDart(2, const Hit.triple(20));
      expect(game.remaining(0), 321);
      expect(game.currentPlayer, 1);
      expect(game.currentTurn.darts, isEmpty);
    });

    test('Korrektur macht aus einem Bust einen gültigen Wurf', () {
      final game = X01Game(players: ['A', 'B'], startScore: 40);
      game.throwDart(const Hit.triple(20)); // Bust
      expect(game.currentPlayer, 1);
      game.correctDart(0, const Hit.single(20));
      expect(game.currentPlayer, 0);
      expect(game.displayRemaining(0), 20);
    });

    test('Korrektur zum Checkout beendet das Spiel', () {
      final game = X01Game(players: ['A', 'B'], startScore: 40);
      game.throwDart(const Hit.single(20));
      game.correctDart(0, const Hit.double(20));
      expect(game.winner, 0);
    });

    test('vorzeitig beendete Aufnahme bleibt beendet', () {
      final game = X01Game(players: ['A', 'B']);
      game.throwDart(const Hit.triple(19));
      game.nextPlayer(); // Darts gezogen, Rest daneben
      game.correctDart(0, const Hit.triple(20));
      expect(game.remaining(0), 441);
      expect(game.currentPlayer, 1);
    });

    test('mittlerer Dart, spätere Darts werden neu verrechnet', () {
      final game = X01Game(players: ['A'], startScore: 100);
      throwAll(game, [const Hit.single(20), const Hit.triple(20)]); // Rest 20
      game.correctDart(0, const Hit.triple(20)); // 60 + 60 > 100 -> Bust
      expect(game.turns.first.bust, isTrue);
      expect(game.remaining(0), 100);
    });
  });

  group('Gesamtpunktzahl', () {
    test('normale Aufnahme', () {
      final game = X01Game(players: ['A', 'B']);
      expect(game.enterTurnTotal(100), ThrowResult.turnOver);
      expect(game.remaining(0), 401);
      expect(game.currentPlayer, 1);
      expect(game.average(0), 100);
    });

    test('unmögliche Summen werden abgelehnt', () {
      final game = X01Game(players: ['A']);
      for (final score in [179, 163, 181, -1]) {
        expect(() => game.enterTurnTotal(score), throwsArgumentError, reason: '$score');
      }
      expect(game.remaining(0), 501);
      expect(game.currentTurn.isTotal, isFalse);
    });

    test('Bust bei zu viel oder Rest 1', () {
      final game = X01Game(players: ['A'], startScore: 60);
      expect(game.enterTurnTotal(81), ThrowResult.bust);
      expect(game.remaining(0), 60);
      expect(game.enterTurnTotal(59), ThrowResult.bust);
      expect(game.remaining(0), 60);
    });

    test('Checkout mit Anzahl Darts für den Average', () {
      final game = X01Game(players: ['A'], startScore: 141);
      game.enterTurnTotal(100); // Rest 41
      expect(game.enterTurnTotal(41, darts: 2), ThrowResult.win);
      expect(game.winner, 0);
      expect(game.average(0), closeTo(141 / 5 * 3, 1e-9));
    });

    test('Checkout, der so nicht geht, wird abgelehnt', () {
      final game = X01Game(players: ['A'], startScore: 41);
      expect(() => game.enterTurnTotal(41, darts: 1), throwsArgumentError);
      expect(game.isOver, isFalse);
      expect(game.currentTurn.isTotal, isFalse);

      final bogey = X01Game(players: ['A'], startScore: 169);
      // 169 ist mit drei Darts möglich (z. B. T20 T19 Bull) – aber nicht auf ein Doppel endend
      expect(() => bogey.enterTurnTotal(169), throwsArgumentError);
    });

    test('Rückgängig nimmt die ganze Summe zurück', () {
      final game = X01Game(players: ['A', 'B']);
      game.enterTurnTotal(60);
      game.undo();
      expect(game.currentPlayer, 0);
      expect(game.currentTurn.isTotal, isFalse);
      expect(game.remaining(0), 501);
      expect(game.canUndo, isFalse);
    });

    test('gemischt mit einzelnen Darts', () {
      final game = X01Game(players: ['A', 'B']);
      game.enterTurnTotal(60);
      throwAll(game, [const Hit.triple(20), const Hit.triple(20), const Hit.triple(20)]);
      expect(game.remaining(0), 441);
      expect(game.remaining(1), 321);
      expect(() => game.correctDart(0, const Hit.single(1)), returnsNormally);
      expect(game.remaining(1), 380); // 1 + 60 + 60
    });
  });
}
