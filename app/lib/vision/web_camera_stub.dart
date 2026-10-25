import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'detector.dart';

/// Platzhalter für Plattformen ohne Browser. Die Kamera ist vorerst nur in der Web-Version
/// umgesetzt (iPhone über Safari).
class WebCamera {
  final String viewType = '';
  final ValueNotifier<Size?> videoSize = ValueNotifier(null);
  bool get isRecording => false;

  Future<void> start() async =>
      throw const CameraException('Die Kamera ist bisher nur in der Browser-Version verfügbar.');
  Frame? grabFrame({int maxWidth = 960}) => null;
  void startRecording() {}
  Future<String?> stopRecordingAndDownload(String baseName) async => null;
  static void downloadText(String filename, String content, {String type = 'application/json'}) {}
  void dispose() => videoSize.dispose();
}

class CameraException implements Exception {
  const CameraException(this.message);
  final String message;

  @override
  String toString() => message;
}

const cameraSupported = false;
