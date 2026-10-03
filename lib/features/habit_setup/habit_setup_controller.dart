import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

final habitSetupControllerProvider =
    AsyncNotifierProvider.autoDispose<HabitSetupController, List<Habit>>(
      HabitSetupController.new,
    );

/// Habit selection for a session in setup. Every toggle is persisted
/// immediately, so leaving the app mid-setup keeps the selection.
class HabitSetupController extends AsyncNotifier<List<Habit>> {
  @override
  Future<List<Habit>> build() =>
      ref.watch(winterArcServiceProvider).setupHabits();

  Future<ActionResult<void>> setEnabled(
    String habitId, {
    required bool enabled,
  }) async {
    final service = ref.read(winterArcServiceProvider);
    final result = await runAction(
      'habit_setup',
      () => service.setHabitEnabled(habitId, enabled: enabled),
    );
    // Re-read so the UI always mirrors what was persisted, success or not.
    final reloaded = await AsyncValue.guard(service.setupHabits);
    if (ref.mounted) state = reloaded;
    return result;
  }

  Future<ActionResult<WinterArcSession>> start() => runAction(
    'habit_setup',
    () => ref.read(winterArcServiceProvider).startWinterArc(),
  );
}
