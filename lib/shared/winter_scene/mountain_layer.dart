import 'package:flutter/rendering.dart';

import '../../app/theme/winter_tokens.dart';
import 'scene_geometry.dart';
import 'scene_progress.dart';

/// Layered snowy mountains: the far range with the summit, the middle
/// ridge, the near hills with pines, and fog between them.
///
/// The milestone decides what shows: the ridge comes out of the fog on Day
/// 30, the high ridge catches light from Day 60, and the fog over the
/// summit thins as the arc goes on. Static: repaints only when the scene
/// changes.
class MountainPainter extends CustomPainter {
  const MountainPainter({required this.scene, required this.colors});

  final SceneProgress scene;
  final WinterColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(Offset n) => SceneGeometry.at(size, n);

    // Far range with the summit.
    final far = _range(size, SceneGeometry.farRange, bottom: h * 0.75);
    canvas.drawPath(far, Paint()..color = colors.mountainFar);
    final cap = Paint()..color = colors.snow.withValues(alpha: 0.85);
    for (final peak in SceneGeometry.farRange) {
      if (peak.dy > 0.36) continue;
      final isSummit = peak == SceneGeometry.summit;
      final alpha = isSummit ? 0.4 + 0.6 * scene.summitReveal : 0.75;
      cap.color = colors.snow.withValues(alpha: alpha);
      canvas.drawPath(_snowcap(p(peak), w, h, isSummit ? 0.075 : 0.05), cap);
    }

    // Fog over the summit thins as the arc progresses.
    final summit = p(SceneGeometry.summit);
    final fogAlpha = (1 - scene.summitReveal) * 0.8;
    if (fogAlpha > 0) {
      canvas.drawOval(
        Rect.fromCenter(
          center: summit + Offset(0, h * 0.05),
          width: w * 0.42,
          height: h * 0.2,
        ),
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
          ..color = colors.fog.withValues(alpha: fogAlpha * 0.5),
      );
    }

    // Fog band between the far range and the ridge.
    final band = Rect.fromLTRB(0, h * 0.4, w, h * 0.7);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.fog.withValues(alpha: 0),
            colors.fog.withValues(alpha: 0.14),
            colors.fog.withValues(alpha: 0),
          ],
        ).createShader(band),
    );

    // Middle ridge: veiled until Day 30, rim-lit from Day 60.
    final ridge = _range(size, SceneGeometry.midRidge, bottom: h);
    final ridgeColor = Color.lerp(
      colors.mountainFar,
      colors.mountainMid,
      scene.ridgeVisible ? 1 : 0.35,
    )!;
    canvas.drawPath(ridge, Paint()..color = ridgeColor);
    if (scene.highRidge) {
      canvas.drawPath(
        _outline(size, SceneGeometry.midRidge),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = colors.snow.withValues(alpha: 0.35),
      );
    }

    // Near hills with a snowy edge.
    final hill = Path()..moveTo(0, h * SceneGeometry.hillAt(0));
    for (var x = 0.0; x <= 1.0001; x += 0.05) {
      hill.lineTo(x * w, h * SceneGeometry.hillAt(x));
    }
    final hillEdge = Path.from(hill);
    hill
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = colors.mountainNear);
    canvas.drawPath(
      hillEdge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colors.snow.withValues(alpha: 0.28),
    );

    // Pines; the forest camp adds more.
    final pine = Paint()
      ..color = Color.lerp(colors.mountainNear, colors.skyTop, 0.4)!;
    final tip = Paint()..color = colors.snow.withValues(alpha: 0.5);
    final trees = [
      ...SceneGeometry.trees,
      if (scene.forestCamp) ...SceneGeometry.forestTrees,
    ];
    for (final (x, height) in trees) {
      _pine(
        canvas,
        Offset(x * w, h * SceneGeometry.hillAt(x) + 2),
        height * h,
        pine,
        tip,
      );
    }
  }

  Path _range(Size size, List<Offset> outline, {required double bottom}) =>
      _outline(size, outline)
        ..lineTo(size.width, bottom)
        ..lineTo(0, bottom)
        ..close();

  Path _outline(Size size, List<Offset> outline) {
    final path = Path();
    for (final (i, n) in outline.indexed) {
      final point = SceneGeometry.at(size, n);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  /// A jagged snowcap hanging below [peak].
  Path _snowcap(Offset peak, double w, double h, double depth) {
    final d = depth * h;
    return Path()
      ..moveTo(peak.dx, peak.dy)
      ..lineTo(peak.dx + d * 0.9, peak.dy + d)
      ..lineTo(peak.dx + d * 0.35, peak.dy + d * 0.7)
      ..lineTo(peak.dx, peak.dy + d * 1.05)
      ..lineTo(peak.dx - d * 0.4, peak.dy + d * 0.72)
      ..lineTo(peak.dx - d * 0.95, peak.dy + d)
      ..close();
  }

  void _pine(Canvas canvas, Offset base, double height, Paint body, Paint tip) {
    final width = height * 0.45;
    for (var tier = 0; tier < 3; tier++) {
      final top = base.dy - height + tier * height * 0.28;
      final bottom = top + height * 0.5;
      final half = width * (0.45 + tier * 0.28) / 2;
      final path = Path()
        ..moveTo(base.dx, top)
        ..lineTo(base.dx + half, bottom)
        ..lineTo(base.dx - half, bottom)
        ..close();
      canvas.drawPath(path, body);
    }
    canvas.drawCircle(Offset(base.dx, base.dy - height + 1.5), 1.2, tip);
  }

  @override
  bool shouldRepaint(MountainPainter old) =>
      old.colors != colors || old.scene.milestone != scene.milestone;
}
