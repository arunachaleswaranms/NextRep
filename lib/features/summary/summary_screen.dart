import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_status.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/winter_scene/scene_progress.dart';
import '../../shared/winter_scene/winter_scene.dart';
import 'arc_removal.dart';
import 'summary_controller.dart';

/// End-of-Arc summary of arc [sessionId]: the summit, warm and fully
/// revealed, with the arc's results derived from its stored history. The
/// home of a completed arc, and the overview of any arc in Arc History.
/// Read-only.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});

  final int sessionId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SummaryView view,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteArcDialog(view: view),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(arcRemovalProvider)
        .deleteCompletedArc(view.session.id);
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess(:final value):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Winter Arc deleted.')));
        context.go(value);
      case ActionFailure(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(summaryControllerProvider(sessionId));
    final resolution = ref.watch(arcResolutionProvider);
    // Another arc can only start from the latest completed arc, and only
    // while nothing is in setup or running.
    final isHome =
        resolution != null &&
        resolution.current == null &&
        resolution.latestCompleted?.id == sessionId;
    return Scaffold(
      body: WinterBackground(
        child: switch (view) {
          AsyncData(:final value) => _content(
            context,
            value,
            isHome: isHome,
            onDelete: value.session.status == WinterArcStatus.completed
                ? () => _delete(context, ref, value)
                : null,
          ),
          AsyncError(:final error, :final stackTrace) => SafeArea(
            child: FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () =>
                  ref.invalidate(summaryControllerProvider(sessionId)),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _content(
    BuildContext context,
    SummaryView view, {
    required bool isHome,
    required VoidCallback? onDelete,
  }) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final summary = view.summary;
    final dates = arcDateRange(view.session);
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
                // Opened from Arc History rather than as the home.
                if (ModalRoute.of(context)?.canPop ?? false)
                  const Positioned(
                    left: WinterSpacing.xs,
                    top: 0,
                    child: SafeArea(child: BackButton()),
                  ),
                if (onDelete != null)
                  Positioned(
                    right: WinterSpacing.xs,
                    top: 0,
                    child: SafeArea(
                      child: PopupMenuButton<void>(
                        tooltip: 'Arc options',
                        icon: const Icon(Icons.more_vert_rounded),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            onTap: onDelete,
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_forever_rounded,
                                color: colors.danger,
                              ),
                              title: const Text('Delete Arc'),
                            ),
                          ),
                        ],
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
                  if (isHome) ...[
                    FilledButton.icon(
                      onPressed: () => context.push(AppRoutes.newArc),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Start New Arc'),
                    ),
                    const SizedBox(height: WinterSpacing.sm),
                  ],
                  _SecondaryAction(
                    icon: Icons.terrain_rounded,
                    label: 'View Journey',
                    filled: !isHome,
                    onPressed: () =>
                        context.push(AppRoutes.arcJourney(view.session.id)),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  _SecondaryAction(
                    icon: Icons.edit_note_rounded,
                    label: 'View Journal',
                    onPressed: () =>
                        context.push(AppRoutes.arcJournal(view.session.id)),
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  _SecondaryAction(
                    icon: Icons.emoji_events_rounded,
                    label: 'Achievements',
                    onPressed: () => context.push(
                      AppRoutes.arcAchievements(view.session.id),
                    ),
                  ),
                  if (isHome) ...[
                    const SizedBox(height: WinterSpacing.xs),
                    TextButton.icon(
                      onPressed: () => context.push(AppRoutes.arcs),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Arc History'),
                    ),
                  ],
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

/// "Delete this Winter Arc?": what will be lost, in numbers, and a
/// destructive confirm button. Cancel is the safe default.
class _DeleteArcDialog extends StatelessWidget {
  const _DeleteArcDialog({required this.view});

  final SummaryView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final summary = view.summary;
    final perfect = summary.perfectDays == 1
        ? '1 Perfect Day'
        : '${summary.perfectDays} Perfect Days';
    return AlertDialog(
      icon: Icon(Icons.delete_forever_rounded, color: colors.danger),
      title: const Text('Delete this Winter Arc?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(arcDateRange(view.session), style: text.titleMedium),
            Text('${summary.totalXp} XP', style: text.bodyLarge),
            Text(perfect, style: text.bodyLarge),
            const SizedBox(height: WinterSpacing.md),
            const Text(
              'This permanently removes its habits, progress, XP, Journey, '
              'achievements and reflections.',
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              'This cannot be undone unless you have a backup.',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: colors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Delete Arc'),
        ),
      ],
    );
  }
}

/// A full-width summary action: filled for the primary one, outlined
/// otherwise.
class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => filled
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          icon: Icon(icon),
          label: Text(label),
        );
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
