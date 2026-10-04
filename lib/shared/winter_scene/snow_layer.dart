import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// A bounded snowfall.
///
/// [count] flakes with fixed, seeded parameters; each frame only moves
/// them, so a frame costs [count] circle draws and nothing else. Flakes fall
/// a whole number of times per ambient loop, so the loop is seamless. With
/// [time] null (reduced motion) the flakes are drawn once, still.
class SnowPainter extends CustomPainter {
  SnowPainter({required this.count, required this.color, this.time})
    : _flakes = _flakesFor(count),
      super(repaint: time);

  /// Upper bound on flakes, whatever the size.
  static const int maxFlakes = 60;

  final int count;
  final Color color;
  final Animation<double>? time;
  final List<_Flake> _flakes;

  static final Map<int, List<_Flake>> _cache = {};

  static List<_Flake> _flakesFor(int count) =>
      _cache.putIfAbsent(count.clamp(0, maxFlakes), () {
        final random = math.Random(42);
        return List.generate(count.clamp(0, maxFlakes), (_) {
          return _Flake(
            x: random.nextDouble(),
            y: random.nextDouble(),
            falls: 1 + random.nextInt(3),
            sway: 2 + random.nextDouble() * 6,
            swayCycles: 1 + random.nextInt(2),
            phase: random.nextDouble(),
            radius: 0.6 + random.nextDouble() * 1.3,
            alpha: 0.35 + random.nextDouble() * 0.5,
          );
        });
      });

  @override
  void paint(Canvas canvas, Size size) {
    final t = time?.value ?? 0;
    final paint = Paint();
    final height = size.height + 8;
    for (final flake in _flakes) {
      final y = ((flake.y + t * flake.falls) % 1) * height - 4;
      final x =
          flake.x * size.width +
          flake.sway *
              math.sin(2 * math.pi * (flake.phase + t * flake.swayCycles));
      paint.color = color.withValues(alpha: flake.alpha);
      canvas.drawCircle(Offset(x, y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(SnowPainter old) =>
      old.count != count || old.color != color || old.time != time;
}

final class _Flake {
  const _Flake({
    required this.x,
    required this.y,
    required this.falls,
    required this.sway,
    required this.swayCycles,
    required this.phase,
    required this.radius,
    required this.alpha,
  });

  final double x;
  final double y;

  /// Times the flake crosses the height per loop.
  final int falls;
  final double sway;
  final int swayCycles;
  final double phase;
  final double radius;
  final double alpha;
}
