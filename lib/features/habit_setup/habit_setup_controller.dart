import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../domain/habit/habit.dart';
import '../../domain/habit/setup_habit_rules.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

final habitSetupControllerProvider =
    AsyncNotifierProvider.autoDispose<HabitSetupController, ArcSetup>(
      HabitSetupController.new,
    );

/// The arc in setup and its habits. Every change is persisted immediately
/// (so leaving the app mid-setup keeps it) and then re-read, so the screen
/// always shows what was stored, success or not.
class HabitSetupController extends AsyncNotifier<ArcSetup> {
  @override
  Future<ArcSetup> build() => ref.watch(winterArcServiceProvider).setup();

  Future<ActionResult<void>> setEnabled(
    String habitId, {
    required bool enabled,
  }) =>
      _change((service) => service.setHabitEnabled(habitId, enabled: enabled));

  Future<ActionResult<Habit>> addTemplate(String templateId) =>
      _change((service) => service.addTemplateHabit(templateId));

  Future<ActionResult<Habit>> addCustom(HabitDraft draft) =>
      _change((service) => service.addCustomHabit(draft));

  Future<ActionResult<Habit>> edit(String habitId, HabitDraft draft) =>
      _change((service) => service.editSetupHabit(habitId, draft));

  Future<ActionResult<void>> delete(String habitId) =>
      _change((service) => service.deleteSetupHabit(habitId));

  Future<ActionResult<T>> _change<T>(
    Future<T> Function(WinterArcService service) body,
  ) async {
    final service = ref.read(winterArcServiceProvider);
    final result = await runAction('habit_setup', () => body(service));
    final reloaded = await AsyncValue.guard(service.setup);
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
