/// Ein getroffenes Feld auf der Scheibe.
class Hit {
  const Hit(this.segment, this.multiplier)
      : assert(segment == 0 || segment == 25 || (segment >= 1 && segment <= 20)),
        assert(multiplier >= 0 && multiplier <= 3),
        assert(segment != 25 || multiplier <= 2);

  /// 1-20, 25 für Bull, 0 für daneben.
  final int segment;

  /// 0 (daneben), 1, 2 oder 3.
  final int multiplier;

  static const miss = Hit(0, 0);
  static const outerBull = Hit(25, 1);
  static const bull = Hit(25, 2);

  const Hit.single(int segment) : this(segment, 1);
  const Hit.double(int segment) : this(segment, 2);
  const Hit.triple(int segment) : this(segment, 3);

  int get value => segment * multiplier;
  bool get isDouble => multiplier == 2;

  String get label {
    if (multiplier == 0) return 'Miss';
    if (segment == 25) return multiplier == 2 ? 'Bull' : '25';
    return switch (multiplier) { 2 => 'D$segment', 3 => 'T$segment', _ => '$segment' };
  }

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is Hit && other.segment == segment && other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(segment, multiplier);
}
