import 'dart:ui';

/// Shared layout of the winter world in normalised (0..1) coordinates, so
/// the mountains, camps and trail of every layer line up at any size.
abstract final class SceneGeometry {
  /// The summit peak.
  static const summit = Offset(0.68, 0.17);

  /// Far range outline, left to right (x, y).
  static const farRange = [
    Offset(0, 0.5),
    Offset(0.08, 0.4),
    Offset(0.17, 0.46),
    Offset(0.27, 0.3),
    Offset(0.36, 0.42),
    Offset(0.46, 0.33),
    Offset(0.55, 0.39),
    summit,
    Offset(0.79, 0.34),
    Offset(0.88, 0.28),
    Offset(1, 0.42),
  ];

  /// Middle ridge outline.
  static const midRidge = [
    Offset(0, 0.62),
    Offset(0.12, 0.52),
    Offset(0.24, 0.58),
    Offset(0.38, 0.48),
    Offset(0.5, 0.56),
    Offset(0.63, 0.5),
    Offset(0.76, 0.58),
    Offset(0.9, 0.49),
    Offset(1, 0.56),
  ];

  /// First camp tent and fire (Day 7).
  static const tent = Offset(0.22, 0.87);
  static const fire = Offset(0.28, 0.89);

  /// Second tent of the forest camp (Day 14).
  static const forestTent = Offset(0.12, 0.9);

  /// Summit shelter (Day 75).
  static const shelter = Offset(0.615, 0.235);

  /// Pine trees on the near hills (x, height), and those the forest camp
  /// adds.
  static const trees = [
    (0.04, 0.11),
    (0.08, 0.08),
    (0.33, 0.09),
    (0.82, 0.1),
    (0.87, 0.13),
    (0.93, 0.09),
  ];
  static const forestTrees = [(0.42, 0.08), (0.74, 0.09), (0.97, 0.1)];

  static Offset at(Size size, Offset n) =>
      Offset(n.dx * size.width, n.dy * size.height);

  /// Height of the near hills' top edge at [x] (normalised).
  static double hillAt(double x) {
    // Matches the quadratic curve drawn by the mountain layer.
    const a = 0.8, b = 0.74, c = 0.83;
    return (1 - x) * (1 - x) * a + 2 * (1 - x) * x * b + x * x * c;
  }

  /// The winding trail from the foreground up to the summit.
  static Path trail(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(0.16 * w, 1.02 * h)
      ..cubicTo(0.42 * w, 0.93 * h, 0.1 * w, 0.8 * h, 0.34 * w, 0.72 * h)
      ..cubicTo(0.55 * w, 0.65 * h, 0.3 * w, 0.55 * h, 0.5 * w, 0.46 * h)
      ..cubicTo(0.66 * w, 0.39 * h, 0.52 * w, 0.3 * h, 0.62 * w, 0.24 * h)
      ..quadraticBezierTo(0.66 * w, 0.2 * h, summit.dx * w, summit.dy * h);
  }
}
