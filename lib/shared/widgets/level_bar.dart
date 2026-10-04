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
          Row(
            children: [
              Flexible(
                child: Text(
                  'Level ${level.level}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: colors.celebration),
                ),
              ),
              const SizedBox(width: WinterSpacing.sm),
              const Spacer(),
              Flexible(
                flex: 2,
                child: Text(
                  '${level.xpIntoLevel} / ${level.xpForLevel} XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: WinterSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(WinterRadii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: level.ratio),
              duration: context.motion.emphasis,
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
