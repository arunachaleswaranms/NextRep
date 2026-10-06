import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';
import '../../domain/xp/level_rules.dart';

/// "Level N" with XP progress towards the next level. The bar animates
/// between persisted values; it never decides anything.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.level});

  final LevelProgress level;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label:
          'Level ${level.level}, ${level.xpIntoLevel} of '
          '${level.xpForLevel} XP to level ${level.level + 1}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Side by side when they fit; at large text the XP figure moves
          // under the level instead of both being cut short.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: WinterSpacing.sm,
            children: [
              Text(
                'Level ${level.level}',
                style: text.labelLarge?.copyWith(color: colors.celebration),
              ),
              Text(
                '${level.xpIntoLevel} / ${level.xpForLevel} XP',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: WinterSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(WinterRadii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: level.ratio),
              duration: context.motion.celebration,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                color: colors.celebration,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An integer that counts to its new value when it changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.builder});

  final int value;
  final Widget Function(BuildContext context, int value) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
    tween: IntTween(end: value),
    duration: context.motion.standard,
    curve: Curves.easeOut,
    builder: (context, shown, _) => builder(context, shown),
  );
}
