import 'package:dartvision_app/data/storage.dart';
import 'package:dartvision_app/main.dart';
import 'package:dartvision_app/widgets/scoreboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> startApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  LocalStore.resetForTests();
  await tester.pumpWidget(const DartApp());
  await tester.pumpAndSettle();
}

/// Text innerhalb der Punktetafel (der Titel zeigt z. B. auch "501").
Finder score(String text) => find.descendant(of: find.byType(Scoreboard), matching: find.text(text));

/// Auf dem Startbildschirm (lange Liste) erst hinscrollen, dann tippen.
Future<void> tapInSetup(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> tapAll(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('Spiel starten und eine Triple 20 eintragen', (tester) async {
    await startApp(tester);
    await tapInSetup(tester, 'Spiel starten');

    expect(score('501'), findsNWidgets(2));

    await tapAll(tester, ['Triple', '20']);

    expect(score('441'), findsOneWidget);
    expect(find.text('T20'), findsOneWidget);
  });

  testWidgets('Gesamtpunktzahl eingeben', (tester) async {
    await startApp(tester);
    await tapInSetup(tester, 'Gesamtpunktzahl');
    await tapInSetup(tester, 'Spiel starten');

    // Spieler 1 tippt 1-0-0 und OK
    await tapAll(tester, ['1', '0', '0', 'OK']);
    expect(score('401'), findsOneWidget);
    expect(find.text('Spieler 1: 100'), findsOneWidget);

    // Spieler 2 nimmt die Schnelltaste 180
    await tapAll(tester, ['180']);
    expect(score('321'), findsOneWidget);
    expect(find.text('Hundertachtzig!'), findsOneWidget);

    // 179 geht mit drei Darts nicht
    await tapAll(tester, ['1', '7', '9', 'OK']);
    expect(find.text('179 kann man mit drei Darts nicht werfen'), findsOneWidget);
    expect(score('401'), findsOneWidget);
  });

  testWidgets('Eingabeart wird gemerkt', (tester) async {
    await startApp(tester);
    await tapInSetup(tester, 'Gesamtpunktzahl');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('input_mode'), 'turnTotal');
  });
}
