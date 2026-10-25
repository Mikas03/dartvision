import 'dart:ui';

/// Projektive Abbildung (3x3-Matrix) zwischen zwei Ebenen, z. B. Scheibe (mm) -> Kamerabild.
class Homography {
  const Homography(this.m) : assert(m.length == 9);

  /// Matrix zeilenweise.
  final List<double> m;

  /// Berechnet die Abbildung, die die 4 Punkte [src] auf die 4 Punkte [dst] abbildet.
  factory Homography.fromPoints(List<Offset> src, List<Offset> dst) {
    if (src.length != 4 || dst.length != 4) {
      throw ArgumentError('Genau 4 Punktpaare nötig');
    }
    // Lineares Gleichungssystem A·h = b für h0..h7 (h8 = 1)
    final a = <List<double>>[];
    final b = <double>[];
    for (var i = 0; i < 4; i++) {
      final (x, y) = (src[i].dx, src[i].dy);
      final (u, v) = (dst[i].dx, dst[i].dy);
      a.add([x, y, 1, 0, 0, 0, -x * u, -y * u]);
      b.add(u);
      a.add([0, 0, 0, x, y, 1, -x * v, -y * v]);
      b.add(v);
    }
    final h = _solve(a, b);
    return Homography([...h, 1]);
  }

  Offset map(Offset p) {
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    return Offset(
      (m[0] * p.dx + m[1] * p.dy + m[2]) / w,
      (m[3] * p.dx + m[4] * p.dy + m[5]) / w,
    );
  }

  Homography inverse() {
    final [a, b, c, d, e, f, g, h, i] = m;
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-12) throw StateError('Homographie ist nicht invertierbar');
    return Homography([
      (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
      (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
      (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det,
    ]);
  }

  /// Gauß-Elimination mit Spaltenpivotsuche.
  static List<double> _solve(List<List<double>> a, List<double> b) {
    final n = b.length;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var row = col + 1; row < n; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw StateError('Punkte liegen ungünstig (z. B. drei auf einer Linie)');
      }
      final rowTmp = a[col];
      a[col] = a[pivot];
      a[pivot] = rowTmp;
      final bTmp = b[col];
      b[col] = b[pivot];
      b[pivot] = bTmp;
      for (var row = col + 1; row < n; row++) {
        final factor = a[row][col] / a[col][col];
        for (var k = col; k < n; k++) {
          a[row][k] -= factor * a[col][k];
        }
        b[row] -= factor * b[col];
      }
    }
    final x = List<double>.filled(n, 0);
    for (var row = n - 1; row >= 0; row--) {
      var sum = b[row];
      for (var k = row + 1; k < n; k++) {
        sum -= a[row][k] * x[k];
      }
      x[row] = sum / a[row][row];
    }
    return x;
  }
}
