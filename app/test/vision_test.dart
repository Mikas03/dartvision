import 'dart:math' as math;
import 'dart:ui';

import 'package:dartvision_app/models/board.dart';
import 'package:dartvision_app/vision/calibration.dart';
import 'package:dartvision_app/vision/homography.dart';
import 'package:flutter_test/flutter_test.dart';

Offset polar(double r, double clockwiseDegFromTop) {
  final a = (90 - clockwiseDegFromTop) * math.pi / 180;
  return Offset(r * math.cos(a), r * math.sin(a));
}

void expectClose(Offset a, Offset b, [double tol = 1e-6]) {
  expect((a - b).distance, lessThan(tol), reason: '$a != $b');
}

void main() {
  group('Scheibe', () {
    final cases = <(double, double, String)>[
      (0, 0, 'Bull'),
      (10, 45, '25'),
      (50, 0, '20'),
      (103, 0, 'T20'),
      (166, 0, 'D20'),
      (180, 0, 'Miss'),
      (103, 18, 'T1'),
      (50, 90, '6'),
      (166, 180, 'D3'),
      (103, 270, 'T11'),
      (50, 351, '20'),
      (50, 9.1, '1'),
    ];
    for (final (r, angle, label) in cases) {
      test('r=$r, $angle° -> $label', () {
        final p = polar(r, angle);
        expect(scoreAt(p.dx, p.dy).label, label);
      });
    }
  });

  group('Homographie', () {
    test('bildet die 4 Punkte ab und lässt sich umkehren', () {
      const src = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      const dst = [Offset(10, 20), Offset(110, 30), Offset(100, 140), Offset(5, 120)];
      final h = Homography.fromPoints(src, dst);
      for (var i = 0; i < 4; i++) {
        expectClose(h.map(src[i]), dst[i]);
      }
      final inv = h.inverse();
      expectClose(inv.map(h.map(const Offset(0.3, 0.7))), const Offset(0.3, 0.7));
    });

    test('drei Punkte auf einer Linie werden abgelehnt', () {
      expect(
        () => Homography.fromPoints(
          const [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(0, 1)],
          const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
        ),
        throwsStateError,
      );
    });
  });

  group('Kalibrierung', () {
    // Frontal aufgenommen: Bull in der Bildmitte, Doppelring füllt 80 % der Höhe (Bild 16:9)
    BoardCalibration frontal() {
      const cy = 0.5, ry = 0.4, rx = 0.4 * 9 / 16, cx = 0.5;
      return BoardCalibration(const [
        Offset(cx, cy - ry), // 20 oben
        Offset(cx + rx, cy), // 6 rechts
        Offset(cx, cy + ry), // 3 unten
        Offset(cx - rx, cy), // 11 links
      ]);
    }

    test('Felder an bekannten Bildpositionen', () {
      final calib = frontal();
      expect(calib.scoreAt(const Offset(0.5, 0.5)).label, 'Bull');
      expect(calib.scoreAt(Offset(0.5, 0.5 - 0.4 * 103 / 170)).label, 'T20');
      expect(calib.scoreAt(Offset(0.5 + 0.4 * 9 / 16 * 166 / 170, 0.5)).label, 'D6');
    });

    test('Bild -> Scheibe -> Bild ergibt denselben Punkt', () {
      final calib = frontal();
      expectClose(calib.toImage(calib.toBoard(const Offset(0.42, 0.61))), const Offset(0.42, 0.61));
    });

    test('JSON-Export und -Import', () {
      final calib = frontal();
      final json = calib.toJson(videoSize: const Size(1920, 1080));
      expect(json['width'], 1920);
      expect(json['order'], [20, 6, 3, 11]);
      final restored = BoardCalibration.fromJson(json);
      expect(restored!.points, calib.points);
    });
  });
}
