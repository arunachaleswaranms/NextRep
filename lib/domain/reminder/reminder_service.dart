import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../winter_arc/current_arc_service.dart';
import '../winter_arc/winter_arc_repository.dart';
import 'reminder_plan.dart';
import 'reminder_preferences.dart';
import 'reminder_scheduler.dart';

/// Outcome of changing the reminder preferences.
enum ReminderUpdate {
  /// Saved and the pending reminders were brought in line.
  saved,

  /// A reminder was being turned on but notification permission was
  /// denied. Nothing was saved.
  permissionDenied,
}

/// Reminder use cases: the user's preferences and the reminders they imply
/// for the active arc.
///
/// [reconcile] makes the scheduler's pending reminders exactly what
/// [ReminderPlanner] says they should be. It is idempotent and safe to call
/// any time: at launch, on resume, after a preference change, and when the
/// arc starts or closes (no active arc means nothing pending).
final class ReminderService {
  ReminderService({
    required WinterArcRepository sessions,
    required this._preferences,
    required this._scheduler,
    required this._clock,
  }) : _arcs = CurrentArcService(sessions);

  final CurrentArcService _arcs;
  final ReminderPreferencesRepository _preferences;
  final ReminderScheduler _scheduler;
  final Clock _clock;
  final _queue = SerialQueue();

  Future<ReminderPreferences> preferences() => _preferences.load();

  /// Whether notifications may currently be shown. Never prompts.
  Future<bool> permissionGranted() => _scheduler.permissionGranted();

  /// Applies [change] to the stored preferences, saves the result and
  /// reconciles. The change is applied inside the queue to whatever is
  /// stored at that moment, so two quick edits (e.g. two switches flipped
  /// before the first save finished) both land instead of the second
  /// overwriting the first with a stale copy.
  ///
  /// Permission is asked for only when a reminder is being turned on, so a
  /// denial is never followed by more prompts unless the user tries again;
  /// the app works fully without it.
  Future<ReminderUpdate> update(
    ReminderPreferences Function(ReminderPreferences current) change,
  ) => _queue.run(() async {
    final previous = await _preferences.load();
    final next = change(previous);
    final turningOn =
        (next.dailyEnabled && !previous.dailyEnabled) ||
        (next.reflectionEnabled && !previous.reflectionEnabled);
    if (turningOn &&
        !await _scheduler.permissionGranted() &&
        !await _scheduler.requestPermission()) {
      return ReminderUpdate.permissionDenied;
    }
    await _preferences.save(next, at: _clock.now());
    await _reconcile();
    return ReminderUpdate.saved;
  });

  /// Brings the pending reminders in line with the preferences and the
  /// active arc, and returns what is now pending.
  Future<List<PlannedReminder>> reconcile() => _queue.run(_reconcile);

  Future<List<PlannedReminder>> _reconcile() async {
    final plan = ReminderPlanner.plan(
      preferences: await _preferences.load(),
      active: (await _arcs.resolve()).active,
      now: _clock.now(),
    );
    if (plan.isEmpty) {
      await _scheduler.cancelAll();
    } else {
      await _scheduler.schedule(plan);
    }
    return plan;
  }
}
