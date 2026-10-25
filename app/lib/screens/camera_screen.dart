import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../vision/calibration.dart';
import '../vision/web_camera_stub.dart' if (dart.library.js_interop) '../vision/web_camera.dart';
import '../widgets/board_overlay.dart';

/// Kamera einrichten: Scheibe kalibrieren, Raster prüfen, Testvideos aufnehmen.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final WebCamera _camera = WebCamera();
  String? _error;
  bool _starting = true;

  /// Statt der Kamera ein mitgeliefertes Testbild zeigen (zum Ausprobieren ohne Kamera).
  bool _useTestImage = false;
  static const _testImageSize = Size(1280, 720);

  List<Offset> _points = []; // normiert, Reihenfolge wie calibrationOrder
  BoardCalibration? _calibration;
  int? _dragging;
  Offset? _testPoint;

  Timer? _recordTimer;
  Duration _recorded = Duration.zero;
  String? _lastFile;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final saved = await BoardCalibration.load();
    if (saved != null && mounted) {
      setState(() {
        _points = List.of(saved.points);
        _calibration = saved;
      });
    }
    try {
      await _camera.start();
    } on CameraException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Kamera konnte nicht gestartet werden: $e';
    }
    if (mounted) setState(() => _starting = false);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _camera.dispose();
    super.dispose();
  }

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
    calib?.save();
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

  void _reset() {
    setState(() {
      _points = [];
      _calibration = null;
      _testPoint = null;
    });
    BoardCalibration.clear();
  }

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
    final name = _lastFile == null ? '${_timestamp()}.calibration.json' : _lastFile!.replaceAll(RegExp(r'\.\w+$'), '.calibration.json');
    WebCamera.downloadText(name, const JsonEncoder.withIndent('  ').convert(calib.toJson(videoSize: _camera.videoSize.value)));
  }

  void _showSnack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String get _instruction {
    if (_points.length < 4) {
      return 'Tippe auf die Außenkante des Doppelrings, Mitte der ${calibrationOrder[_points.length]} '
          '(${_points.length + 1}/4)';
    }
    if (_calibration == null) return 'Die Punkte passen nicht zusammen. Bitte neu kalibrieren.';
    final test = _testPoint;
    if (test != null) return 'Getippt: ${_calibration!.scoreAt(test).label}';
    return 'Liegt das Raster auf der Scheibe? Punkte lassen sich verschieben. '
        'Tippe aufs Board, um ein Feld zu testen.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamera einrichten'),
        actions: [
          IconButton(
            tooltip: 'Neu kalibrieren',
            onPressed: _points.isEmpty ? null : _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildPreview(scheme)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(_instruction, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ),
            if (_error == null && !_starting && !_useTestImage) _buildControls(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    if (_starting) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _useTestImage = true;
                  _error = null;
                }),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Mit Testbild ausprobieren'),
              ),
            ],
          ),
        ),
      );
    }
    return ValueListenableBuilder<Size?>(
      valueListenable: _camera.videoSize,
      builder: (context, cameraSize, _) {
        final videoSize = _useTestImage ? _testImageSize : cameraSize;
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
                  if (_useTestImage)
                    Image.asset('assets/test_board.jpg', fit: BoxFit.contain)
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

  Widget _buildControls(ColorScheme scheme) {
    final recording = _camera.isRecording;
    final minutes = _recorded.inMinutes.toString().padLeft(2, '0');
    final seconds = (_recorded.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
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
    );
  }
}
