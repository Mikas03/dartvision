import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'board.dart';
import 'hit.dart';

/// Dartbot: zielt auf ein Feld und streut realistisch um den Zielpunkt. Getroffen wird, was an
/// der gestreuten Stelle auf der Scheibe liegt (gleiche Geometrie wie bei der Kamera).
///
/// Die Streuung pro Stufe ist so gewählt, dass der 3-Dart-Average beim Werfen auf T20 etwa
/// [averageByLevel] entspricht (per Simulation ermittelt).
class DartBot {
  DartBot(this.level, {math.Random? random})
      : assert(level >= 1 && level <= maxLevel),
        _random = random ?? math.Random();

  static const maxLevel = 10;

  /// Standardabweichung der Streuung in mm je Stufe (Stufe 1 = Index 0).
  static const _sigmaByLevel = [110.0, 75.0, 55.0, 42.0, 33.0, 26.0, 20.0, 15.5, 12.0, 9.0];

  /// Ungefährer 3-Dart-Average beim Werfen auf T20 je Stufe.
  static const averageByLevel = [21, 27, 32, 36, 39, 44, 51, 63, 78, 95];

  final int level;
  final math.Random _random;

  double get sigma => _sigmaByLevel[level - 1];

  static String describe(int level) => 'Bot Stufe $level (Ø ~${averageByLevel[level - 1]})';

  /// Wirft einen Dart auf [target].
  Hit throwAt(Hit target) {
    final aim = aimPoint(target);
    return scoreAt(aim.dx + _gauss() * sigma, aim.dy + _gauss() * sigma);
  }

  /// Normalverteilte Zufallszahl (Box-Muller).
  double _gauss() {
    final u = 1 - _random.nextDouble(); // (0, 1]
    final v = _random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  /// Zielpunkt in mm für ein Feld: Mitte des jeweiligen Rings im Segment.
  static Offset aimPoint(Hit target) {
    if (target.segment == 25) return target.multiplier == 2 ? Offset.zero : const Offset(0, (rBull + rOuterBull) / 2);
    if (target.segment == 0) return const Offset(0, 250); // absichtlich daneben – kommt praktisch nie vor
    final index = boardSegments.indexOf(target.segment);
    final angle = (90 - 18 * index) * math.pi / 180;
    final r = switch (target.multiplier) {
      3 => (rTripleInner + rTripleOuter) / 2,
      2 => (rDoubleInner + rDoubleOuter) / 2,
      _ => (rTripleOuter + rDoubleInner) / 2, // großes äußeres Single-Feld
    };
    return Offset(r * math.cos(angle), r * math.sin(angle));
  }
}
