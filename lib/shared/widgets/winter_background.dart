import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';
import '../winter_scene/scene_geometry.dart';
import '../winter_scene/sky_layer.dart';

/// Full-screen night sky with a faint mountain horizon, behind every
/// screen. Static and cheap: painted once into its own layer. Screens that
/// show the living world use `WinterScene` instead.
class WinterBackground extends StatelessWidget {
  const WinterBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: SkyPainter(colors: colors, starCount: 48),
            foregroundPainter: _HorizonPainter(colors),
          ),
        ),
        child,
      ],
    );
  }
}

/// A low, faded mountain silhouette along the bottom of the screen.
class _HorizonPainter extends CustomPainter {
  const _HorizonPainter(this.colors);

  final WinterColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * 0.72;
    final span = size.height - top;
    final path = Path()..moveTo(0, size.height);
    for (final n in SceneGeometry.farRange) {
      path.lineTo(n.dx * size.width, top + n.dy * span);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    final rect = Rect.fromLTRB(0, top, size.width, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.mountainFar.withValues(alpha: 0.55),
            colors.background,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HorizonPainter old) => old.colors != colors;
}
