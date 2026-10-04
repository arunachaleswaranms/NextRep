import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/winter_scene/scene_progress.dart';
import '../../shared/winter_scene/winter_scene.dart';
import 'summary_controller.dart';

/// End-of-Arc summary: the summit, warm and fully revealed, with the arc's
/// results derived from stored history. The home of a completed arc.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(summaryControllerProvider);
    return Scaffold(
      body: WinterBackground(
        child: switch (view) {
          AsyncData(:final value) => _content(context, value),
          AsyncError(:final error, :final stackTrace) => SafeArea(
            child: FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(summaryControllerProvider),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _content(BuildContext context, SummaryView view) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final summary = view.summary;
    final dates =
        '${DateFormat('d MMM').format(view.session.startDate.toLocalDateTime())}'
        ' – '
        '${DateFormat('d MMM y').format(view.session.endDate.toLocalDateTime())}';
    final strongest = summary.strongestHabit;
    final stats = [
      _StatData('Total XP', '${summary.totalXp}', Icons.bolt_rounded),
      _StatData(
        'Final level',
        'Level ${summary.level.level}',
        Icons.trending_up_rounded,
      ),
      _StatData('Perfect Days', '${summary.perfectDays}', Icons.star_rounded),
      _StatData(
        'Best Perfect streak',
        '${summary.bestPerfectStreak} ${summary.bestPerfectStreak == 1 ? 'day' : 'days'}',
        Icons.local_fire_department_rounded,
      ),
      _StatData(
        'Habits completed',
        '${summary.habitsCompleted}',
        Icons.check_circle_rounded,
      ),
      _StatData(
        'Minimum Days completed',
        '${summary.minimumDaysCompleted}',
        Icons.spa_rounded,
      ),
      _StatData(
        'Achievements',
        '${summary.achievementsUnlocked} / ${summary.achievementsTotal}',
        Icons.emoji_events_rounded,
      ),
      _StatData(
        'Consistency',
        '${summary.consistencyPercent}%',
        Icons.insights_rounded,
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 340,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Summit reveal: the walked trail draws itself to the top.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: context.motion.celebration * 3,
                  curve: Curves.easeInOutCubic,
                  builder: (context, reveal, _) => WinterScene(
                    scene: SceneProgress.summit(),
                    trailReveal: reveal,
                    maxSnow: 36,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.background.withValues(alpha: 0),
                        colors.background.withValues(alpha: 0.95),
                      ],
                      stops: const [0.4, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: WinterSpacing.lg,
                  right: WinterSpacing.lg,
                  bottom: WinterSpacing.md,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WINTER ARC COMPLETE',
                          style: text.labelLarge?.copyWith(
                            color: colors.warmLight,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: WinterSpacing.xs),
                        Text(
                          '${summary.totalDays} days',
                          style: text.displaySmall,
                        ),
                        Text(dates, style: text.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            WinterSpacing.sm,
            WinterSpacing.md,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (strongest != null) ...[
                  _Panel(
                    accent: colors.celebration,
                    child: Row(
                      children: [
                        HabitIcon(iconKey: strongest.habit.iconKey),
                        const SizedBox(width: WinterSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STRONGEST HABIT',
                                style: text.labelSmall?.copyWith(
                                  color: colors.celebration,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                strongest.habit.title,
                                style: text.titleMedium,
                              ),
                              Text(
                                'Best streak ${strongest.bestStreak} days · '
                                'done on ${strongest.completedDays} days',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                ],
                for (var i = 0; i < stats.length; i += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _Stat(stats[i])),
                        const SizedBox(width: WinterSpacing.sm),
                        Expanded(child: _Stat(stats[i + 1])),
                      ],
                    ),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.sm,
            WinterSpacing.lg,
            WinterSpacing.xl,
          ),
          sliver: SliverToBoxAdapter(
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.summaryJourney),
                    icon: const Icon(Icons.terrain_rounded),
                    label: const Text('View Journey'),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.achievements),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.emoji_events_rounded),
                    label: const Text('Achievements'),
                  ),
                  const SizedBox(height: WinterSpacing.md),
                  Text(
                    'Your Winter Arc is complete and kept as it was. '
                    'Its history is read-only.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _StatData {
  const _StatData(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _Stat extends StatelessWidget {
  const _Stat(this.data);

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '${data.label}: ${data.value}',
      excludeSemantics: true,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, size: 18, color: colors.accentSecondary),
            const SizedBox(height: WinterSpacing.xs),
            Text(data.value, style: text.titleLarge),
            Text(data.label, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Container(
      padding: const EdgeInsets.all(WinterSpacing.md),
      decoration: BoxDecoration(
        color: colors.glass,
        borderRadius: BorderRadius.circular(WinterRadii.card),
        border: Border.all(
          color: accent?.withValues(alpha: 0.6) ?? colors.glassBorder,
        ),
      ),
      child: child,
    );
  }
}
