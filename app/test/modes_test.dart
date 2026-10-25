import 'dart:convert';
import 'dart:math' as math;

import 'package:dartvision_app/models/board.dart';
import 'package:dartvision_app/models/bot.dart';
import 'package:dartvision_app/models/cricket_game.dart';
import 'package:dartvision_app/models/hit.dart';
import 'package:dartvision_app/models/match.dart';
import 'package:dartvision_app/models/practice_games.dart';
import 'package:dartvision_app/models/x01_game.dart';
import 'package:flutter_test/flutter_test.dart';

void throwAll(DartGame game, List<String> labels) {
  for (final l in labels) {
    game.throwDart(Hit.parse(l));
  }
}

void main() {
  test('Hit.parse ist die Umkehrung von label', () {
    for (final h in [Hit.miss, Hit.bull, Hit.outerBull, const Hit.triple(20), const Hit.double(7), const Hit.single(1)]) {
      expect(Hit.parse(h.label), h);
    }
    expect(() => Hit.parse('T21'), throwsFormatException);
  });

  group('X01-Optionen', () {
    test('Double In: Punkte zählen erst ab dem ersten Doppel', () {
      final game = X01Game(players: ['A'], doubleIn: true);
      throwAll(game, ['T20', 'D10', 'T20']);
      expect(game.remaining(0), 501 - 20 - 60);
    });

    test('Double In: ohne Doppel zählt die Aufnahme nicht', () {
      final game = X01Game(players: ['A'], doubleIn: true);
      throwAll(game, ['T20', 'T20', 'T20']);
      expect(game.remaining(0), 501);
      throwAll(game, ['5']); // immer noch nicht drin
      expect(game.displayRemaining(0), 501);
    });

    test('Master Out erlaubt Triple zum Beenden', () {
      final game = X01Game(players: ['A'], startScore: 60, masterOut: true);
      expect(game.throwDart(const Hit.triple(20)), ThrowResult.win);
    });
  });

  group('Cricket', () {
    test('Schließen und Punkte', () {
      final game = CricketGame(players: ['A', 'B']);
      throwAll(game, ['T20', 'T20', '19']); // A: 20 zu + 60 Punkte, 19 einmal
      expect(game.marks[0][20], 3);
      expect(game.points[0], 60);
      expect(game.marks[0][19], 1);
      throwAll(game, ['T20', 'T20', 'Miss']); // B schließt die 20; A hat sie auch zu -> keine Punkte
      expect(game.points[1], 0);
    });

    test('Gewinnen: alles zu und nicht weniger Punkte', () {
      final game = CricketGame(players: ['A']);
      throwAll(game, ['T20', 'T19', 'T18', 'T17', 'T16', 'T15', 'Bull', '25']);
      expect(game.winner, 0);
    });

    test('Cut-Throat: Punkte gehen an den Gegner', () {
      final game = CricketGame(players: ['A', 'B'], cutThroat: true);
      throwAll(game, ['T20', 'T20', 'Miss']);
      expect(game.points[1], 60);
      expect(game.points[0], 0);
    });

    test('Bot zielt auf die höchste offene Zahl', () {
      final game = CricketGame(players: ['A']);
      expect(game.botTarget(), const Hit.triple(20));
      throwAll(game, ['T20']);
      expect(game.botTarget(), const Hit.triple(19));
    });
  });

  group('Around the Clock', () {
    test('Reihenfolge, beliebiger Ring zählt', () {
      final game = AroundTheClockGame(players: ['A']);
      throwAll(game, ['1', 'D2', '5', 'T3']);
      expect(game.target(0), 4);
    });

    test('Mehrfach zählt, aber Bull muss man selbst treffen', () {
      final game = AroundTheClockGame(players: ['A'], multiplesCount: true);
      throwAll(game, ['T1']); // -> 4
      expect(game.target(0), 4);
      final late = AroundTheClockGame(players: ['A'], multiplesCount: true);
      for (var i = 1; i <= 18; i++) {
        late.throwDart(Hit.single(i));
      }
      late.throwDart(const Hit.triple(19)); // zählt 19 und 20, weiter geht es nicht
      expect(late.target(0), 25);
      expect(late.isOver, isFalse);
      throwAll(late, ['Bull']);
      expect(late.winner, 0);
    });
  });

  group('Shanghai', () {
    test('Shanghai gewinnt sofort', () {
      final game = ShanghaiGame(players: ['A', 'B']);
      throwAll(game, ['1', 'D1', 'T1']);
      expect(game.winner, 0);
    });

    test('Nach 7 Runden gewinnt die höchste Punktzahl', () {
      final game = ShanghaiGame(players: ['A', 'B']);
      for (var round = 1; round <= 7; round++) {
        throwAll(game, ['T$round', 'Miss', 'Miss']); // A
        throwAll(game, ['$round', 'Miss', 'Miss']); // B
      }
      expect(game.winner, 0);
      expect(game.score(0), 3 * 28);
    });
  });

  group("Bob's 27", () {
    test('Treffer addieren, Fehlrunden ziehen ab', () {
      final game = Bobs27Game(players: ['A']);
      throwAll(game, ['D1', 'D1', 'Miss']); // +4
      expect(game.score(0), 31);
      throwAll(game, ['Miss', 'Miss', 'Miss']); // -4 (D2)
      expect(game.score(0), 27);
      expect(game.currentTarget, 3);
    });

    test('Wer auf 0 fällt, ist raus', () {
      final game = Bobs27Game(players: ['A']);
      for (var i = 0; i < 5; i++) {
        throwAll(game, ['Miss', 'Miss', 'Miss']); // 27 - 2 - 4 - 6 - 8 - 10 < 0
        if (game.isOver) break;
      }
      expect(game.isOver, isTrue);
      expect(game.score(0), lessThanOrEqualTo(0));
    });
  });

  group('Checkout-Training', () {
    test('gleiche Aufgaben mit gleichem Seed, Erfolg zählt', () {
      final a = CheckoutTrainingGame(players: ['A'], seed: 42, rounds: 3);
      final b = CheckoutTrainingGame(players: ['A'], seed: 42, rounds: 3);
      expect(a.targets, b.targets);

      final game = CheckoutTrainingGame(players: ['A'], seed: 42, rounds: 3);
      // Ersten Rest mit dem vorgeschlagenen Weg auschecken
      while (game.roundsPlayed(0) == 0) {
        game.throwDart(game.botTarget());
      }
      expect(game.successes(0), 1);
    });
  });

  group('Match', () {
    test('Best of 3 mit wechselndem Anwurf', () {
      final match = Match(
        settings: const MatchSettings(startScore: 40, bestOf: 3),
        players: const [MatchPlayer(name: 'A'), MatchPlayer(name: 'B')],
      );
      expect(match.leg.currentPlayer, 0);
      match.leg.throwDart(const Hit.double(20)); // A gewinnt Leg 1
      expect(match.legOver, isTrue);
      match.startNextLeg();
      expect(match.leg.currentPlayer, 1); // B wirft an
      match.leg.throwDart(const Hit.double(20)); // B gewinnt Leg 2
      match.startNextLeg();
      match.leg.throwDart(const Hit.double(20)); // A wirft an und gewinnt
      expect(match.legWins, [2, 1]);
      expect(match.winner, 0);
    });

    test('Rückgängig am Leg-Anfang geht ins vorige Leg zurück', () {
      final match = Match(
        settings: const MatchSettings(startScore: 40, bestOf: 3),
        players: const [MatchPlayer(name: 'A'), MatchPlayer(name: 'B')],
      );
      match.leg.throwDart(const Hit.double(20));
      match.startNextLeg();
      match.undo();
      expect(match.legs.length, 1);
      expect(match.leg.isOver, isFalse);
      expect(match.legWins, [0, 0]);
    });

    test('Speichern und Wiederherstellen ergibt denselben Stand', () {
      final match = Match(
        settings: const MatchSettings(mode: GameMode.x01, bestOf: 3),
        players: const [MatchPlayer(name: 'A', profileId: 'p1'), MatchPlayer(name: 'Bot', botLevel: 5)],
      );
      throwAll(match.leg, ['T20', 'T20', 'T20', '5', '1', 'Miss', 'T19']);
      match.leg.nextPlayer(); // vorzeitig beendet
      (match.leg as X01Game).enterTurnTotal(100);

      final restored = Match.fromJson(jsonDecode(jsonEncode(match.toJson())) as Map<String, dynamic>);
      final a = match.leg as X01Game, b = restored.leg as X01Game;
      expect(b.remaining(0), a.remaining(0));
      expect(b.remaining(1), a.remaining(1));
      expect(b.currentPlayer, a.currentPlayer);
      expect(restored.players[1].isBot, isTrue);
      expect(restored.players[0].profileId, 'p1');
      expect(restored.stats(), match.stats());
    });

    test('Checkout-Training: wiederhergestellt mit denselben Aufgaben', () {
      final match = Match(
        settings: const MatchSettings(mode: GameMode.checkoutTraining, trainingRounds: 5),
        players: const [MatchPlayer(name: 'A')],
      );
      final restored = Match.fromJson(jsonDecode(jsonEncode(match.toJson())) as Map<String, dynamic>);
      expect((restored.leg as CheckoutTrainingGame).targets, (match.leg as CheckoutTrainingGame).targets);
    });
  });

  group('Dartbot', () {
    test('Zielpunkte liegen im richtigen Feld', () {
      for (final target in [const Hit.triple(20), const Hit.double(16), const Hit.single(5), Hit.bull, Hit.outerBull]) {
        final p = DartBot.aimPoint(target);
        expect(scoreAt(p.dx, p.dy), target, reason: target.label);
      }
    });

    test('Stärkere Stufen werfen einen höheren Average', () {
      double average(int level) {
        final bot = DartBot(level, random: math.Random(7));
        var sum = 0;
        for (var i = 0; i < 3000; i++) {
          sum += bot.throwAt(const Hit.triple(20)).value;
        }
        return sum / 3000 * 3;
      }

      final low = average(1), high = average(10);
      expect(low, closeTo(DartBot.averageByLevel[0], 6));
      expect(high, closeTo(DartBot.averageByLevel[9], 10));
    });

    test('Bot spielt ein ganzes 501-Leg zu Ende', () {
      final bot = DartBot(8, random: math.Random(3));
      final game = X01Game(players: ['Bot']);
      var darts = 0;
      while (!game.isOver && darts < 500) {
        game.throwDart(bot.throwAt(game.botTarget()));
        darts++;
      }
      expect(game.isOver, isTrue);
    });
  });
}
