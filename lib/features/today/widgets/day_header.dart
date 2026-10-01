import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/progress/day_summary.dart';
import '../../../domain/winter_arc/winter_arc_session.dart';
import '../../../shared/widgets/progress_ring.dart';

class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.summary});

  final DaySummary summary;

  static String dayTitle(ArcDayPosition position) => switch (position) {
    ArcInProgress(:final dayNumber, :final totalDays) =>
      'Day $dayNumber of $totalDays',
    ArcNotStarted(:final daysUntilStart) =>
      daysUntilStart == 1
          ? 'Starts tomorrow'
          : 'Starts in $daysUntilStart days',
    ArcFinished() => 'Winter Arc complete',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WINTER ARC',
                style: text.labelLarge?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: WinterSpacing.xs),
              Text(dayTitle(summary.position), style: text.headlineMedium),
              const SizedBox(height: WinterSpacing.xs),
              Text(
                DateFormat('EEEE, d MMMM')
                    .format(summary.date.toLocalDateTime()),
                style: text.bodyMedium,
              ),
              const SizedBox(height: WinterSpacing.sm),
              _XpPill(xp: summary.totalXp),
            ],
          ),
        ),
        Semantics(
          label: 'Daily completion ${completion.percent} percent',
          excludeSemantics: true,
          child: ProgressRing(
            ratio: completion.ratio,
            label: '${completion.percent}%',
          ),
        ),
      ],
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
          Text(
            '$xp XP',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
