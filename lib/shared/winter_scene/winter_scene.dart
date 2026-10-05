import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../app/theme/winter_tokens.dart';
import 'aurora_layer.dart';
import 'cabin_layer.dart';
import 'mountain_layer.dart';
import 'scene_progress.dart';
import 'sky_layer.dart';
import 'snow_layer.dart';

/// The cinematic Winter Arc world: sky, aurora, mountains, camp light, the
/// trail and snowfall, at the stage described by [scene].
///
/// Decorative only: excluded from semantics and hit testing, and never the
/// only carrier of information. Each layer has its own [RepaintBoundary];
/// the static layers repaint only when [scene] changes.
///
/// Ambient motion (snow, aurora drift) runs on one ticker that stops when
/// the platform asks for reduced motion, when the app is not in the
/// foreground, and (through [TickerMode]) when the scene is on a hidden tab
/// or under another route.
class WinterScene extends ConsumerStatefulWidget {
  const WinterScene({
    super.key,
    required this.scene,
    this.showTrail = true,
    this.maxSnow = 40,
    this.trailReveal = 1,
  });

  final SceneProgress scene;
  final bool showTrail;

  /// Upper bound on snowflakes; fewer are used on small areas.
  final int maxSnow;

  /// `0..1` of the walked trail to light (for a reveal animation).
  final double trailReveal;

  @override
  ConsumerState<WinterScene> createState() => _WinterSceneState();
}

class _WinterSceneState extends ConsumerState<WinterScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: WinterDurations.ambientLoop,
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = _isForeground(state);
    if (foreground != _foreground) setState(() => _foreground = foreground);
  }

  static bool _isForeground(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ambient.dispose();
    super.dispose();
  }

  /// Starts or stops the ambient loop; returns the animation to drive the
  /// layers with, or null when the scene must be still.
  Animation<double>? _ambientTime() {
    final run =
        _foreground &&
        context.motion.ambient &&
        ref.watch(ambientMotionProvider);
    if (run && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!run && _ambient.isAnimating) {
      _ambient.stop();
    }
    return run ? _ambient : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final time = _ambientTime();
    final scene = widget.scene;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          // Light warms (or cools) smoothly after a persisted change.
          tween: Tween(end: scene.warmth),
          duration: context.motion.celebration,
          curve: Curves.easeOutCubic,
          builder: (context, warmth, _) {
            final lit = scene.withWarmth(warmth);
            return LayoutBuilder(
              builder: (context, constraints) {
                final area = constraints.maxWidth * constraints.maxHeight;
                final flakes = (area / 7000).round().clamp(8, widget.maxSnow);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: SkyPainter(
                          colors: colors,
                          warmth: lit.warmth,
                          recovery: lit.recovery,
                        ),
                      ),
                    ),
                    // Its drift repaints every ambient frame; the boundary
                    // keeps that from spreading to the screen above.
                    RepaintBoundary(
                      child: AuroraLayer(
                        intensity: lit.aurora,
                        colors: colors,
                        animation: time,
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: MountainPainter(scene: lit, colors: colors),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: CampPainter(scene: lit, colors: colors),
                      ),
                    ),
                    if (widget.showTrail)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: TrailPainter(
                            scene: lit,
                            colors: colors,
                            reveal: widget.trailReveal,
                          ),
                        ),
                      ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: SnowPainter(
                          count: flakes,
                          color: colors.snow,
                          time: time,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
