import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';
import '../../domain/progress/progress_repository.dart';
import '../../domain/xp/level_rules.dart';
import '../../shared/feedback/haptics.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../achievements/widgets/trophy_button.dart';
import '../celebration/celebration_queue.dart';
import 'today_controller.dart';
import 'widgets/habit_progress_tile.dart';
import 'widgets/minimum_day.dart';
import 'widgets/time_before_tile.dart';
import 'widgets/today_hero.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late final AppLifecycleListener _lifecycle;

  TodayController get _controller => ref.read(todayControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Re-read on resume so a day rollover (or the end of the arc) while
    // backgrounded is picked up.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _perform(
    Habit habit,
    HabitAction action, {
    NightTime? time,
  }) async {
    final result = await _controller.perform(habit.id, action, time: time);
    if (!mounted) return;

    // Feedback runs only after the result is persisted, and is derived from
    // what was written (the ledger change) and the re-read state.
    switch (result) {
      case ActionSuccess(:final value):
        final ledger = value.settlement.ledger;
        _celebrate(value);
        if (ledger.habitAwardFor(habit.id) case final award?) {
          if (!ledger.perfectDayGranted) unawaited(Haptics.habitCompleted());
          _showSnack(
            '${habit.title} complete · +${award.amount} XP',
            undo: () => _undo(habit, value.value),
          );
        } else if (value.value.becameIncomplete) {
          _showSnack(
            ledger.perfectDayRevoked
                ? '${habit.title} marked not done · Perfect Day bonus removed'
                : '${habit.title} marked not done',
            undo: habit.type.isClockTime
                ? () => _undo(habit, value.value)
                : null,
          );
        } else if (habit.type.isClockTime && value.value.changed) {
          final after = value.value.after;
          _showSnack(
            after.currentValue == 0
                ? '${habit.title} time cleared'
                : after.completed
                ? '${habit.title} time updated'
                : '${habit.title} logged · after the goal',
            undo: () => _undo(habit, value.value),
          );
        }
      case ActionFailure(:final failure):
        _showSnack(userMessageFor(failure));
    }
  }

  /// Reverts [transition]: the step that completed a binary or numeric
  /// habit, or a clock-time habit's previous record (a time, or none).
  Future<void> _undo(Habit habit, ProgressTransition transition) {
    if (!habit.type.isClockTime) {
      return _perform(habit, HabitProgressRules.undoActionFor(habit));
    }
    final previous = NightTime.tryValue(transition.before.currentValue);
    return previous == null
        ? _perform(habit, HabitAction.clearTime)
        : _perform(habit, HabitAction.setTime, time: previous);
  }

  /// Queues the Perfect Day / level-up celebration of a commit. Its haptic
  /// plays when the card appears.
  void _celebrate(DayCommit<Object?> commit) {
    final level = LevelRules.levelUp(
      beforeXp: commit.xpBefore,
      afterXp: commit.xpAfter,
    );
    final perfect = commit.settlement.ledger.perfectDayGranted;
    final summary = ref.read(todayControllerProvider).value;
    ref
        .read(celebrationQueueProvider.notifier)
        .add(
          DayCelebration(
            perfectStreak: perfect
                ? summary?.perfectDays.streak.current ?? 1
                : null,
            level: level,
            levelXp: level == null ? null : LevelRules.xpAtStartOf(level),
          ),
        );
  }

  Future<void> _openMinimumDay(DaySummary summary) async {
    final confirmed = await MinimumDaySheet.show(context, summary.entries);
    if (!confirmed || !mounted) return;
    final result = await _controller.activateMinimumDay();
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value) when value.value:
        unawaited(Haptics.minimumDay());
        _celebrate(value);
        _showSnack('Minimum Day on. Keep moving.');
      case ActionSuccess():
        break; // already a Minimum Day; nothing changed
      case ActionFailure(:final failure):
        _showSnack(userMessageFor(failure));
    }
  }

  // Today re-reads after edits through the arcRefresh listener in build, so
  // an edit still being saved when the editor closes is not missed.
  Future<void> _editHabits() => context.push(AppRoutes.habits);

  void _showSnack(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          action: undo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: undo),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayControllerProvider);
    // Persisted changes made elsewhere (e.g. the habit editor).
    ref.listen(arcRefreshProvider, (_, _) => _controller.refresh());
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (today) {
            AsyncData(:final value) => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(todayControllerProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DaySummary summary) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;
    // At most a handful of habits, so build everything (no lazy list): tiles
    // keep their animation state while scrolled away.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        WinterSpacing.md,
        WinterSpacing.sm,
        WinterSpacing.md,
        WinterSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: WinterSpacing.xs),
              Expanded(
                child: Text(
                  'WINTER ARC',
                  style: text.labelLarge?.copyWith(
                    color: colors.accentSecondary,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reminders',
                onPressed: () => context.push(AppRoutes.reminders),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const TrophyButton(),
            ],
          ),
          const SizedBox(height: WinterSpacing.xs),
          TodayHero(summary: summary),
          AnimatedSize(
            duration: context.motion.standard,
            child: summary.mode.isMinimum
                ? const Padding(
                    padding: EdgeInsets.only(top: WinterSpacing.md),
                    child: MinimumDayBanner(),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: WinterSpacing.lg),
          Row(
            children: [
              Expanded(child: Text("Today's habits", style: text.titleMedium)),
              Text(
                '${completion.completed} of ${completion.total} done',
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: WinterSpacing.sm),
          for (final entry in summary.entries) ...[
            if (entry.habit.type.isClockTime)
              TimeBeforeHabitTile(
                key: ValueKey(entry.habit.id),
                entry: entry,
                enabled: summary.isTrackable,
                streak: summary.streakFor(entry.habit.id).current,
                onSetTime: (time) =>
                    _perform(entry.habit, HabitAction.setTime, time: time),
                onClear: () => _perform(entry.habit, HabitAction.clearTime),
              )
            else
              HabitProgressTile(
                key: ValueKey(entry.habit.id),
                entry: entry,
                enabled: summary.isTrackable,
                minimum: summary.mode.isMinimum,
                streak: summary.streakFor(entry.habit.id).current,
                onAction: (action) => _perform(entry.habit, action),
              ),
            const SizedBox(height: WinterSpacing.sm),
          ],
          if (summary.canSwitchToMinimum) ...[
            const SizedBox(height: WinterSpacing.sm),
            RoughDayCard(onTap: () => _openMinimumDay(summary)),
          ],
          const SizedBox(height: WinterSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: summary.isTrackable ? _editHabits : null,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Edit habits'),
            ),
          ),
        ],
      ),
    );
  }
}
