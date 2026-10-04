import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/progress/day_summary.dart';
import '../../../shared/formatting/arc_labels.dart';
import '../../../shared/widgets/level_bar.dart';
import '../../../shared/widgets/progress_ring.dart';

class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;
    final minimum = summary.mode.isMinimum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: WinterSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'WINTER ARC',
                        style: text.labelLarge?.copyWith(
                          color: colors.accentSecondary,
                          letterSpacing: 3,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: context.motion.standard,
                        child: minimum
                            ? const _Badge.minimum()
                            : summary.isPerfect
                            ? const _Badge.perfect()
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(dayTitle(summary.position), style: text.headlineMedium),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(
                    DateFormat('EEEE, d MMMM')
                        .format(summary.date.toLocalDateTime()),
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'Daily completion ${completion.percent} percent',
              excludeSemantics: true,
              child: ProgressRing(
                ratio: completion.ratio,
                label: '${completion.percent}%',
                color: minimum ? colors.recovery : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: WinterSpacing.md),
        Row(
          children: [
            _XpPill(xp: summary.totalXp),
            const SizedBox(width: WinterSpacing.md),
            Expanded(child: LevelBar(level: summary.level)),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge.minimum() : _minimum = true;
  const _Badge.perfect() : _minimum = false;

  final bool _minimum;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final color = _minimum ? colors.recovery : colors.celebration;
    return Container(
      key: ValueKey(_minimum),
      padding: const EdgeInsets.symmetric(
        horizontal: WinterSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(WinterRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        _minimum ? 'MINIMUM DAY' : 'PERFECT DAY',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _XpPill extends StatelessWidget {
  const _XpPill({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WinterSpacing.sm + 2,
        vertical: WinterSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(WinterRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: colors.warning),
          const SizedBox(width: WinterSpacing.xs),
          AnimatedCount(
            value: xp,
            builder: (context, shown) => Text(
              '$shown XP',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
