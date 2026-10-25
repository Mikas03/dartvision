import 'hit.dart';

/// Reihenfolge, in der Doppel zum Auschecken bevorzugt werden.
const _preferredDoubles = [16, 20, 8, 18, 12, 10, 4, 14, 6, 2, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1];

final List<Hit> _finishingDoubles = [
  for (final d in _preferredDoubles) Hit.double(d),
  Hit.bull,
];

/// Würfe zum Stellen: Singles zuerst (sicherer), dann Triples von hoch nach niedrig, dann Bull.
final List<Hit> _setupHits = [
  for (var s = 20; s >= 1; s--) Hit.single(s),
  for (var s = 20; s >= 1; s--) Hit.triple(s),
  Hit.outerBull,
  Hit.bull,
];

/// Für 3-Dart-Wege beginnt man mit dem höchsten Wurf.
final List<Hit> _openingHits = [
  for (var s = 20; s >= 1; s--) Hit.triple(s),
  Hit.bull,
  Hit.outerBull,
  for (var s = 20; s >= 1; s--) Hit.single(s),
];

/// Schlägt einen Checkout-Weg mit möglichst wenigen Darts vor, oder null, wenn keiner möglich ist.
List<Hit>? suggestCheckout(int rest, {int darts = 3, bool doubleOut = true}) {
  if (rest <= 0 || darts <= 0) return null;
  final finishes = doubleOut ? _finishingDoubles : [..._openingHits];

  for (final f in finishes) {
    if (f.value == rest) return [f];
  }
  if (darts >= 2) {
    final two = _twoDarts(rest, finishes);
    if (two != null) return two;
  }
  if (darts >= 3) {
    for (final first in _openingHits) {
      final two = _twoDarts(rest - first.value, finishes);
      if (two != null) return [first, ...two];
    }
  }
  return null;
}

List<Hit>? _twoDarts(int rest, List<Hit> finishes) {
  if (rest <= 0) return null;
  for (final f in finishes) {
    for (final setup in _setupHits) {
      if (setup.value + f.value == rest) return [setup, f];
    }
  }
  return null;
}

/// Alle Summen, die man mit höchstens drei Darts werfen kann (0 bis 180, aber z. B. nicht 179).
final Set<int> _possibleScores = () {
  final values = {0, for (var s = 1; s <= 20; s++) ...[s, 2 * s, 3 * s], 25, 50};
  return {
    for (final a in values)
      for (final b in values)
        for (final c in values) a + b + c,
  };
}();

/// Ob man [score] mit höchstens drei Darts werfen kann.
bool isPossibleScore(int score) => _possibleScores.contains(score);
