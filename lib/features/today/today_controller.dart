import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';
import '../../domain/progress/habit_tracking_service.dart';
import '../../domain/progress/progress_repository.dart';

final todayControllerProvider =
    AsyncNotifierProvider.autoDispose<TodayController, DaySummary>(
      TodayController.new,
    );

/// Today's habits. The state is always re-read from storage after an action,
/// so what the UI shows is what was persisted.
class TodayController extends AsyncNotifier<DaySummary> {
  final _queue = SerialQueue();

  @override
  Future<DaySummary> build() => ref.watch(habitTrackingServiceProvider).today();

  /// Applies [action] to [habitId] for the day currently on screen.
  ///
  /// Calls are queued, so rapid taps are processed one at a time.
  Future<ActionResult<DayCommit<ProgressTransition>>> perform(
    String habitId,
    HabitAction action,
  ) => _mutate(
    (service, date) =>
        service.perform(habitId: habitId, action: action, date: date),
  );

  /// Switches the day on screen to a Minimum Day (one-way).
  Future<ActionResult<DayCommit<bool>>> activateMinimumDay() =>
      _mutate((service, date) => service.activateMinimumDay(date: date));

  /// Re-reads today's state, e.g. when the app resumes on a new day or a
  /// habit was edited elsewhere.
  Future<void> refresh() => _queue.run(_reload);

  Future<ActionResult<T>> _mutate<T>(
    Future<T> Function(HabitTrackingService service, LocalDate date) body,
  ) {
    final shownDate = state.value?.date;
    final service = ref.read(habitTrackingServiceProvider);
    final arcRefresh = ref.read(arcRefreshProvider.notifier);
    return _queue.run(() async {
      final result = shownDate == null
          ? ActionFailure<T>(
              const DomainFailure(
                DomainRule.noActiveSession,
                'Today not loaded',
              ),
            )
          : await runAction('today', () => body(service, shownDate));
      if (result is ActionSuccess<T>) arcRefresh.changed();
      await _reload(service);
      return result;
    });
  }

  Future<void> _reload([HabitTrackingService? service]) async {
    if (!ref.mounted) return;
    final HabitTrackingService tracking =
        service ?? ref.read(habitTrackingServiceProvider);
    final next = await AsyncValue.guard(tracking.today);
    if (next case AsyncError(:final error, :final stackTrace)) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'today');
    }
    if (ref.mounted) state = next;
  }
}
