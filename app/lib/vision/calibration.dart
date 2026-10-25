import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/board.dart' as board;
import '../models/hit.dart';
import 'homography.dart';

/// Reihenfolge, in der die Kalibrierpunkte angetippt werden.
const calibrationOrder = [20, 6, 3, 11];

/// Mitte der Außenkante des Doppelrings bei 20, 6, 3, 11 (oben, rechts, unten, links), in mm.
const calibrationPointsMm = {
  20: Offset(0, board.rDoubleOuter),
  6: Offset(board.rDoubleOuter, 0),
  3: Offset(0, -board.rDoubleOuter),
  11: Offset(-board.rDoubleOuter, 0),
};

/// Kalibrierung: 4 Punkte im Kamerabild, normiert auf 0..1 (unabhängig von der Auflösung).
class BoardCalibration {
  BoardCalibration(List<Offset> points)
      : points = List.unmodifiable(points),
        boardToImage = Homography.fromPoints(
          [for (final s in calibrationOrder) calibrationPointsMm[s]!],
          points,
        ) {
    imageToBoard = boardToImage.inverse();
  }

  /// Bildpunkte (normiert) in der Reihenfolge [calibrationOrder].
  final List<Offset> points;

  /// Scheibe (mm) -> Bild (normiert).
  final Homography boardToImage;

  /// Bild (normiert) -> Scheibe (mm).
  late final Homography imageToBoard;

  Offset toImage(Offset mm) => boardToImage.map(mm);
  Offset toBoard(Offset normalized) => imageToBoard.map(normalized);
  Hit scoreAt(Offset normalized) {
    final mm = toBoard(normalized);
    return board.scoreAt(mm.dx, mm.dy);
  }

  /// Export für den Python-Prototyp (dartvision.calibration lädt dieses Format).
  Map<String, Object> toJson({Size? videoSize}) => {
        'order': calibrationOrder,
        'points_normalized': [for (final p in points) [p.dx, p.dy]],
        if (videoSize != null) 'width': videoSize.width.round(),
        if (videoSize != null) 'height': videoSize.height.round(),
      };

  static BoardCalibration? fromJson(Map<String, dynamic> json) {
    final raw = json['points_normalized'];
    if (raw is! List || raw.length != 4) return null;
    return BoardCalibration([
      for (final p in raw) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ]);
  }

  static const _prefsKey = 'board_calibration';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }

  static Future<BoardCalibration?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // kaputte oder alte Daten -> neu kalibrieren
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
