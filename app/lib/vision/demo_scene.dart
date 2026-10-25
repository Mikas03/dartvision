import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'calibration.dart';
import 'detector.dart';

/// Spielt die synthetische Testszene (assets/demo_scene, erzeugt vom Python-Generator) wie ein
/// Kamerabild ab. So lässt sich die Erkennung ohne Kamera und ohne Dartboard ausprobieren.
class DemoScene {
  DemoScene._(this.width, this.height, this.calibration, this._states);

  static const _dir = 'assets/demo_scene';

  /// Die Szene ist für 30 Bilder/s erzeugt; die App wertet etwa 10 Bilder/s aus.
  static const _speedup = 3;

  final int width;
  final int height;
  final BoardCalibration calibration;
  final List<(String, int)> _states;

  int _state = -1;
  int _remaining = 0;
  ui.Image? _image;
  Frame? _frame;

  ui.Image? get image => _image;

  static Future<DemoScene> load() async {
    final data = jsonDecode(await rootBundle.loadString('$_dir/scenario.json')) as Map<String, dynamic>;
    return DemoScene._(
      data['width'] as int,
      data['height'] as int,
      BoardCalibration.fromJson(data['calibration'] as Map<String, dynamic>)!,
      [
        for (final s in (data['states'] as List).cast<Map<String, dynamic>>())
          (s['image'] as String, ((s['count'] as int) / _speedup).round().clamp(1, 1 << 20)),
      ],
    );
  }

  /// Nächstes Bild; nach dem Ende beginnt die Szene von vorn.
  Future<Frame> next() async {
    if (_remaining == 0 || _frame == null) {
      _state = (_state + 1) % _states.length;
      final (name, count) = _states[_state];
      _remaining = count;
      await _decode(name);
    }
    _remaining--;
    return _frame!;
  }

  Future<void> _decode(String name) async {
    final bytes = await rootBundle.load('$_dir/$name');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    _image?.dispose();
    _image = image;
    _frame = Frame(image.width, image.height, rgba!.buffer.asUint8List());
  }

  void dispose() => _image?.dispose();
}
