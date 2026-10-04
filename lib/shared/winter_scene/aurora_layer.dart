import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/theme/winter_tokens.dart';

/// A restrained aurora: two soft curtains high in the sky.
///
/// The curtains are painted once (cached behind a [RepaintBoundary]); the
/// ambient [animation] only drifts and breathes them with a transform and
/// opacity, so it never repaints the shapes. Without an animation (reduced
/// motion) the aurora is static.
class AuroraLayer extends StatelessWidget {
  const AuroraLayer({
    super.key,
    required this.intensity,
    required this.colors,
    this.animation,
  });

  /// `0..1`; nothing is drawn at 0.
  final double intensity;
  final WinterColors colors;
  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    if (intensity <= 0) return const SizedBox.shrink();
    final curtains = RepaintBoundary(
      child: CustomPaint(
        painter: AuroraPainter(colors: colors, intensity: intensity),
        size: Size.infinite,
      ),
    );
    final animation = this.animation;
    if (animation == null) return curtains;
    return AnimatedBuilder(
      animation: animation,
      child: curtains,
      builder: (context, child) {
        final phase = animation.value * 2 * math.pi;
        return Opacity(
          opacity: 0.8 + 0.2 * math.sin(phase * 2),
          child: FractionalTranslation(
            translation: Offset(0.025 * math.sin(phase), 0),
            child: child,
          ),
        );
      },
    );
  }
}

class AuroraPainter extends CustomPainter {
  const AuroraPainter({required this.colors, required this.intensity});

  final WinterColors colors;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    _curtain(
      canvas,
      size,
      color: colors.auroraGreen,
      top: 0.1,
      depth: 0.2,
      waves: 1.3,
      shift: 0.4,
      alpha: 0.42 * intensity,
    );
    _curtain(
      canvas,
      size,
      color: colors.auroraViolet,
      top: 0.04,
      depth: 0.1,
      waves: 1.8,
      shift: 2.1,
      alpha: 0.22 * intensity,
    );
  }

  void _curtain(
    Canvas canvas,
    Size size, {
    required Color color,
    required double top,
    required double depth,
    required double waves,
    required double shift,
    required double alpha,
  }) {
    final w = size.width, h = size.height;
    double edge(double x) =>
        (top + depth + 0.05 * math.sin(x / w * 2 * math.pi * waves + shift)) *
        h;
    final path = Path()..moveTo(0, top * h);
    for (var x = 0.0; x <= w; x += w / 24) {
      path.lineTo(x, top * h + 0.03 * h * math.sin(x / w * 7 + shift));
    }
    for (var x = w; x >= 0; x -= w / 24) {
      path.lineTo(x, edge(x));
    }
    path.close();
    final bounds = Rect.fromLTRB(0, top * h, w, (top + depth + 0.06) * h);
    canvas.drawPath(
      path,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.4),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(AuroraPainter old) =>
      old.colors != colors || old.intensity != intensity;
}
