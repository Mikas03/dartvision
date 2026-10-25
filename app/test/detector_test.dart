import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvision_app/vision/calibration.dart';
import 'package:dartvision_app/vision/detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Szene aus dem Python-Generator (Scenario.export_fixture, seed 0): 2 Aufnahmen à 3 Darts.
const fixture = 'assets/demo_scene';

/// Was der Python-Prototyp (detection.py) auf genau dieser Szene erkennt –
/// siehe tests/test_fixture.py. Beide Versionen müssen übereinstimmen, auch bei den Fehlern.
const pythonLabels = ['13', 'Miss', '25', '20', 'T1', 'T5'];
const truthLabels = ['13', 'Miss', '25', '20', '1', '20'];

void main() {
  test('Erkennung entspricht dem Python-Prototyp', () {
    final data = jsonDecode(File('$fixture/scenario.json').readAsStringSync()) as Map<String, dynamic>;
    final width = data['width'] as int, height = data['height'] as int;
    final calibration = BoardCalibration.fromJson(data['calibration'] as Map<String, dynamic>)!;
    final truth = (data['darts'] as List).cast<Map<String, dynamic>>();
    expect([for (final d in truth) _appLabel(d['label'] as String)], truthLabels);

    final detector = DartDetector();
    final detections = <(int, Offset?)>[];
    var frameNo = 0;
    var cleared = 0;
    for (final state in (data['states'] as List).cast<Map<String, dynamic>>()) {
      final frame = _loadFrame('$fixture/${state['image']}');
      expect((frame.width, frame.height), (width, height));
      for (var i = 0; i < (state['count'] as int); i++) {
        final result = detector.update(frame);
        if (result.event == DetectionEvent.dart) detections.add((frameNo, result.tip));
        if (result.event == DetectionEvent.boardCleared) cleared++;
        frameNo++;
      }
    }

    // Jeder echte Dart bekommt die erste Erkennung zwischen seinem Auftreffen und dem nächsten Dart
    final labels = <String?>[];
    final errors = <double>[];
    var next = 0;
    for (var i = 0; i < truth.length; i++) {
      final start = truth[i]['frame'] as int;
      final end = i + 1 < truth.length ? truth[i + 1]['frame'] as int : 1 << 30;
      while (next < detections.length && detections[next].$1 < start) {
        next++;
      }
      if (next < detections.length && detections[next].$1 < end && detections[next].$2 != null) {
        final tip = detections[next].$2!;
        final normalized = Offset(tip.dx / width, tip.dy / height);
        labels.add(calibration.scoreAt(normalized).label);
        final t = truth[i]['tip_normalized'] as List;
        final trueMm = calibration.toBoard(Offset((t[0] as num).toDouble(), (t[1] as num).toDouble()));
        errors.add((calibration.toBoard(normalized) - trueMm).distance);
        next++;
      } else {
        labels.add(null);
      }
    }

    expect(detections.length, 6, reason: 'keine Fehlerkennungen');
    expect(cleared, 2, reason: 'nach jeder Aufnahme werden die Darts gezogen');
    expect(labels, pythonLabels);
    // Die vier richtig gezählten Darts liegen wie in Python nur wenige mm daneben
    for (var i = 0; i < 4; i++) {
      expect(errors[i], lessThan(4), reason: 'Dart $i: ${errors[i].toStringAsFixed(1)} mm');
    }
  });
}

/// Python schreibt "MISS" und "BULL", die App "Miss" und "Bull".
String _appLabel(String python) => switch (python) { 'MISS' => 'Miss', 'BULL' => 'Bull', _ => python };

Frame _loadFrame(String path) {
  final decoded = img.decodeJpg(File(path).readAsBytesSync())!;
  final rgba = decoded.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return Frame(decoded.width, decoded.height, Uint8List.fromList(rgba));
}
