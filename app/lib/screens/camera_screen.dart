import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/hit.dart';
import '../vision/calibration.dart';
import '../vision/demo_scene.dart';
import '../vision/detector.dart';
import '../vision/web_camera_stub.dart' if (dart.library.js_interop) '../vision/web_camera.dart';
import '../widgets/board_overlay.dart';

/// Kamera einrichten: Scheibe kalibrieren, Raster prüfen, Erkennung testen, Videos aufnehmen.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final WebCamera _camera = WebCamera();
  String? _error;
  bool _starting = true;

  /// Statt der Kamera die mitgelieferte Testszene abspielen (zum Ausprobieren ohne Kamera/Board).
  DemoScene? _demo;

  List<Offset> _points = []; // normiert, Reihenfolge wie calibrationOrder
  BoardCalibration? _calibration;
  int? _dragging;
  Offset? _testPoint;

  // Erkennung
  static const _detectorConfig = DetectorConfig(stableFrames: 3); // ca. 10 Bilder/s
  DartDetector _detector = DartDetector(_detectorConfig);
  bool _detecting = false;
  Timer? _loop;
  bool _busy = false;
  Frame? _lastFrame;
  final List<(Offset, Hit)> _detected = [];
  int _processingMs = 0;
  int _framesThisSecond = 0;
  int _fps = 0;
  final Stopwatch _fpsClock = Stopwatch();

  // Aufnahme
  Timer? _recordTimer;
  Duration _recorded = Duration.zero;
  String? _lastFile;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadSavedCalibration();
    try {
      await _camera.start();
    } on CameraException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Kamera konnte nicht gestartet werden: $e';
    }
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _loadSavedCalibration() async {
    final saved = await BoardCalibration.load();
    if (!mounted) return;
    setState(() {
      _points = saved == null ? [] : List.of(saved.points);
      _calibration = saved;
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    _recordTimer?.cancel();
    _demo?.dispose();
    _camera.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Kalibrierung

  void _updateCalibration() {
    BoardCalibration? calib;
    if (_points.length == 4) {
      try {
        calib = BoardCalibration(_points);
      } catch (_) {
        calib = null; // Punkte liegen ungünstig, z. B. drei auf einer Linie
      }
    }
    _calibration = calib;
    if (_demo == null) calib?.save(); // die Demo-Kalibrierung nicht als eigene speichern
  }

  void _onTap(Offset normalized) {
    setState(() {
      if (_points.length < 4) {
        _points = [..._points, normalized];
        _updateCalibration();
      } else {
        _testPoint = normalized;
      }
    });
  }

  void _onPanStart(Offset normalized, Size size) {
    // nächsten Punkt im Umkreis von 40 Pixeln greifen
    int? best;
    var bestDist = 40.0;
    for (var i = 0; i < _points.length; i++) {
      final d = Offset((_points[i].dx - normalized.dx) * size.width, (_points[i].dy - normalized.dy) * size.height)
          .distance;
      if (d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    setState(() => _dragging = best);
  }

  void _onPanUpdate(Offset delta, Size size) {
    final i = _dragging;
    if (i == null) return;
    setState(() {
      final p = _points[i] + Offset(delta.dx / size.width, delta.dy / size.height);
      _points = [..._points]..[i] = Offset(p.dx.clamp(0, 1), p.dy.clamp(0, 1));
      _updateCalibration();
    });
  }

  void _resetCalibration() {
    setState(() {
      _points = [];
      _calibration = null;
      _testPoint = null;
    });
    if (_demo == null) BoardCalibration.clear();
  }

  // ---------------------------------------------------------------- Demo und Erkennung

  Future<void> _toggleDemo() async {
    if (_demo != null) {
      _demo!.dispose();
      _demo = null;
      _setDetecting(false);
      await _loadSavedCalibration();
      return;
    }
    final demo = await DemoScene.load();
    if (!mounted) return;
    setState(() {
      _demo = demo;
      _points = List.of(demo.calibration.points);
      _calibration = demo.calibration;
      _testPoint = null;
    });
    _setDetecting(true);
  }

  void _setDetecting(bool on) {
    _detector = DartDetector(_detectorConfig);
    _detected.clear();
    _detecting = on;
    _loop?.cancel();
    _loop = null;
    if (on || _demo != null) {
      _fpsClock
        ..reset()
        ..start();
      _loop = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    }
    setState(() {});
  }

  Future<void> _tick() async {
    if (_busy) return; // voriges Bild wird noch verarbeitet
    _busy = true;
    try {
      final frame = _demo != null ? await _demo!.next() : _camera.grabFrame();
      if (frame == null || !mounted) return;
      _lastFrame = frame;
      if (_detecting) _detect(frame);

      _framesThisSecond++;
      if (_fpsClock.elapsedMilliseconds >= 1000) {
        _fps = _framesThisSecond;
        _framesThisSecond = 0;
        _fpsClock
          ..reset()
          ..start();
      }
      setState(() {});
    } finally {
      _busy = false;
    }
  }

  void _detect(Frame frame) {
    final clock = Stopwatch()..start();
    final result = _detector.update(frame);
    _processingMs = clock.elapsedMilliseconds;

    switch (result.event) {
      case DetectionEvent.dart:
        final tip = result.tip, calib = _calibration;
        if (tip != null && calib != null) {
          final normalized = Offset(tip.dx / frame.width, tip.dy / frame.height);
          _detected.add((normalized, calib.scoreAt(normalized)));
        }
      case DetectionEvent.boardCleared:
        _detected.clear();
      case DetectionEvent.none:
        break;
    }
  }

  /// Aktuelles Bild als leere Scheibe merken (z. B. nach Lichtänderung oder Kamera verschoben).
  void _resetEmptyBoard() {
    final frame = _lastFrame;
    if (frame == null) return;
    setState(() {
      _detector.reset(frame, empty: true);
      _detected.clear();
    });
  }

  // ---------------------------------------------------------------- Aufnahme

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'dart_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<void> _toggleRecording() async {
    if (_camera.isRecording) {
      _recordTimer?.cancel();
      final file = await _camera.stopRecordingAndDownload(_timestamp());
      setState(() => _lastFile = file);
      return;
    }
    try {
      _camera.startRecording();
    } on CameraException catch (e) {
      _showSnack(e.message);
      return;
    }
    _recorded = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recorded += const Duration(seconds: 1));
    });
    setState(() {});
  }

  void _exportCalibration() {
    final calib = _calibration;
    if (calib == null) return;
    final name = _lastFile == null
        ? '${_timestamp()}.calibration.json'
        : _lastFile!.replaceAll(RegExp(r'\.\w+$'), '.calibration.json');
    WebCamera.downloadText(
        name, const JsonEncoder.withIndent('  ').convert(calib.toJson(videoSize: _camera.videoSize.value)));
  }

  void _showSnack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------- Oberfläche

  String get _instruction {
    if (_points.length < 4) {
      return 'Tippe auf die Außenkante des Doppelrings, Mitte der ${calibrationOrder[_points.length]} '
          '(${_points.length + 1}/4)';
    }
    if (_calibration == null) return 'Die Punkte passen nicht zusammen. Bitte neu kalibrieren.';
    if (_detecting) {
      return 'Erkennung läuft · $_fps Bilder/s · $_processingMs ms pro Bild';
    }
    final test = _testPoint;
    if (test != null) return 'Getippt: ${_calibration!.scoreAt(test).label}';
    return 'Liegt das Raster auf der Scheibe? Punkte lassen sich verschieben. '
        'Tippe aufs Board, um ein Feld zu testen.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showPreview = _demo != null || (_error == null && !_starting);
    return Scaffold(
      appBar: AppBar(
        title: Text(_demo != null ? 'Demo-Szene' : 'Kamera einrichten'),
        actions: [
          IconButton(
            tooltip: _demo != null ? 'Zurück zur Kamera' : 'Demo-Szene abspielen',
            onPressed: _toggleDemo,
            icon: Icon(_demo != null ? Icons.videocam_outlined : Icons.movie_outlined),
          ),
          IconButton(
            tooltip: 'Neu kalibrieren',
            onPressed: _points.isEmpty ? null : _resetCalibration,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: showPreview ? _buildPreview() : _buildStatus(scheme)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(_instruction, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ),
            if (_detecting) _buildDetectedChips(scheme),
            if (showPreview) _buildControls(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ColorScheme scheme) {
    if (_starting) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _toggleDemo,
              icon: const Icon(Icons.movie_outlined),
              label: const Text('Demo-Szene abspielen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final demo = _demo;
    return ValueListenableBuilder<Size?>(
      valueListenable: _camera.videoSize,
      builder: (context, cameraSize, _) {
        final videoSize = demo != null ? Size(demo.width.toDouble(), demo.height.toDouble()) : cameraSize;
        if (videoSize == null) return const Center(child: CircularProgressIndicator());
        return Center(
          child: AspectRatio(
            aspectRatio: videoSize.width / videoSize.height,
            child: LayoutBuilder(builder: (context, constraints) {
              final size = constraints.biggest;
              Offset normalize(Offset local) => Offset(local.dx / size.width, local.dy / size.height);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (demo != null)
                    demo.image == null
                        ? const ColoredBox(color: Colors.black)
                        : RawImage(image: demo.image, fit: BoxFit.contain)
                  else
                    HtmlElementView(viewType: _camera.viewType),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTap(normalize(d.localPosition)),
                    onPanStart: (d) => _onPanStart(normalize(d.localPosition), size),
                    onPanUpdate: (d) => _onPanUpdate(d.delta, size),
                    onPanEnd: (_) => setState(() => _dragging = null),
                    child: CustomPaint(
                      painter: BoardOverlayPainter(
                        points: _points,
                        calibration: _calibration,
                        activeHandle: _dragging,
                        testPoint: _testPoint,
                        testLabel: _testPoint == null ? null : _calibration?.scoreAt(_testPoint!).label,
                        detected: List.of(_detected),
                        color: Colors.lightGreenAccent,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildDetectedChips(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: _detected.isEmpty
            ? [Text('Noch kein Dart erkannt', style: TextStyle(color: scheme.onSurfaceVariant))]
            : [for (final (_, hit) in _detected) Chip(label: Text(hit.label))],
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    final recording = _camera.isRecording;
    final minutes = _recorded.inMinutes.toString().padLeft(2, '0');
    final seconds = (_recorded.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _calibration == null ? null : () => _setDetecting(!_detecting),
                  icon: Icon(_detecting ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  label: Text(_detecting ? 'Erkennung aus' : 'Erkennung an'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _detecting ? _resetEmptyBoard : null,
                  icon: const Icon(Icons.crop_free),
                  label: const Text('Scheibe ist leer'),
                ),
              ),
            ],
          ),
          if (_demo == null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _calibration == null || recording ? null : _exportCalibration,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Kalibrierung'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _toggleRecording,
                    style: recording ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
                    icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(recording ? 'Stopp $minutes:$seconds' : 'Aufnehmen'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
