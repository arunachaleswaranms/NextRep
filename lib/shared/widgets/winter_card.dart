import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Rounded surface used for list rows and panels.
class WinterCard extends StatelessWidget {
  const WinterCard({
    super.key,
    required this.child,
    this.highlighted = false,
    this.onTap,
    this.padding = const EdgeInsets.all(WinterSpacing.md),
  });

  final Widget child;

  /// Draws the accent border, e.g. for a completed habit.
  final bool highlighted;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final radius = BorderRadius.circular(WinterRadii.card);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: highlighted ? colors.accentSecondary : colors.outline,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
