import 'package:dartvision_app/models/checkout.dart';
import 'package:dartvision_app/models/hit.dart';
import 'package:flutter_test/flutter_test.dart';

String? way(int rest, {int darts = 3, bool doubleOut = true}) =>
    suggestCheckout(rest, darts: darts, doubleOut: doubleOut)?.join(' ');

void main() {
  test('bekannte Checkouts', () {
    expect(way(170), 'T20 T20 Bull');
    expect(way(100), 'T20 D20');
    expect(way(50), 'Bull');
    expect(way(40), 'D20');
    expect(way(41), '9 D16');
    expect(way(2), 'D1');
  });

  test('nicht checkbare Zahlen', () {
    for (final rest in [169, 168, 166, 165, 163, 162, 159, 1, 0, 171]) {
      expect(way(rest), isNull, reason: '$rest');
    }
  });

  test('weniger Darts übrig', () {
    expect(way(100, darts: 1), isNull);
    expect(way(100, darts: 2), 'T20 D20');
    expect(way(32, darts: 1), 'D16');
  });

  test('jeder Weg ergibt genau den Rest und endet auf einem Doppel', () {
    for (var rest = 2; rest <= 170; rest++) {
      final hits = suggestCheckout(rest);
      if (hits == null) continue;
      expect(hits.fold<int>(0, (s, h) => s + h.value), rest);
      expect(hits.last.isDouble, isTrue);
      expect(hits.length, lessThanOrEqualTo(3));
    }
  });

  test('Single Out darf auf allem enden', () {
    expect(suggestCheckout(57, darts: 1, doubleOut: false), [const Hit.triple(19)]);
  });

  test('mögliche Summen einer Aufnahme', () {
    for (final s in [0, 1, 26, 60, 100, 140, 170, 177, 180]) {
      expect(isPossibleScore(s), isTrue, reason: '$s');
    }
    for (final s in [163, 166, 169, 172, 173, 175, 176, 178, 179, 181, -1]) {
      expect(isPossibleScore(s), isFalse, reason: '$s');
    }
  });
}
