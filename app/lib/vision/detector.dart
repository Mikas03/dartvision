import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Ein Kamerabild im RGBA-Format (4 Bytes pro Pixel, wie getImageData im Browser).
class Frame {
  Frame(this.width, this.height, this.rgba) : assert(rgba.length == width * height * 4);

  final int width;
  final int height;
  final Uint8List rgba;
}

class DetectorConfig {
  const DetectorConfig({
    this.diffThreshold = 30,
    this.motionPixels = 500,
    this.stableFrames = 8,
    this.minDartArea = 300,
    this.maxDartArea = 30000,
    this.endFraction = 0.15,
    this.removeShadows = true,
    this.shadowMinRatio = 0.45,
    this.shadowMaxRatio = 0.92,
    this.shadowMaxSpread = 0.08,
    this.referencePixels = 1280 * 720,
  });

  /// Farbunterschied (größter Kanal), ab dem ein Pixel als geändert gilt.
  final int diffThreshold;

  /// Mehr geänderte Pixel zum Vorbild = Bewegung.
  final int motionPixels;

  /// So viele ruhige Bilder hintereinander, bevor ausgewertet wird.
  final int stableFrames;

  /// Kleinere Änderungen ignorieren (Rauschen).
  final int minDartArea;

  /// Größere Änderungen = Hand / Person im Bild.
  final int maxDartArea;

  /// Anteil der Dartlänge, der zur Breitenmessung an den Enden genutzt wird.
  final double endFraction;

  final bool removeShadows;
  final double shadowMinRatio;
  final double shadowMaxRatio;
  final double shadowMaxSpread;

  /// Die Flächenwerte gelten für diese Bildgröße und werden für andere Auflösungen skaliert.
  final int referencePixels;
}

enum DetectionEvent { none, dart, boardCleared }

class Detection {
  const Detection(this.event, {this.tip, this.changedPixels = 0});

  final DetectionEvent event;

  /// Geschätzte Spitze in Pixeln des ausgewerteten Bildes.
  final Offset? tip;
  final int changedPixels;
}

/// Klassische Darterkennung per Differenzbild – dieselbe Logik wie detection.py im Python-Prototyp:
///
/// 1. Bild weichzeichnen, mit dem vorigen vergleichen: Bewegung?
/// 2. Ist das Bild [DetectorConfig.stableFrames] Bilder lang ruhig, mit der Referenz vergleichen.
/// 3. Sieht es aus wie die leere Scheibe -> Darts wurden gezogen.
/// 4. Kleine bis mittlere Änderung (ohne Schatten) -> neuer Dart, Spitze schätzen.
/// 5. Sehr große Änderung -> Hand/Person im Bild, ignorieren.
class DartDetector {
  DartDetector([this.config = const DetectorConfig()]);

  final DetectorConfig config;

  _Image? _reference; // Stand nach dem letzten erkannten Dart
  _Image? _empty; // leere Scheibe
  _Image? _previous;
  int _stableCount = 0;
  int _dartsOnBoard = 0;
  double _areaScale = 1;

  int get dartsOnBoard => _dartsOnBoard;

  /// Setzt das aktuelle Bild als Referenz; mit [empty] auch als leere Scheibe.
  void reset(Frame frame, {bool empty = false}) {
    final img = _Image.blurred(frame);
    _areaScale = frame.width * frame.height / config.referencePixels;
    _reference = img;
    _previous = img;
    _stableCount = 0;
    if (empty || _empty == null) {
      _empty = img;
      _dartsOnBoard = 0;
    }
  }

  Detection update(Frame frame) {
    final reference = _reference;
    final previous = _previous;
    if (reference == null || previous == null || previous.width != frame.width || previous.height != frame.height) {
      reset(frame, empty: true);
      return const Detection(DetectionEvent.none);
    }

    final img = _Image.blurred(frame);
    final moving = _countDiff(img, previous) > config.motionPixels * _areaScale;
    _previous = img;
    _stableCount = moving ? 0 : _stableCount + 1;
    if (_stableCount != config.stableFrames) return const Detection(DetectionEvent.none);

    // Bild ist gerade ruhig geworden. Sieht es wieder wie die leere Scheibe aus,
    // wurden die Darts gezogen.
    if (_dartsOnBoard > 0 && _count(_dartMask(img, _empty!)) < config.minDartArea * _areaScale) {
      _reference = img;
      _dartsOnBoard = 0;
      return const Detection(DetectionEvent.boardCleared);
    }

    final mask = _dartMask(img, reference);
    final changed = _count(mask);
    if (changed < config.minDartArea * _areaScale) return const Detection(DetectionEvent.none);
    if (changed > config.maxDartArea * _areaScale) {
      // Person/Hand im Bild -> ignorieren, Referenz bleibt
      return Detection(DetectionEvent.none, changedPixels: changed);
    }

    final tip = findTip(mask, img.width);
    _reference = img;
    _dartsOnBoard++;
    return Detection(DetectionEvent.dart, tip: tip, changedPixels: changed);
  }

  /// Schätzt die Dartspitze in einer Differenzmaske (1 = geändert).
  ///
  /// Hauptachse aller geänderten Pixel bestimmen; das Ende, an dem die Maske schmaler ist,
  /// ist die Spitze, das breite Ende der Flight. Bewusst alle Pixel statt nur der größten
  /// Fläche: Ein dunkler Schaft auf schwarzem Segment fällt weg, der Dart zerfällt in Teile.
  Offset? findTip(Uint8List mask, int width) {
    var n = 0;
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0) {
        n++;
        sx += i % width;
        sy += i ~/ width;
      }
    }
    if (n < 5) return null;
    final cx = sx / n, cy = sy / n;

    // Hauptachse über die Kovarianzmatrix (entspricht cv2.fitLine mit DIST_L2)
    var cxx = 0.0, cyy = 0.0, cxy = 0.0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0) {
        final dx = i % width - cx, dy = i ~/ width - cy;
        cxx += dx * dx;
        cyy += dy * dy;
        cxy += dx * dy;
      }
    }
    final angle = 0.5 * math.atan2(2 * cxy, cxx - cyy);
    final ax = math.cos(angle), ay = math.sin(angle);

    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0) {
        final along = (i % width - cx) * ax + (i ~/ width - cy) * ay;
        if (along < lo) lo = along;
        if (along > hi) hi = along;
      }
    }

    final span = (hi - lo) * config.endFraction;
    var loMin = double.infinity, loMax = double.negativeInfinity;
    var hiMin = double.infinity, hiMax = double.negativeInfinity;
    var loIndex = -1, hiIndex = -1;
    var loBest = double.infinity, hiBest = double.negativeInfinity;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) continue;
      final dx = i % width - cx, dy = i ~/ width - cy;
      final along = dx * ax + dy * ay;
      final across = -dx * ay + dy * ax;
      if (along < lo + span) {
        loMin = math.min(loMin, across);
        loMax = math.max(loMax, across);
      }
      if (along > hi - span) {
        hiMin = math.min(hiMin, across);
        hiMax = math.max(hiMax, across);
      }
      if (along < loBest) {
        loBest = along;
        loIndex = i;
      }
      if (along > hiBest) {
        hiBest = along;
        hiIndex = i;
      }
    }
    final widthLo = loMax - loMin, widthHi = hiMax - hiMin;
    // äußerster Pixel am schmalen Ende
    final tipIndex = widthLo < widthHi ? loIndex : hiIndex;
    return Offset((tipIndex % width).toDouble(), (tipIndex ~/ width).toDouble());
  }

  /// Anzahl Pixel, die sich in mindestens einem Kanal deutlich geändert haben.
  int _countDiff(_Image a, _Image b) {
    final t = config.diffThreshold;
    var count = 0;
    for (var p = 0, i = 0; p < a.width * a.height; p++, i += 3) {
      if ((a.data[i] - b.data[i]).abs() > t ||
          (a.data[i + 1] - b.data[i + 1]).abs() > t ||
          (a.data[i + 2] - b.data[i + 2]).abs() > t) {
        count++;
      }
    }
    return count;
  }

  /// Maske der Pixel, die sich geändert haben und kein Schatten sind, morphologisch bereinigt.
  Uint8List _dartMask(_Image current, _Image reference) {
    final c = current.data, r = reference.data;
    final t = config.diffThreshold;
    final mask = Uint8List(current.width * current.height);
    for (var p = 0, i = 0; p < mask.length; p++, i += 3) {
      final d0 = (c[i] - r[i]).abs(), d1 = (c[i + 1] - r[i + 1]).abs(), d2 = (c[i + 2] - r[i + 2]).abs();
      if (d0 <= t && d1 <= t && d2 <= t) continue;
      if (config.removeShadows) {
        // Schatten: alle Kanäle etwa gleich stark dunkler, Farbe bleibt gleich
        final q0 = (c[i] + 1) / (r[i] + 1), q1 = (c[i + 1] + 1) / (r[i + 1] + 1), q2 = (c[i + 2] + 1) / (r[i + 2] + 1);
        final mean = (q0 + q1 + q2) / 3;
        final spread = math.max(q0, math.max(q1, q2)) - math.min(q0, math.min(q1, q2));
        if (mean > config.shadowMinRatio && mean < config.shadowMaxRatio && spread < config.shadowMaxSpread) {
          continue;
        }
      }
      mask[p] = 1;
    }
    return _clean(mask, current.width, current.height);
  }

  static int _count(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      n += v;
    }
    return n;
  }

  /// Öffnen (1x) und Schließen (2x) mit einem 3x3-Kreuz – wie cv2.morphologyEx mit MORPH_ELLIPSE 3x3.
  static Uint8List _clean(Uint8List mask, int w, int h) {
    var m = _erode(mask, w, h);
    m = _dilate(m, w, h);
    m = _dilate(_dilate(m, w, h), w, h);
    return _erode(_erode(m, w, h), w, h);
  }

  static Uint8List _erode(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (src[i] == 0) continue;
        // Pixel außerhalb des Bildes zählen als gesetzt (wie OpenCV beim Erodieren)
        if ((x > 0 && src[i - 1] == 0) ||
            (x < w - 1 && src[i + 1] == 0) ||
            (y > 0 && src[i - w] == 0) ||
            (y < h - 1 && src[i + w] == 0)) {
          continue;
        }
        out[i] = 1;
      }
    }
    return out;
  }

  static Uint8List _dilate(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (src[i] != 0 ||
            (x > 0 && src[i - 1] != 0) ||
            (x < w - 1 && src[i + 1] != 0) ||
            (y > 0 && src[i - w] != 0) ||
            (y < h - 1 && src[i + w] != 0)) {
          out[i] = 1;
        }
      }
    }
    return out;
  }
}

/// Weichgezeichnetes RGB-Bild (3 Bytes pro Pixel).
class _Image {
  _Image(this.width, this.height, this.data);

  final int width;
  final int height;
  final Uint8List data;

  /// 5x5-Gauß ([1 4 6 4 1] / 16 in beide Richtungen), wie cv2.GaussianBlur(…, (5, 5), 0).
  ///
  /// Auf Geschwindigkeit getrimmt (läuft auf jedes Kamerabild): Kanäle getrennt, Kernel
  /// ausgerollt, Randbehandlung nur in den äußeren zwei Pixeln.
  factory _Image.blurred(Frame frame) {
    final w = frame.width, h = frame.height, src = frame.rgba;
    final tmp = Uint16List(w * h);
    final out = Uint8List(w * h * 3);
    for (var c = 0; c < 3; c++) {
      // horizontal: RGBA -> tmp (ein Kanal)
      for (var y = 0; y < h; y++) {
        final row = y * w;
        for (var x = 0; x < w; x++) {
          int sum;
          if (x >= 2 && x < w - 2) {
            final i = (row + x) * 4 + c;
            sum = src[i - 8] + 4 * src[i - 4] + 6 * src[i] + 4 * src[i + 4] + src[i + 8];
          } else {
            sum = 0;
            for (var j = -2; j <= 2; j++) {
              sum += _k[j + 2] * src[(row + _reflect(x + j, w)) * 4 + c];
            }
          }
          tmp[row + x] = sum;
        }
      }
      // vertikal: tmp -> out
      for (var y = 0; y < h; y++) {
        final inner = y >= 2 && y < h - 2;
        for (var x = 0; x < w; x++) {
          int sum;
          final i = y * w + x;
          if (inner) {
            sum = tmp[i - 2 * w] + 4 * tmp[i - w] + 6 * tmp[i] + 4 * tmp[i + w] + tmp[i + 2 * w];
          } else {
            sum = 0;
            for (var j = -2; j <= 2; j++) {
              sum += _k[j + 2] * tmp[_reflect(y + j, h) * w + x];
            }
          }
          out[i * 3 + c] = (sum + 128) >> 8; // / 256 mit Rundung
        }
      }
    }
    return _Image(w, h, out);
  }

  static const _k = [1, 4, 6, 4, 1];

  /// Randbehandlung wie OpenCV (BORDER_REFLECT_101).
  static int _reflect(int i, int n) {
    if (i < 0) return -i;
    if (i >= n) return 2 * n - i - 2;
    return i;
  }
}
