import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../../domain/habit/habit.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';
import '../../domain/progress/progress_repository.dart';
import '../../domain/winter_arc/arc_pause.dart';
import '../../domain/winter_arc/arc_restart.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../domain/xp/level_rules.dart';
import '../../shared/feedback/haptics.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../achievements/widgets/trophy_button.dart';
import '../arc_pause/pause_actions.dart';
import '../arc_pause/pause_labels.dart';
import '../arc_pause/pause_sheet.dart';
import '../arc_pause/paused_arc_card.dart';
import '../arc_pause/resume_sheet.dart';
import '../arc_restart/restart_labels.dart';
import '../celebration/celebration_queue.dart';
import '../focus_guard/focus_guard_card.dart';
import '../share/share_choice_sheet.dart';
import '../share/share_preview_screen.dart';
import '../sound/sound_origin_scope.dart';
import '../sound/sound_settings_screen.dart';
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

class _TodayScreenState extends ConsumerState<TodayScreen>
    with SoundOriginScope {
  late final AppLifecycleListener _lifecycle;
  bool _returningToFull = false;
  bool _cancellingPause = false;

  TodayController get _controller => ref.read(todayControllerProvider.notifier);

  @override
  String get soundLocation => AppRoutes.today;

  @override
  void initState() {
    super.initState();
    // Re-read on resume so a day rollover (or the end of the arc) while
    // backgrounded is picked up.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
    // Loads the completion sounds (if on) so the first one plays at once.
    unawaited(ref.read(completionFeedbackProvider).warmUp());
    // A completion's sound belongs to the Arc it was made in: a Restart, or
    // the Arc ending, drops any that hasn't started.
    ref.listenManual(
      todayControllerProvider.select(
        (today) => (today.value?.session.id, today.value?.session.status),
      ),
      (_, _) => renewSoundOrigin(),
    );
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
    final feedback = ref.read(completionFeedbackProvider);
    final requestedAt = feedback.now();
    final sessionId = ref.read(todayControllerProvider).value?.session.id;
    // Today as the user sees it now: if they leave, or the Arc or app
    // changes, before the sound starts, it never plays (G-R1).
    final origin = soundOrigin;
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
          // The completion sound (spec § 8.1): only for a saved transition
          // to complete, never awaited, and independent of the haptic.
          if (value.value.becameCompleted && sessionId != null) {
            unawaited(
              feedback.habitCompleted(
                sessionId: sessionId,
                date: value.settlement.date,
                habitId: habit.id,
                perfectDay: ledger.perfectDayGranted,
                requestedAt: requestedAt,
                origin: origin,
              ),
            );
          }
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
        // Undo is pinned to the day it was offered for: after a rollover
        // the domain rejects it as stale, it never changes another day.
        final date = value.settlement.date;
        _showSnack(
          'Minimum Day activated',
          undo: () => _returnOnce(() => _returnToFullTargets(date: date)),
        );
      case ActionSuccess():
        break; // already a Minimum Day; nothing changed
      case ActionFailure(:final failure):
        _showSnack(userMessageFor(failure));
    }
  }

  Future<void> _confirmReturnToFullTargets() => _returnOnce(() async {
    final confirmed = await ReturnToFullTargetsDialog.show(context);
    if (confirmed && mounted) await _returnToFullTargets();
  });

  /// Runs [body] unless a return to full targets is already being confirmed
  /// or saved, so repeated taps can't stack dialogs or requests (the domain
  /// is idempotent as well).
  Future<void> _returnOnce(Future<void> Function() body) async {
    if (_returningToFull) return;
    _returningToFull = true;
    try {
      await body();
    } finally {
      _returningToFull = false;
    }
  }

  /// Returns today to full targets through the domain. Progress is kept;
  /// completion and XP follow from what is persisted.
  Future<void> _returnToFullTargets({LocalDate? date}) async {
    final result = await _controller.returnToFullTargets(date: date);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value) when value.value:
        _celebrate(value);
        _showSnack('Back to full targets');
      case ActionSuccess():
        break; // already on full targets; nothing changed
      case ActionFailure(:final failure):
        _showSnack(userMessageFor(failure));
    }
  }

  /// Asks which card to share, then previews it from the summary on
  /// screen. Nothing is shared until the user taps Share in the preview.
  Future<void> _share(DaySummary summary) async {
    final choice = await ShareChoiceSheet.show(context);
    if (choice == null || !mounted) return;
    await switch (choice) {
      ShareChoice.todayProgress => SharePreviewScreen.today(context, summary),
      ShareChoice.myArc => SharePreviewScreen.arc(context, summary),
    };
  }

  /// "Pause Arc": the sheet does the rest. Today re-reads through the
  /// arcRefresh listener once the pause is stored.
  Future<void> _openPause(DaySummary summary) async {
    final result = await PauseArcSheet.show(context, summary.session.id);
    if (!mounted) return;
    if (result == PauseSheetResult.openFocusGuard) {
      await context.push(AppRoutes.focusGuard);
    }
  }

  /// "Cancel pause", until midnight. The service re-checks the stored pause
  /// and today's date; after midnight the pause has begun and Today shows
  /// it instead.
  Future<void> _cancelPause(DaySummary summary) async {
    if (_cancellingPause) return;
    setState(() => _cancellingPause = true);
    final result = await runPauseAction(
      ref,
      'cancel_pause',
      (service) => service.cancelPause(sessionId: summary.session.id),
    );
    if (!mounted) return;
    setState(() => _cancellingPause = false);
    switch (result) {
      case ActionSuccess():
        _showSnack(PauseCopy.cancelled);
      case ActionFailure(failure: DomainFailure() && final failure):
        _showSnack(userMessageFor(failure));
        await _controller.refresh();
      case ActionFailure():
        _showSnack(PauseCopy.cancelFailed);
    }
  }

  /// "Resume Arc": Today shows the resumed day once the sheet has stored
  /// it (never before).
  Future<void> _openResume(DaySummary summary) =>
      ResumeArcSheet.show(context, summary.session.id);

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
    if (summary.position case final ArcPaused paused
        when summary.session.status == WinterArcStatus.active) {
      return _pausedContent(context, summary, paused);
    }
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;
    final pauseOffered =
        ArcPauseRules.blockerOn(summary.session, summary.date) == null;
    final scheduled = summary.session.scheduledPauseOn(summary.date);
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
          _TodayHeader(
            actions: [
              IconButton(
                tooltip: 'Share progress',
                onPressed: () => _share(summary),
                icon: const Icon(Icons.ios_share_rounded),
              ),
              IconButton(
                tooltip: 'Reminders',
                onPressed: () => context.push(AppRoutes.reminders),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const SoundSettingsButton(),
              const TrophyButton(),
              if (pauseOffered)
                PopupMenuButton<void>(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert_rounded),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      onTap: () => _openPause(summary),
                      child: const ListTile(
                        leading: Icon(Icons.ac_unit_rounded),
                        title: Text(PauseCopy.menuItem),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: WinterSpacing.xs),
          TodayHero(summary: summary),
          if (scheduled != null)
            Padding(
              padding: const EdgeInsets.only(top: WinterSpacing.md),
              child: PauseScheduledBanner(
                frozenFrom: scheduled.frozenFrom,
                today: summary.date,
                busy: _cancellingPause,
                cancelOffered: ArcPauseRules.cancelOfferedOn(
                  summary.session,
                  summary.date,
                ),
                onCancel: () => _cancelPause(summary),
              ),
            ),
          AnimatedSize(
            duration: context.motion.standard,
            child: summary.mode.isMinimum
                ? Padding(
                    padding: const EdgeInsets.only(top: WinterSpacing.md),
                    child: MinimumDayBanner(
                      onReturnToFullTargets: summary.canReturnToFullTargets
                          ? _confirmReturnToFullTargets
                          : null,
                    ),
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
          // Focus Guard is app-level and visual only: it never affects the
          // day's habits, XP or streaks. Omitted where unsupported.
          const Padding(
            padding: EdgeInsets.only(top: WinterSpacing.sm),
            child: FocusGuardCard(),
          ),
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

  /// Today on a paused date (spec § 9.7): the paused card and Focus Guard,
  /// which isn't part of the Arc. Nothing here writes.
  Widget _pausedContent(
    BuildContext context,
    DaySummary summary,
    ArcPaused paused,
  ) {
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
          _TodayHeader(
            actions: [
              IconButton(
                tooltip: 'Reminders',
                onPressed: () => context.push(AppRoutes.reminders),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const SoundSettingsButton(),
              const TrophyButton(),
            ],
          ),
          const SizedBox(height: WinterSpacing.sm),
          PausedArcCard(
            position: paused,
            today: summary.date,
            onResume: () => _openResume(summary),
            // Restart from the paused screen (spec § 9.7); the Restart
            // screen re-checks everything, including the clock guard.
            onRestart:
                ArcRestartRules.blockerOn(summary.session, summary.date) == null
                ? () => context.push(AppRoutes.restartArc(summary.session.id))
                : null,
            restartLabel: RestartCopy.entry(summary.session),
          ),
          const Padding(
            padding: EdgeInsets.only(top: WinterSpacing.md),
            child: FocusGuardCard(),
          ),
        ],
      ),
    );
  }
}

/// Today's header: the "WINTER ARC" eyebrow and its actions. On one line
/// when they fit; otherwise the actions move under the eyebrow (wrapping
/// rather than overflowing), so the eyebrow never breaks inside a word on a
/// narrow phone or with large text.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: WinterSpacing.xs),
          child: Text(
            'WINTER ARC',
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 3,
            ),
          ),
        ),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ],
    );
  }
}
