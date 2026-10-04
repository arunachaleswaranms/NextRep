import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Rounded glass surface used for list rows and panels over the scene.
///
/// Translucency (no blur) keeps it cheap to composite over the animated
/// world while staying readable.
class WinterCard extends StatelessWidget {
  const WinterCard({
    super.key,
    required this.child,
    this.highlighted = false,
    this.accent,
    this.onTap,
    this.padding = const EdgeInsets.all(WinterSpacing.md),
  });

  final Widget child;

  /// Draws the accent border and a soft glow, e.g. for a completed habit.
  final bool highlighted;

  /// Accent for the highlighted state. Defaults to the progress accent.
  final Color? accent;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final radius = BorderRadius.circular(WinterRadii.card);
    final glow = accent ?? colors.accentSecondary;
    return AnimatedContainer(
      duration: context.motion.standard,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (highlighted)
            BoxShadow(
              color: glow.withValues(alpha: 0.16),
              blurRadius: 18,
              spreadRadius: -4,
            ),
        ],
      ),
      child: Material(
        color: colors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted
                ? glow.withValues(alpha: 0.75)
                : colors.glassBorder,
            width: highlighted ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
