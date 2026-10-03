import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';

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
  Future<ActionResult<ProgressTransition>> perform(
    String habitId,
    HabitAction action,
  ) {
    final shownDate = state.value?.date;
    return _queue.run(() async {
      final result = shownDate == null
          ? const ActionFailure<ProgressTransition>(
              DomainFailure(DomainRule.noActiveSession, 'Today not loaded'),
            )
          : await runAction(
              'today',
              () => ref
                  .read(habitTrackingServiceProvider)
                  .perform(habitId: habitId, action: action, date: shownDate),
            );
      await _reload();
      return result;
    });
  }

  /// Re-reads today's state, e.g. when the app resumes on a new day.
  Future<void> refresh() => _queue.run(_reload);

  Future<void> _reload() async {
    final next = await AsyncValue.guard(
      ref.read(habitTrackingServiceProvider).today,
    );
    if (next case AsyncError(:final error, :final stackTrace)) {
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'today');
    }
    if (ref.mounted) state = next;
  }
}
