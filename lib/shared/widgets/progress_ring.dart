import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Circular completion indicator with a centred percentage label.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.ratio,
    required this.label,
    this.size = 84,
  });

  /// `0.0..1.0`.
  final double ratio;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: ratio,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            color: ratio >= 1 ? colors.success : colors.accentSecondary,
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
