import 'package:flutter/rendering.dart';

import '../../app/theme/winter_tokens.dart';
import 'scene_geometry.dart';
import 'scene_progress.dart';

/// Warm light in the cold world: the camp (Day 7, grows on Day 14), the
/// summit shelter (Day 75) and the summit itself (Day 92). Brighter as
/// today's [SceneProgress.warmth] grows.
class CampPainter extends CustomPainter {
  const CampPainter({required this.scene, required this.colors});

  final SceneProgress scene;
  final WinterColors colors;

  Color get _light => scene.recovery ? colors.recovery : colors.warmLight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    Offset p(Offset n) => SceneGeometry.at(size, n);

    if (scene.campLit) {
      final glow = 0.45 + 0.4 * scene.warmth;
      _glow(
        canvas,
        p(SceneGeometry.fire),
        w * (0.08 + 0.04 * scene.warmth),
        _light.withValues(alpha: glow),
      );
      _tent(canvas, p(SceneGeometry.tent), w * 0.07, lit: true);
      _flame(canvas, p(SceneGeometry.fire), w * 0.012);
      if (scene.forestCamp) {
        _glow(
          canvas,
          p(SceneGeometry.forestTent),
          w * 0.05,
          _light.withValues(alpha: glow * 0.6),
        );
        _tent(canvas, p(SceneGeometry.forestTent), w * 0.06, lit: true);
      }
    }

    if (scene.shelterGlow > 0) {
      final shelter = p(SceneGeometry.shelter);
      _glow(
        canvas,
        shelter,
        w * 0.06,
        colors.warmLight.withValues(alpha: 0.7 * scene.shelterGlow),
      );
      _cabin(canvas, shelter, w * 0.04);
    }

    if (scene.summitRevealed) {
      final summit = p(SceneGeometry.summit);
      _glow(
        canvas,
        summit,
        w * 0.1,
        colors.warmLight.withValues(alpha: 0.28 + 0.2 * scene.warmth),
      );
      final pole = Paint()
        ..color = colors.snow
        ..strokeWidth = 1.2;
      final top = summit - Offset(0, w * 0.045);
      canvas.drawLine(summit, top, pole);
      canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(top.dx + w * 0.03, top.dy + w * 0.009)
          ..lineTo(top.dx, top.dy + w * 0.018)
          ..close(),
        Paint()..color = colors.warmLight,
      );
    }
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _tent(Canvas canvas, Offset base, double width, {required bool lit}) {
    final height = width * 0.75;
    final body = Path()
      ..moveTo(base.dx - width / 2, base.dy)
      ..lineTo(base.dx, base.dy - height)
      ..lineTo(base.dx + width / 2, base.dy)
      ..close();
    canvas.drawPath(body, Paint()..color = colors.mountainMid);
    final door = Path()
      ..moveTo(base.dx - width * 0.14, base.dy)
      ..lineTo(base.dx, base.dy - height * 0.55)
      ..lineTo(base.dx + width * 0.14, base.dy)
      ..close();
    canvas.drawPath(
      door,
      Paint()..color = _light.withValues(alpha: lit ? 0.85 : 0.2),
    );
    canvas.drawLine(
      base - Offset(0, height),
      base - Offset(width * 0.08, height * 1.18),
      Paint()
        ..color = colors.snow.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
  }

  void _flame(Canvas canvas, Offset base, double size) {
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - size, base.dy)
        ..quadraticBezierTo(
          base.dx - size * 0.6,
          base.dy - size * 1.6,
          base.dx,
          base.dy - size * 2.6,
        )
        ..quadraticBezierTo(
          base.dx + size * 0.6,
          base.dy - size * 1.6,
          base.dx + size,
          base.dy,
        )
        ..close(),
      Paint()..color = colors.ember,
    );
  }

  void _cabin(Canvas canvas, Offset base, double width) {
    final height = width * 0.6;
    final wall = Rect.fromLTWH(
      base.dx - width / 2,
      base.dy - height,
      width,
      height,
    );
    canvas.drawRect(wall, Paint()..color = colors.mountainNear);
    canvas.drawPath(
      Path()
        ..moveTo(wall.left - width * 0.12, wall.top)
        ..lineTo(base.dx, wall.top - height * 0.7)
        ..lineTo(wall.right + width * 0.12, wall.top)
        ..close(),
      Paint()..color = colors.snow.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: wall.center,
        width: width * 0.28,
        height: height * 0.4,
      ),
      Paint()
        ..color = colors.warmLight.withValues(
          alpha: 0.5 + 0.5 * scene.shelterGlow,
        ),
    );
  }

  @override
  bool shouldRepaint(CampPainter old) =>
      old.colors != colors || old.scene != scene;
}

/// The trail to the summit: the whole way faintly dashed, and the part
/// already walked ([SceneProgress.journey]) lit, ending at a small light
/// for the traveller.
class TrailPainter extends CustomPainter {
  const TrailPainter({
    required this.scene,
    required this.colors,
    this.reveal = 1,
  });

  final SceneProgress scene;
  final WinterColors colors;

  /// `0..1` of the walked part to draw, for the summit reveal animation.
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final metric = SceneGeometry.trail(size).computeMetrics().first;
    final length = metric.length;

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = colors.snow.withValues(alpha: 0.22);
    for (var d = 0.0; d < length; d += 9) {
      canvas.drawPath(metric.extractPath(d, d + 4), dash);
    }

    final walked = length * scene.journey * reveal.clamp(0.0, 1.0);
    if (walked <= 0) return;
    final base = scene.recovery ? colors.recovery : colors.accentSecondary;
    final color = Color.lerp(base, colors.warmLight, scene.warmth * 0.45)!;
    final lit = metric.extractPath(0, walked);
    canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..color = color.withValues(alpha: 0.35 + 0.35 * scene.dayCompletion),
    );
    canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(color, colors.snow, 0.35)!,
    );

    final at = metric.getTangentForOffset(walked)?.position;
    if (at == null) return;
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: at, radius: 7)),
    );
    canvas.drawCircle(at, 2.2, Paint()..color = colors.snow);
  }

  @override
  bool shouldRepaint(TrailPainter old) =>
      old.colors != colors || old.scene != scene || old.reveal != reveal;
}
