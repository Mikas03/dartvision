import 'package:dartvision_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Spiel starten und eine Triple 20 eintragen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DartApp());
    await tester.tap(find.text('Spiel starten'));
    await tester.pumpAndSettle();

    expect(find.text('501'), findsNWidgets(2));

    await tester.tap(find.text('Triple'));
    await tester.pump();
    await tester.tap(find.text('20'));
    await tester.pump();

    expect(find.text('441'), findsOneWidget);
    expect(find.text('T20'), findsOneWidget);
  });
}
