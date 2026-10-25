import 'package:dartvision_app/data/storage.dart';
import 'package:dartvision_app/models/hit.dart';
import 'package:dartvision_app/models/match.dart';
import 'package:dartvision_app/online/online_session.dart';
import 'package:dartvision_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online-Sitzung ohne Server: merkt sich, was gesendet würde.
class FakeSession extends OnlineSession {
  FakeSession({required super.myPlayer}) : super.offline();

  final List<Match> pushed = [];

  @override
  Future<void> push(Match match) async {
    version++;
    pushed.add(Match.fromJson(match.toJson()));
  }
}

Match newMatch() => Match(
      settings: const MatchSettings(startScore: 301),
      players: const [MatchPlayer(name: 'Anna', profileId: 'acc:a'), MatchPlayer(name: 'Ben', profileId: 'acc:b')],
      id: 'online-test',
    );

void main() {
  testWidgets('Online: nur wer am Zug ist, wirft – Würfe des Gegners kommen über den Server', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    LocalStore.resetForTests();

    final session = FakeSession(myPlayer: 1); // ich bin Ben (Gast)
    await tester.pumpWidget(MaterialApp(home: GameScreen(match: newMatch(), online: session)));
    await tester.pumpAndSettle();

    // Anna ist dran: meine Eingaben zählen nicht
    expect(find.text('Anna wirft …'), findsOneWidget);
    await tester.tap(find.text('20').last);
    await tester.pump();
    expect(session.pushed, isEmpty);

    // Anna wirft auf ihrem Gerät, der neue Stand kommt an
    final remote = newMatch();
    for (final h in ['T20', 'T20', 'T20']) {
      remote.leg.throwDart(Hit.parse(h));
    }
    session.onRemoteState!(remote);
    await tester.pumpAndSettle();
    expect(find.text('121'), findsOneWidget); // Annas Rest

    // Jetzt bin ich dran: mein Wurf wird an den Server geschickt
    await tester.tap(find.text('20').last);
    await tester.pump();
    expect(session.pushed.length, 1);
    expect(session.pushed.last.leg.currentTurn.darts, [const Hit.single(20)]);

    // Annas Würfe kann ich nicht zurücknehmen, meinen eigenen schon
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pump();
    expect(session.pushed.length, 2);
    expect(session.pushed.last.leg.currentTurn.darts, isEmpty);
    expect(session.pushed.last.leg.lastTurn(0)!.darts.length, 3);
  });
}
