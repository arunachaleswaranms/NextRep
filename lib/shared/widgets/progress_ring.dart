import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Circular completion indicator with a centred percentage label.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.ratio,
    required this.label,
    this.size = 84,
    this.color,
  });

  /// `0.0..1.0`.
  final double ratio;
  final String label;
  final double size;

  /// Arc colour. Defaults to the progress accent, and success once full.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: ratio),
            duration: context.motion.standard,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              color:
                  color ??
                  (ratio >= 1 ? colors.success : colors.accentSecondary),
            ),
          ),
          Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
