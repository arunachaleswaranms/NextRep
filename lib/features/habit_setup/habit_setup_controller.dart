import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../domain/habit/habit.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
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

  Future<ActionResult<WinterArcSession>> start() async {
    final status = ref.read(arcResolutionProvider.notifier);
    final result = await runAction(
      'habit_setup',
      () => ref.read(winterArcServiceProvider).startWinterArc(),
    );
    // Publish the started arc so the router leaves setup for Today.
    if (result is ActionSuccess) await _republish(status);
    return result;
  }

  static Future<void> _republish(ArcResolutionController status) async {
    try {
      await status.reconcile();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'habit_setup',
      );
    }
  }
}
