import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show Size;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Kamera im Browser über getUserMedia. Das Video wird mit object-fit: contain angezeigt,
/// d. h. ohne Beschnitt. Dadurch entsprechen normierte Koordinaten auf der Vorschau exakt
/// denen im aufgenommenen Video.
class WebCamera {
  WebCamera() : viewType = 'dart-camera-${_counter++}';

  static int _counter = 0;

  final String viewType;
  final ValueNotifier<Size?> videoSize = ValueNotifier(null);

  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = [];
  String _mimeType = 'video/mp4';

  bool get isRecording => _recorder != null;

  /// Startet die Rückkamera. Wirft eine [CameraException] mit verständlicher Meldung.
  Future<void> start() async {
    if (!web.window.isSecureContext) {
      throw const CameraException('Die Kamera funktioniert nur über HTTPS.');
    }
    final constraints = {
      'audio': false,
      'video': {
        'facingMode': {'ideal': 'environment'},
        'width': {'ideal': 1920},
        'height': {'ideal': 1080},
      },
    }.jsify()! as web.MediaStreamConstraints;

    try {
      _stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
    } catch (e) {
      final text = e.toString();
      if (text.contains('NotAllowed')) {
        throw const CameraException('Kamerazugriff wurde abgelehnt. Erlaube ihn in den Safari-Einstellungen.');
      }
      if (text.contains('NotFound')) {
        throw const CameraException('Keine Kamera gefunden.');
      }
      throw CameraException('Kamera konnte nicht gestartet werden: $text');
    }

    final video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', '')
      ..srcObject = _stream;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..pointerEvents = 'none'
      ..backgroundColor = 'black';
    _video = video;

    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => video);

    final ready = Completer<void>();
    void updateSize() {
      if (video.videoWidth > 0 && video.videoHeight > 0) {
        videoSize.value = Size(video.videoWidth.toDouble(), video.videoHeight.toDouble());
        if (!ready.isCompleted) ready.complete();
      }
    }

    // 'resize' feuert auch beim Drehen des Handys, wenn sich das Seitenverhältnis ändert
    video.addEventListener('loadedmetadata', ((web.Event _) => updateSize()).toJS);
    video.addEventListener('resize', ((web.Event _) => updateSize()).toJS);
    await video.play().toDart;
    updateSize();
    await ready.future.timeout(const Duration(seconds: 10),
        onTimeout: () => throw const CameraException('Kamera liefert kein Bild.'));
  }

  void startRecording() {
    final stream = _stream;
    if (stream == null || isRecording) return;
    const candidates = ['video/mp4', 'video/webm;codecs=vp9', 'video/webm'];
    _mimeType = candidates.firstWhere((type) => web.MediaRecorder.isTypeSupported(type),
        orElse: () => throw const CameraException('Dieser Browser kann keine Videos aufnehmen.'));
    _chunks.clear();
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(mimeType: _mimeType, videoBitsPerSecond: 8000000),
    );
    recorder.addEventListener(
      'dataavailable',
      ((web.BlobEvent e) {
        if (e.data.size > 0) _chunks.add(e.data);
      }).toJS,
    );
    recorder.start(1000);
    _recorder = recorder;
  }

  /// Beendet die Aufnahme und bietet das Video zum Speichern an. Gibt den Dateinamen zurück.
  Future<String?> stopRecordingAndDownload(String baseName) async {
    final recorder = _recorder;
    if (recorder == null) return null;
    final stopped = Completer<void>();
    recorder.addEventListener('stop', ((web.Event _) => stopped.complete()).toJS);
    recorder.stop();
    await stopped.future;
    _recorder = null;

    final blob = web.Blob(_chunks.cast<JSAny>().toList().toJS, web.BlobPropertyBag(type: _mimeType));
    final extension = _mimeType.contains('mp4') ? 'mp4' : 'webm';
    final filename = '$baseName.$extension';
    _download(blob, filename);
    _chunks.clear();
    return filename;
  }

  static void downloadText(String filename, String content, {String type = 'application/json'}) {
    _download(web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: type)), filename);
  }

  static void _download(web.Blob blob, String filename) {
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  void dispose() {
    _recorder?.stop();
    _recorder = null;
    final tracks = _stream?.getTracks().toDart ?? [];
    for (final track in tracks) {
      track.stop();
    }
    _stream = null;
    _video?.srcObject = null;
    videoSize.dispose();
  }
}

class CameraException implements Exception {
  const CameraException(this.message);
  final String message;

  @override
  String toString() => message;
}

const cameraSupported = true;
