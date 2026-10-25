import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../vision/calibration.dart';
import '../vision/live_detection.dart';
import '../widgets/board_overlay.dart';
import '../widgets/live_preview.dart';

/// Kamera einrichten: Scheibe kalibrieren, Raster prüfen, Erkennung testen, Videos aufnehmen.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final LiveDetection _live = LiveDetection();

  List<Offset> _points = []; // normiert, Reihenfolge wie calibrationOrder
  int? _dragging;
  Offset? _testPoint;

  Timer? _recordTimer;
  Duration _recorded = Duration.zero;
  String? _lastFile;

  @override
  void initState() {
    super.initState();
    _live.addListener(_onLiveChanged);
    _init();
  }

  Future<void> _init() async {
    await _live.loadSavedCalibration();
    _syncPoints();
    await _live.startCamera();
  }

  void _onLiveChanged() {
    if (mounted) setState(() {});
  }

  void _syncPoints() {
    setState(() => _points = List.of(_live.calibration?.points ?? const []));
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _live.removeListener(_onLiveChanged);
    _live.dispose();
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
    _live.calibration = calib;
    if (!_live.isDemo) calib?.save(); // die Demo-Kalibrierung nicht als eigene speichern
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
      _testPoint = null;
      _live.calibration = null;
    });
    if (!_live.isDemo) BoardCalibration.clear();
  }

  Future<void> _toggleDemo() async {
    if (_live.isDemo) {
      _live.setDetecting(false);
      await _live.stopDemo();
    } else {
      await _live.startDemo();
      _live.setDetecting(true);
    }
    _testPoint = null;
    _syncPoints();
  }

  // ---------------------------------------------------------------- Aufnahme

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'dart_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  Future<void> _toggleRecording() async {
    final camera = _live.camera;
    if (camera.isRecording) {
      _recordTimer?.cancel();
      final file = await camera.stopRecordingAndDownload(_timestamp());
      setState(() => _lastFile = file);
      return;
    }
    try {
      camera.startRecording();
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
    final calib = _live.calibration;
    if (calib == null) return;
    final name = _lastFile == null
        ? '${_timestamp()}.calibration.json'
        : _lastFile!.replaceAll(RegExp(r'\.\w+$'), '.calibration.json');
    WebCamera.downloadText(
        name, const JsonEncoder.withIndent('  ').convert(calib.toJson(videoSize: _live.camera.videoSize.value)));
  }

  void _showSnack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------- Oberfläche

  String get _instruction {
    final calib = _live.calibration;
    if (_points.length < 4) {
      return 'Tippe auf die Außenkante des Doppelrings, Mitte der ${calibrationOrder[_points.length]} '
          '(${_points.length + 1}/4)';
    }
    if (calib == null) return 'Die Punkte passen nicht zusammen. Bitte neu kalibrieren.';
    if (_live.detecting) {
      return 'Erkennung läuft · ${_live.fps} Bilder/s · ${_live.processingMs} ms pro Bild';
    }
    final test = _testPoint;
    if (test != null) return 'Getippt: ${calib.scoreAt(test).label}';
    return 'Liegt das Raster auf der Scheibe? Punkte lassen sich verschieben. '
        'Tippe aufs Board, um ein Feld zu testen.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showPreview = _live.isDemo || _live.cameraRunning;
    return Scaffold(
      appBar: AppBar(
        title: Text(_live.isDemo ? 'Demo-Szene' : 'Kamera einrichten'),
        actions: [
          IconButton(
            tooltip: _live.isDemo ? 'Zurück zur Kamera' : 'Demo-Szene abspielen',
            onPressed: _toggleDemo,
            icon: Icon(_live.isDemo ? Icons.videocam_outlined : Icons.movie_outlined),
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
            Expanded(
              child: showPreview
                  ? LivePreview(live: _live, overlay: _buildOverlay)
                  : CameraStatus(live: _live, onDemo: _toggleDemo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(_instruction, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ),
            if (_live.detecting) _buildDetectedChips(scheme),
            if (showPreview) _buildControls(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, Size size) {
    Offset normalize(Offset local) => Offset(local.dx / size.width, local.dy / size.height);
    final calib = _live.calibration;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTap(normalize(d.localPosition)),
      onPanStart: (d) => _onPanStart(normalize(d.localPosition), size),
      onPanUpdate: (d) => _onPanUpdate(d.delta, size),
      onPanEnd: (_) => setState(() => _dragging = null),
      child: CustomPaint(
        painter: BoardOverlayPainter(
          points: _points,
          calibration: calib,
          activeHandle: _dragging,
          testPoint: _testPoint,
          testLabel: _testPoint == null ? null : calib?.scoreAt(_testPoint!).label,
          detected: List.of(_live.detected),
          color: Colors.lightGreenAccent,
        ),
      ),
    );
  }

  Widget _buildDetectedChips(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: _live.detected.isEmpty
            ? [Text('Noch kein Dart erkannt', style: TextStyle(color: scheme.onSurfaceVariant))]
            : [for (final (_, hit) in _live.detected) Chip(label: Text(hit.label))],
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    final recording = _live.camera.isRecording;
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
                  onPressed: _live.calibration == null ? null : () => _live.setDetecting(!_live.detecting),
                  icon: Icon(_live.detecting ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  label: Text(_live.detecting ? 'Erkennung aus' : 'Erkennung an'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _live.detecting ? _live.resetEmptyBoard : null,
                  icon: const Icon(Icons.crop_free),
                  label: const Text('Scheibe ist leer'),
                ),
              ),
            ],
          ),
          if (!_live.isDemo) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _live.calibration == null || recording ? null : _exportCalibration,
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

/// Ladeanzeige bzw. Fehlermeldung, solange die Kamera nicht läuft – mit Ausweg zur Demo-Szene.
class CameraStatus extends StatelessWidget {
  const CameraStatus({super.key, required this.live, required this.onDemo});

  final LiveDetection live;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (live.starting || live.error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text(live.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onDemo,
              icon: const Icon(Icons.movie_outlined),
              label: const Text('Demo-Szene abspielen'),
            ),
          ],
        ),
      ),
    );
  }
}
