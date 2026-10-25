import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/hit.dart';
import '../vision/calibration.dart';

/// Zeichnet Kalibrierpunkte, das projizierte Scheibenraster und einen Testpunkt
/// über das Kamerabild. Alle Punkte sind normiert (0..1) auf die Bildgröße.
class BoardOverlayPainter extends CustomPainter {
  BoardOverlayPainter({
    required this.points,
    required this.calibration,
    required this.activeHandle,
    this.testPoint,
    this.testLabel,
    this.detected = const [],
    required this.color,
  });

  final List<Offset> points;
  final BoardCalibration? calibration;
  final int? activeHandle;
  final Offset? testPoint;
  final String? testLabel;

  /// Erkannte Darts: Spitze (normiert) und Feld.
  final List<(Offset, Hit)> detected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset normalized) => Offset(normalized.dx * size.width, normalized.dy * size.height);

    final calib = calibration;
    if (calib != null) {
      final grid = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final r in [rOuterBull, rTripleInner, rTripleOuter, rDoubleInner, rDoubleOuter]) {
        final path = Path();
        for (var i = 0; i <= 72; i++) {
          final a = 2 * math.pi * i / 72;
          final p = px(calib.toImage(Offset(r * math.cos(a), r * math.sin(a))));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, grid);
      }
      for (var i = 0; i < 20; i++) {
        final a = (90 - 9 - 18 * i) * math.pi / 180;
        final inner = px(calib.toImage(Offset(rOuterBull * math.cos(a), rOuterBull * math.sin(a))));
        final outer = px(calib.toImage(Offset(rDoubleOuter * math.cos(a), rDoubleOuter * math.sin(a))));
        canvas.drawLine(inner, outer, grid);
      }
    }

    for (var i = 0; i < points.length; i++) {
      final p = px(points[i]);
      final active = i == activeHandle;
      canvas.drawCircle(p, active ? 14 : 10, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(
        p,
        active ? 14 : 10,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(p, 2, Paint()..color = color);
      _label(canvas, '${calibrationOrder[i]}', p + const Offset(14, -26));
    }

    for (final (tip, hit) in detected) {
      final p = px(tip);
      canvas.drawCircle(p, 6, Paint()..color = Colors.cyanAccent);
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _label(canvas, hit.label, p + const Offset(8, 4), background: Colors.cyan.shade800);
    }

    final test = testPoint;
    if (test != null) {
      final p = px(test);
      final paint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 2;
      canvas.drawLine(p - const Offset(10, 0), p + const Offset(10, 0), paint);
      canvas.drawLine(p - const Offset(0, 10), p + const Offset(0, 10), paint);
      if (testLabel != null) _label(canvas, testLabel!, p + const Offset(10, 6), background: Colors.redAccent);
    }
  }

  void _label(Canvas canvas, String text, Offset at, {Color? background}) {
    final painter = TextPainter(
      text: TextSpan(
        text: ' $text ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          backgroundColor: background ?? Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(BoardOverlayPainter old) =>
      old.points != points ||
      old.calibration != calibration ||
      old.activeHandle != activeHandle ||
      old.testPoint != testPoint ||
      old.testLabel != testLabel ||
      old.detected != detected ||
      old.color != color;
}
