import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../app/theme/winter_tokens.dart';

/// Night sky: a deep gradient with a cold horizon glow and fixed stars.
///
/// [warmth] (`0..1`) tints the horizon towards warm light; [recovery] uses
/// the softer Minimum Day tint instead. Static: it only repaints when its
/// inputs change.
class SkyPainter extends CustomPainter {
  const SkyPainter({
    required this.colors,
    this.warmth = 0,
    this.recovery = false,
    this.starCount = 36,
  });

  final WinterColors colors;
  final double warmth;
  final bool recovery;
  final int starCount;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final warm = recovery ? colors.recovery : colors.warmLight;
    final horizon = Color.lerp(colors.skyHorizon, warm, warmth * 0.22)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(0, -1),
          end: const Alignment(0, 1),
          colors: [colors.skyTop, colors.backgroundTop, horizon],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );

    final random = math.Random(7);
    final star = Paint();
    for (var i = 0; i < starCount; i++) {
      final x = random.nextDouble() * size.width;
      // Denser and brighter high up, fading towards the horizon.
      final y = math.pow(random.nextDouble(), 1.6) * size.height * 0.62;
      final radius = 0.4 + random.nextDouble() * 0.9;
      final alpha = (0.25 + random.nextDouble() * 0.6) * (1 - y / size.height);
      star.color = colors.snow.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, star);
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.colors != colors ||
      old.warmth != warmth ||
      old.recovery != recovery ||
      old.starCount != starCount;
}
