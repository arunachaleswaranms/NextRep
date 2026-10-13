import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../progress/progress_repository.dart';
import '../winter_arc/current_arc_service.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'hydration_planner.dart';
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

  /// Saved, but the system scheduler failed. The next launch or resume
  /// reconciles again, so the reminders catch up then.
  savedNotScheduled,
}

/// Whether Hydration Coach can run for the arc as it is now.
enum HydrationAvailability {
  /// The active arc has the built-in Water habit.
  available,

  /// No arc is running.
  noActiveArc,

  /// The active arc has no built-in Water habit (a custom habit named
  /// "Water" doesn't count).
  noBuiltInWater,
}

/// Reminder use cases: the user's preferences and the reminders they imply
/// for the active arc.
///
/// [reconcile] makes the scheduler's pending reminders exactly what
/// [ReminderPlanner] says they should be: daily, reflection and hydration
/// in one complete plan. It is idempotent and safe to call any time: at
/// launch, on resume, at local midnight, after a preference change, after
/// any change to the active arc's day (Water logged or undone, Minimum Day
/// on or off, a habit edit), when the arc starts or closes (no active arc
/// means nothing pending) and after a restore.
final class ReminderService {
  ReminderService({
    required WinterArcRepository sessions,
    required this._progress,
    required this._preferences,
    required this._scheduler,
    required this._clock,
    this._onScheduleError,
  }) : _arcs = CurrentArcService(sessions);

  final CurrentArcService _arcs;
  final ProgressRepository _progress;
  final ReminderPreferencesRepository _preferences;
  final ReminderScheduler _scheduler;
  final Clock _clock;

  /// Told about a scheduler failure that [update] doesn't surface as a
  /// failure (the preferences were saved).
  final void Function(Object error, StackTrace stackTrace)? _onScheduleError;
  final _queue = SerialQueue();

  Future<ReminderPreferences> preferences() => _preferences.load();

  /// Whether notifications may currently be shown. Never prompts.
  Future<bool> permissionGranted() => _scheduler.permissionGranted();

  /// Whether Hydration Coach can run: the active arc has the built-in Water
  /// habit, found by its stable id whatever its title.
  Future<HydrationAvailability> hydrationAvailability() async {
    final active = (await _arcs.resolve()).active;
    if (active == null) return HydrationAvailability.noActiveArc;
    final records = await _progress.loadArc(active.id);
    return records.habits.habit(builtInWaterHabitId) == null
        ? HydrationAvailability.noBuiltInWater
        : HydrationAvailability.available;
  }

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
        (next.reflectionEnabled && !previous.reflectionEnabled) ||
        (next.hydrationEnabled && !previous.hydrationEnabled);
    if (turningOn &&
        !await _scheduler.permissionGranted() &&
        !await _scheduler.requestPermission()) {
      return ReminderUpdate.permissionDenied;
    }
    await _preferences.save(next, at: _clock.now());
    try {
      await _reconcile();
    } catch (error, stackTrace) {
      // The preference is stored: say so rather than "something went
      // wrong" with a switch that then reads as on.
      _onScheduleError?.call(error, stackTrace);
      return ReminderUpdate.savedNotScheduled;
    }
    return ReminderUpdate.saved;
  });

  /// Brings the pending reminders in line with the preferences and the
  /// active arc, and returns what is now pending.
  Future<List<PlannedReminder>> reconcile() => _queue.run(_reconcile);

  Future<List<PlannedReminder>> _reconcile() async {
    final preferences = await _preferences.load();
    final active = (await _arcs.resolve()).active;
    final now = _clock.now();
    final plan = ReminderPlanner.plan(
      preferences: preferences,
      active: active,
      now: now,
      hydration: preferences.hydrationEnabled && active != null
          ? await _hydrationDays(active, now)
          : const [],
    );
    if (plan.isEmpty) {
      await _scheduler.cancelAll();
    } else {
      await _scheduler.schedule(plan);
    }
    return plan;
  }

  /// The stored state of the hydration horizon, today first: the arc's
  /// habit history, day modes and progress, and when today's Water was last
  /// logged.
  Future<List<HydrationDay>> _hydrationDays(
    WinterArcSession arc,
    DateTime now,
  ) async {
    final today = LocalDate.fromDateTime(now);
    final records = await _progress.loadArc(arc.id);
    final lastLogged = await _progress.progressUpdatedAt(
      arc.id,
      builtInWaterHabitId,
      today,
    );
    return [
      for (var offset = 0; offset < HydrationPlanner.horizonDays; offset++)
        HydrationDay.of(
          arc: arc,
          records: records,
          date: today.addDays(offset),
          lastLoggedAt: offset == 0 ? lastLogged : null,
        ),
    ];
  }
}
