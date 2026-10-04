import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/habit/habit.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';
import '../../domain/progress/habit_tracking_service.dart';
import '../../domain/progress/progress_repository.dart';
import '../achievements/achievements_controller.dart';

final todayControllerProvider =
    AsyncNotifierProvider.autoDispose<TodayController, DaySummary>(
      TodayController.new,
    );

/// Today's habits. The state is always re-read from storage after an action,
/// so what the UI shows is what was persisted.
///
/// Loading and refreshing Today are app entry points: they first run the
/// arc close-out check (a completed arc is redirected to its summary) and
/// afterwards reconcile achievements, best effort.
class TodayController extends AsyncNotifier<DaySummary> {
  final _queue = SerialQueue();

  @override
  Future<DaySummary> build() async {
    final tracking = ref.watch(habitTrackingServiceProvider);
    final status = ref.read(arcResolutionProvider.notifier);
    final achievements = ref.read(achievementSyncProvider);
    await status.reconcile();
    final summary = await tracking.today();
    await achievements.run();
    return summary;
  }

  /// Applies [action] to [habitId] for the day currently on screen.
  ///
  /// Calls are queued, so rapid taps are processed one at a time.
  ///
  /// [time] goes with [HabitAction.setTime] on a clock-time habit.
  Future<ActionResult<DayCommit<ProgressTransition>>> perform(
    String habitId,
    HabitAction action, {
    NightTime? time,
  }) => _mutate(
    (service, date, sessionId) => service.perform(
      habitId: habitId,
      action: action,
      date: date,
      sessionId: sessionId,
      time: time,
    ),
  );

  /// Switches the day on screen to a Minimum Day (one-way).
  Future<ActionResult<DayCommit<bool>>> activateMinimumDay() => _mutate(
    (service, date, sessionId) =>
        service.activateMinimumDay(date: date, sessionId: sessionId),
  );

  /// Re-reads today's state, e.g. when the app resumes on a new day or a
  /// habit was edited elsewhere.
  Future<void> refresh() => _queue.run(() => _reload(entryPoint: true));

  /// Runs [body] for the day and arc on screen: a write meant for an arc
  /// that has since closed is rejected, never applied to another arc.
  Future<ActionResult<T>> _mutate<T>(
    Future<T> Function(
      HabitTrackingService service,
      LocalDate date,
      int sessionId,
    )
    body,
  ) {
    final shownDate = state.value?.date;
    final shownSession = state.value?.session.id;
    final service = ref.read(habitTrackingServiceProvider);
    final arcRefresh = ref.read(arcRefreshProvider.notifier);
    final achievements = ref.read(achievementSyncProvider);
    final result = _queue.run(() async {
      final result = shownDate == null || shownSession == null
          ? ActionFailure<T>(
              const DomainFailure(
                DomainRule.noActiveSession,
                'Today not loaded',
              ),
            )
          : await runAction(
              'today',
              () => body(service, shownDate, shownSession),
            );
      if (result is ActionSuccess<T>) arcRefresh.changed();
      await _reload(entryPoint: false, service: service);
      return result;
    });
    // Achievements derive from the committed day. They are reconciled in a
    // follow-up task, after the caller has queued the action's own
    // celebration, and never affect the action's result.
    _queue.run(() async {
      if (await result is ActionSuccess<T>) await achievements.run();
    });
    return result;
  }

  Future<void> _reload({
    required bool entryPoint,
    HabitTrackingService? service,
  }) async {
    if (!ref.mounted) return;
    final HabitTrackingService tracking =
        service ?? ref.read(habitTrackingServiceProvider);
    final status = ref.read(arcResolutionProvider.notifier);
    final achievements = ref.read(achievementSyncProvider);
    final next = await AsyncValue.guard(() async {
      if (entryPoint) await status.reconcile();
      return tracking.today();
    });
    if (next case AsyncError(:final error, :final stackTrace)) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'today');
    }
    if (ref.mounted) state = next;
    if (entryPoint) await achievements.run();
  }
}
