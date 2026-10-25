import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import '../models/hit.dart';
import 'calibration.dart';
import 'demo_scene.dart';
import 'detector.dart';
import 'web_camera_stub.dart' if (dart.library.js_interop) 'web_camera.dart';

export 'web_camera_stub.dart' if (dart.library.js_interop) 'web_camera.dart' show CameraException, WebCamera;

/// Live-Erkennung: holt etwa 10 Bilder/s von der Kamera (oder aus der Demo-Szene),
/// lässt den [DartDetector] darüber laufen und meldet erkannte Darts.
///
/// Wird vom Kamera-Bildschirm und vom Spiel gemeinsam genutzt.
class LiveDetection extends ChangeNotifier {
  LiveDetection({this.config = const DetectorConfig(stableFrames: 3), this.onDart, this.onCleared}) {
    camera.videoSize.addListener(notifyListeners);
  }

  final DetectorConfig config;

  /// Ein Dart wurde erkannt (Feld und Spitze normiert auf 0..1).
  void Function(Hit hit, Offset tip)? onDart;

  /// Die Scheibe ist wieder leer (Darts wurden gezogen).
  VoidCallback? onCleared;

  final WebCamera camera = WebCamera();
  DemoScene? _demo;
  BoardCalibration? calibration;

  bool starting = false;
  bool cameraRunning = false;
  String? error;

  late DartDetector _detector = DartDetector(config);
  bool _detecting = false;
  Timer? _loop;
  bool _busy = false;
  bool _disposed = false;
  Frame? _lastFrame;

  /// Erkannte Darts seit dem letzten Leeren der Scheibe.
  final List<(Offset, Hit)> detected = [];

  int fps = 0;
  int processingMs = 0;
  int _framesThisSecond = 0;
  final Stopwatch _fpsClock = Stopwatch();

  DemoScene? get demo => _demo;
  bool get isDemo => _demo != null;
  bool get detecting => _detecting;

  /// Bildgröße der aktuellen Quelle, null solange die Kamera noch kein Bild liefert.
  Size? get videoSize => _demo != null ? Size(_demo!.width.toDouble(), _demo!.height.toDouble()) : camera.videoSize.value;

  Future<void> startCamera() async {
    starting = true;
    error = null;
    notifyListeners();
    try {
      await camera.start();
      cameraRunning = true;
    } on CameraException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Kamera konnte nicht gestartet werden: $e';
    }
    starting = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> loadSavedCalibration() async {
    calibration = await BoardCalibration.load();
    if (!_disposed) notifyListeners();
  }

  /// Spielt statt der Kamera die mitgelieferte Testszene ab (inkl. passender Kalibrierung).
  Future<void> startDemo() async {
    final demo = await DemoScene.load();
    if (_disposed) return;
    _demo = demo;
    calibration = demo.calibration;
    error = null;
    _restart();
  }

  Future<void> stopDemo() async {
    _demo?.dispose();
    _demo = null;
    await loadSavedCalibration();
    _restart();
  }

  void setDetecting(bool on) {
    _detecting = on;
    _restart();
  }

  /// Aktuelles Bild als leere Scheibe merken (z. B. nach Lichtänderung oder Kamera verschoben).
  void resetEmptyBoard() {
    final frame = _lastFrame;
    if (frame == null) return;
    _detector.reset(frame, empty: true);
    detected.clear();
    notifyListeners();
  }

  void _restart() {
    _detector = DartDetector(config);
    detected.clear();
    _loop?.cancel();
    _loop = null;
    if (_detecting || _demo != null) {
      _fpsClock
        ..reset()
        ..start();
      _loop = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    }
    notifyListeners();
  }

  Future<void> _tick() async {
    if (_busy || _disposed) return; // voriges Bild wird noch verarbeitet
    _busy = true;
    try {
      final frame = _demo != null ? await _demo!.next() : camera.grabFrame();
      if (frame == null || _disposed) return;
      _lastFrame = frame;
      if (_detecting) _detect(frame);

      _framesThisSecond++;
      if (_fpsClock.elapsedMilliseconds >= 1000) {
        fps = _framesThisSecond;
        _framesThisSecond = 0;
        _fpsClock
          ..reset()
          ..start();
      }
      notifyListeners();
    } catch (e) {
      // z. B. Demo-Bilder nicht ladbar (Verbindung weg): anhalten statt 10x pro Sekunde zu scheitern
      _loop?.cancel();
      _loop = null;
      error = 'Bild konnte nicht verarbeitet werden: $e';
      if (!_disposed) notifyListeners();
    } finally {
      _busy = false;
    }
  }

  void _detect(Frame frame) {
    final clock = Stopwatch()..start();
    final result = _detector.update(frame);
    processingMs = clock.elapsedMilliseconds;

    switch (result.event) {
      case DetectionEvent.dart:
        final tip = result.tip, calib = calibration;
        if (tip != null && calib != null) {
          final normalized = Offset(tip.dx / frame.width, tip.dy / frame.height);
          final hit = calib.scoreAt(normalized);
          detected.add((normalized, hit));
          onDart?.call(hit, normalized);
        }
      case DetectionEvent.boardCleared:
        detected.clear();
        onCleared?.call();
      case DetectionEvent.none:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loop?.cancel();
    _demo?.dispose();
    camera.videoSize.removeListener(notifyListeners);
    camera.dispose();
    super.dispose();
  }
}
