import 'dart:math' as math;

import 'hit.dart';

/// Geometrie einer Steeldart-Scheibe (wie board.py im Python-Prototyp).
/// Koordinaten in mm, Ursprung im Bull, x nach rechts, y nach oben.

/// Segmentreihenfolge im Uhrzeigersinn, beginnend oben.
const boardSegments = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

const rBull = 6.35;
const rOuterBull = 15.9;
const rTripleInner = 99.0;
const rTripleOuter = 107.0;
const rDoubleInner = 162.0;
const rDoubleOuter = 170.0;

/// Segmentzahl (1-20) an einer Position, unabhängig vom Radius.
int segmentAt(double x, double y) {
  final angle = math.atan2(y, x) * 180 / math.pi; // 0° = rechts, gegen Uhrzeigersinn
  final clockwiseFromTop = (90 - angle) % 360;
  final index = ((clockwiseFromTop + 9) % 360) ~/ 18;
  return boardSegments[index];
}

/// Getroffenes Feld an einer Position in mm.
Hit scoreAt(double x, double y) {
  final r = math.sqrt(x * x + y * y);
  if (r <= rBull) return Hit.bull;
  if (r <= rOuterBull) return Hit.outerBull;
  if (r > rDoubleOuter) return Hit.miss;

  final segment = segmentAt(x, y);
  if (r > rTripleInner && r <= rTripleOuter) return Hit.triple(segment);
  if (r > rDoubleInner) return Hit.double(segment);
  return Hit.single(segment);
}
