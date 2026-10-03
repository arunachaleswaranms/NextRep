import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/habit/habit_edit.dart';
import '../../domain/progress/habit_tracking_service.dart';

final habitsControllerProvider =
    AsyncNotifierProvider.autoDispose<HabitsController, HabitSettings>(
      HabitsController.new,
    );

/// Habit configuration after the arc has started. Edits apply from today and
/// are re-read from storage after each save.
class HabitsController extends AsyncNotifier<HabitSettings> {
  final _queue = SerialQueue();

  @override
  Future<HabitSettings> build() =>
      ref.watch(habitTrackingServiceProvider).habitSettings();

  Future<ActionResult<void>> edit(String habitId, HabitEdit edit) {
    final shownDate = state.value?.date;
    // Read dependencies up front: the screen may be closed (and this
    // controller disposed) while the commit is still running.
    final service = ref.read(habitTrackingServiceProvider);
    final arcRefresh = ref.read(arcRefreshProvider.notifier);
    return _queue.run(() async {
      final ActionResult<void> result = shownDate == null
          ? const ActionFailure<void>(
              DomainFailure(DomainRule.noActiveSession, 'Habits not loaded'),
            )
          : await runAction(
              'habits',
              () => service.editHabit(
                habitId: habitId,
                edit: edit,
                date: shownDate,
              ),
            );
      // Other screens re-read persisted changes even if this one is gone.
      if (result is ActionSuccess) arcRefresh.changed();

      final next = await AsyncValue.guard(service.habitSettings);
      if (next case AsyncError(:final error, :final stackTrace)) {
        ErrorReporter.report(
          toAppFailure(error, stackTrace),
          context: 'habits',
        );
      }
      if (ref.mounted) state = next;
      return result;
    });
  }
}
