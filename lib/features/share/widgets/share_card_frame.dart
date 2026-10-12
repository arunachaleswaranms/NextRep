import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../shared/winter_scene/aurora_layer.dart';
import '../../../shared/winter_scene/mountain_layer.dart';
import '../../../shared/winter_scene/scene_progress.dart';
import '../../../shared/winter_scene/sky_layer.dart';
import '../share_card_capture.dart';

/// The shared look of every share card: a still night sky with aurora and
/// mountains at the top, the NextRep mark, the card's [child], a [tagline]
/// and a quiet "Made with NextRep" at the bottom. No link is printed.
///
/// Laid out on the fixed [ShareCardCapture.canvas] with a fixed type scale,
/// independent of the phone's width and text size: it is a designed image,
/// not an interactive surface (the preview around it scales with the
/// user's text size). Nothing animates inside a card, so the exported PNG
/// is always its final state.
class ShareCardFrame extends StatelessWidget {
  const ShareCardFrame({
    super.key,
    required this.scene,
    required this.label,
    required this.tagline,
    required this.child,
  });

  /// The winter world shown at the top (stage and light only).
  final SceneProgress scene;

  /// What kind of card this is, top right ("TODAY", "MY ARC", ...).
  final String label;
  final String tagline;
  final Widget child;

  static const double _backdropHeight = 210;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.noScaling, boldText: false),
      child: DefaultTextStyle(
        // The app's typeface, at the card's own fixed sizes.
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(
              color: colors.textPrimary,
              fontSize: 12,
              height: 1.2,
              decoration: TextDecoration.none,
            ),
        child: SizedBox.fromSize(
          size: ShareCardCapture.canvas,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.skyTop, colors.background],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: _backdropHeight,
                  child: _Backdrop(scene: scene),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Brand(label: label),
                      Expanded(child: child),
                      const SizedBox(height: 14),
                      _Footer(tagline: tagline),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.scene});

  final SceneProgress scene;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: SkyPainter(
            colors: colors,
            warmth: scene.warmth,
            recovery: scene.recovery,
            starCount: 40,
          ),
        ),
        CustomPaint(painter: AuroraPainter(colors: colors, intensity: 0.8)),
        // The mountains sit low, behind the bottom of the headline.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 150,
          child: CustomPaint(
            painter: MountainPainter(scene: scene, colors: colors),
          ),
        ),
        // Fades the world into the card so text below stays high contrast.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.skyTop.withValues(alpha: 0.1),
                colors.background.withValues(alpha: 0.45),
                colors.background,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Row(
      children: [
        Icon(Icons.landscape_rounded, size: 16, color: colors.accentSecondary),
        const SizedBox(width: 6),
        const Text(
          'NEXTREP',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        const Spacer(),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: colors.snow.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.tagline});

  final String tagline;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Column(
      children: [
        Text(
          tagline,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: colors.snow,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 1,
          width: 48,
          color: colors.glassBorder,
          margin: const EdgeInsets.only(bottom: 8),
        ),
        Text(
          'Made with NextRep',
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.3,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A small rounded status label on a card, e.g. "MINIMUM DAY".
class ShareCardPill extends StatelessWidget {
  const ShareCardPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(WinterRadii.pill),
      border: Border.all(color: color.withValues(alpha: 0.7)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: color,
      ),
    ),
  );
}
