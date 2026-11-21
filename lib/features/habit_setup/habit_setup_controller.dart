import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/local_date.dart';
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
/// always shows what was stored, success or not. Habit Setup, the saved-
/// setup hub, Review Setup and Confirm & Start all show this one state.
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

  /// Moves habit [habitId] to position [newIndex] (0-based, in the list as
  /// it is now). The new order shows at once and the whole order is then
  /// written in one transaction and re-read: on failure the stored order
  /// comes back. Moving a habit to where it is writes nothing.
  ///
  /// The order is built from the setup on screen; if that is out of date
  /// (a habit added or removed meanwhile) the domain refuses it and the
  /// stored order is shown.
  Future<ActionResult<void>> move(String habitId, int newIndex) async {
    final current = state.value;
    final habits = [...?current?.habits];
    final from = habits.indexWhere((h) => h.id == habitId);
    if (current == null || from < 0) {
      await refresh();
      return const ActionFailure(
        DomainFailure(DomainRule.invalidHabitOrder, 'Unknown habit'),
      );
    }
    final to = newIndex.clamp(0, habits.length - 1);
    if (to == from) return const ActionSuccess(null);
    habits.insert(to, habits.removeAt(from));
    state = AsyncData(current.withHabits(habits));
    return _change(
      (service) => service.reorderSetupHabits([for (final h in habits) h.id]),
    );
  }

  /// Bumped by every re-read, so only the latest one is shown (an older
  /// read finishing late can't bring back an order changed since).
  int _reads = 0;

  Future<ActionResult<T>> _change<T>(
    Future<T> Function(WinterArcService service) body,
  ) async {
    final service = ref.read(winterArcServiceProvider);
    final result = await runAction('habit_setup', () => body(service));
    final read = ++_reads;
    final reloaded = await AsyncValue.guard(service.setup);
    if (ref.mounted && read == _reads) state = reloaded;
    return result;
  }

  /// Re-reads the setup, e.g. on resume: whether it can start depends on
  /// today's date (1 October opens a season, 1 January ends it).
  Future<void> refresh() async {
    final read = ++_reads;
    final reloaded = await AsyncValue.guard(
      ref.read(winterArcServiceProvider).setup,
    );
    if (ref.mounted && read == _reads && reloaded is AsyncData<ArcSetup>) {
      state = reloaded;
    }
  }

  /// Starts the arc in setup: only Confirm & Start calls this. [confirmedOn]
  /// is the Day 1 (or join) date the screen showed; if today is another
  /// date by now, nothing starts and the setup is re-read so the screen
  /// shows the new dates (see [WinterArcService.startWinterArc]).
  Future<ActionResult<WinterArcSession>> start({
    required LocalDate confirmedOn,
  }) async {
    final status = ref.read(arcResolutionProvider.notifier);
    final result = await runAction(
      'habit_setup',
      () => ref
          .read(winterArcServiceProvider)
          .startWinterArc(confirmedOn: confirmedOn),
    );
    // Publish the started arc so the router leaves setup for Today; after a
    // refusal (e.g. the season ended meanwhile) show the current state.
    if (result is ActionSuccess) {
      await _republish(status);
    } else {
      await refresh();
    }
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
