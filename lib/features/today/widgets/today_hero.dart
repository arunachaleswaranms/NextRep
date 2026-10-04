import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/progress/day_summary.dart';
import '../../../domain/winter_arc/winter_arc_session.dart';
import '../../../shared/formatting/arc_labels.dart';
import '../../../shared/widgets/level_bar.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/winter_scene/scene_progress.dart';
import '../../../shared/winter_scene/winter_scene.dart';

/// The Winter Arc command center at the top of Today: the living winter
/// world at today's stage, the day, today's completion, level and XP.
///
/// Everything shown comes from the persisted [DaySummary]; the scene only
/// visualises it (warmer on a Perfect Day, a recovery tint on a Minimum
/// Day) and is excluded from semantics.
class TodayHero extends StatelessWidget {
  const TodayHero({super.key, required this.summary});

  final DaySummary summary;

  static SceneProgress sceneFor(DaySummary summary) => SceneProgress(
    dayNumber: switch (summary.position) {
      ArcInProgress(:final dayNumber) => dayNumber,
      ArcNotStarted() => 1,
      ArcFinished(:final totalDays) => totalDays,
    },
    totalDays: summary.position.totalDays,
    dayCompletion: summary.completion.ratio,
    perfect: summary.isPerfect,
    minimum: summary.mode.isMinimum,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;
    final minimum = summary.mode.isMinimum;
    final scene = sceneFor(summary);
    final perfect = summary.perfectDays;
    final ringColor = summary.isPerfect
        ? colors.celebration
        : minimum
        ? colors.recovery
        : colors.accentSecondary;
    final glow = summary.isPerfect
        ? colors.celebration
        : minimum
        ? colors.recovery
        : null;
    final next = summary.position is ArcInProgress
        ? nextMilestoneLabel(scene.dayNumber)
        : null;

    return AnimatedContainer(
      duration: context.motion.celebration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(WinterRadii.card + 4),
        border: Border.all(
          color: glow?.withValues(alpha: 0.7) ?? colors.glassBorder,
          width: glow == null ? 1 : 1.4,
        ),
        boxShadow: [
          if (glow != null)
            BoxShadow(
              color: glow.withValues(alpha: 0.2),
              blurRadius: 28,
              spreadRadius: -6,
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Positioned.fill(child: WinterScene(scene: scene)),
              // Keeps the text readable over the illustration.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.skyTop.withValues(alpha: 0.15),
                          colors.skyTop.withValues(alpha: 0),
                          colors.background.withValues(alpha: 0.82),
                        ],
                        stops: const [0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(WinterSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: WinterSpacing.sm,
                      runSpacing: WinterSpacing.xs,
                      children: [
                        _Chip(
                          label: milestoneTitle(scene.milestone),
                          icon: Icons.terrain_rounded,
                          color: colors.snow,
                        ),
                        AnimatedSwitcher(
                          duration: context.motion.standard,
                          child: minimum
                              ? _Chip(
                                  key: const ValueKey('minimum'),
                                  label: 'MINIMUM DAY',
                                  icon: Icons.local_fire_department_rounded,
                                  color: colors.recovery,
                                )
                              : summary.isPerfect
                              ? _Chip(
                                  key: const ValueKey('perfect'),
                                  label: 'PERFECT DAY',
                                  icon: Icons.star_rounded,
                                  color: colors.celebration,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 92),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dayTitle(summary.position),
                                style: text.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('EEEE, d MMMM')
                                    .format(summary.date.toLocalDateTime()),
                                style: text.bodyMedium?.copyWith(
                                  color: colors.textPrimary.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                              // A season joined late keeps its own day
                              // numbers; say so rather than look like Day 1.
                              if (summary.session.isSeasonal)
                                Text(
                                  summary.session.joinedLate
                                      ? 'Seasonal Winter Arc · joined Day '
                                            '${summary.session.joinDayNumber}'
                                      : 'Seasonal Winter Arc',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textPrimary.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: WinterSpacing.sm),
                        Semantics(
                          label:
                              'Daily completion ${completion.percent} percent',
                          excludeSemantics: true,
                          child: ProgressRing(
                            ratio: completion.ratio,
                            label: '${completion.percent}%',
                            color: ringColor,
                            size: 76,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WinterSpacing.md,
              WinterSpacing.sm,
              WinterSpacing.md,
              WinterSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _XpPill(xp: summary.totalXp),
                    const SizedBox(width: WinterSpacing.md),
                    Expanded(child: LevelBar(level: summary.level)),
                  ],
                ),
                if (perfect.total > 0 || next != null) ...[
                  const SizedBox(height: WinterSpacing.sm),
                  Wrap(
                    spacing: WinterSpacing.md,
                    runSpacing: WinterSpacing.xs,
                    children: [
                      if (perfect.total > 0)
                        Text(
                          '🔥 Perfect streak ${perfect.streak.current} · '
                          'best ${perfect.streak.best} · ${perfect.total} total',
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      if (next != null)
                        Text(
                          'Next: $next',
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: WinterSpacing.sm,
      vertical: 3,
    ),
    decoration: BoxDecoration(
      color: context.winter.skyTop.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(WinterRadii.pill),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    ),
  );
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
        color: colors.warmLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(WinterRadii.pill),
        border: Border.all(color: colors.warmLight.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: colors.warmLight),
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
