import 'package:dartvision_app/data/storage.dart';
import 'package:dartvision_app/models/match.dart';
import 'package:dartvision_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpGame(WidgetTester tester, Match match) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  LocalStore.resetForTests();
  await tester.pumpWidget(MaterialApp(home: GameScreen(match: match)));
  await tester.pumpAndSettle();
}

Future<void> tapAll(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    await tester.tap(find.text(label).last);
    await tester.pump();
  }
}

void main() {
  testWidgets('Der Bot wirft von selbst, danach ist wieder der Mensch dran', (tester) async {
    final match = Match(
      settings: const MatchSettings(),
      players: [const MatchPlayer(name: 'Ich'), MatchPlayer.bot(10)],
    );
    await pumpGame(tester, match);

    await tapAll(tester, ['Triple', '20', 'Triple', '20', 'Triple', '20']);
    expect(match.leg.currentPlayer, 1);
    expect(find.text('Hundertachtzig!'), findsOneWidget); // erst die eigene Punktzahl

    // Eingaben sind während des Bot-Zugs gesperrt
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(match.leg.currentTurn.darts, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(match.leg.currentTurn.darts.length, 1);
    expect(find.text('Bot 10 wirft …'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(match.leg.currentPlayer, 0);
    expect(match.leg.lastTurn(1)!.darts.length, 3);
    await tester.pumpAndSettle();
  });

  testWidgets('Rückgängig nimmt den Bot-Zug mit zurück', (tester) async {
    final match = Match(
      settings: const MatchSettings(),
      players: [const MatchPlayer(name: 'Ich'), MatchPlayer.bot(3)],
    );
    await pumpGame(tester, match);
    await tapAll(tester, ['20', '20', '20']);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(match.leg.currentPlayer, 0);

    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pump();
    // Bot-Aufnahme komplett weg, mein dritter Dart auch
    expect(match.leg.currentPlayer, 0);
    expect(match.leg.currentTurn.darts.length, 2);
    await tester.pumpAndSettle();
  });

  testWidgets('Beendetes Match landet in der Historie', (tester) async {
    final match = Match(
      settings: const MatchSettings(startScore: 40),
      players: const [MatchPlayer(name: 'A', profileId: 'p1')],
    );
    await pumpGame(tester, match);
    await tapAll(tester, ['Double', '20']);
    await tester.pumpAndSettle();
    expect(find.text('Fertig!'), findsOneWidget);

    await tester.tap(find.text('Revanche'));
    await tester.pumpAndSettle();
    final history = (await LocalStore.instance()).history;
    expect(history.length, 1);
    expect(history.first.players.first.profileId, 'p1');
    expect(history.first.restore().winner, 0);
  });

  testWidgets('Cricket zeigt die Marks-Tabelle', (tester) async {
    final match = Match(
      settings: const MatchSettings(mode: GameMode.cricket),
      players: const [MatchPlayer(name: 'A'), MatchPlayer(name: 'B')],
    );
    await pumpGame(tester, match);
    await tapAll(tester, ['Triple', '20', 'Triple', '20']);
    expect(find.text('Ⓧ'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // Punkte von A
    expect(find.textContaining('Offen: 19'), findsOneWidget);
  });
}
