import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../habit/habit_repository.dart';
import 'arc_clock_guard.dart';
import 'arc_restart.dart';
import 'winter_arc_repository.dart';

/// Restart of the active arc (Phase 12F, ARC_CONTROL_SPEC § 6): the old
/// arc ends early and a new Rolling arc starts on Day 1 today with the
/// same habits, in **one** `WinterArcRepository.restart` transaction. The
/// stored arc, its habits and its last activity date are re-read inside
/// it, the pure [ArcRestartRules] decide with one clock read, and either
/// both arcs are written or nothing is.
///
/// Each restart takes the arc the user was looking at ([sessionId]), the
/// date the screen showed as today and the last day it said the old arc
/// ends on, so a screen left open over midnight (or after the arc changed)
/// is refused rather than applied to something the user wasn't shown.
///
/// Restart never deletes anything. Deleting the old arc is a separate,
/// later transaction (`WinterArcService.deleteFinishedArc`), only after its
/// own typed confirmation (spec § 7).
///
/// Writes run one at a time ([SerialQueue]): a second request after a
/// committed restart finds the old arc ended and is refused, so one
/// confirmation never starts two arcs. Reminders are re-planned by the
/// caller afterwards (`ReminderService.reconcile`).
final class ArcRestartService {
  ArcRestartService({
    required this._sessions,
    required this._habits,
    required this._activity,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final HabitRepository _habits;
  final ArcActivityRepository _activity;
  final Clock _clock;
  final _queue = SerialQueue();

  /// What the Restart screen shows for arc [sessionId] now. Read-only.
  Future<RestartPreview> preview(int sessionId) async {
    final session = await _sessions.sessionById(sessionId);
    if (session == null) {
      throw DomainFailure(DomainRule.sessionNotFound, 'No session $sessionId');
    }
    final today = _clock.today();
    final history = await _habits.historyForSession(session.id);
    final started = session.participationStartDate != null;
    final lastActivity = started
        ? await _activity.lastActivityDate(session.id)
        : null;
    return RestartPreview(
      session: session,
      today: today,
      blocker: ArcRestartRules.blockerOn(session, today, habits: history),
      guard: started
          ? ArcClockGuard.check(
              session: session,
              lastActivityDate: lastActivity,
              today: today,
            )
          : ClockGuardSafe(today: today, earliestSafe: today),
      habits: ArcRestartRules.baselineFrom(history, createdAt: _clock.now()),
      lastActivityDate: lastActivity,
    );
  }

  /// Ends arc [sessionId] early and starts a new Rolling arc on Day 1
  /// today, which the screen showed as [shownOn], with the old arc closing
  /// on [shownClosedOn]. See [ArcRestartRules.decide] for the refusals; a
  /// refusal or a storage error writes nothing.
  Future<RestartOutcome> restart({
    required int sessionId,
    required LocalDate shownOn,
    required LocalDate shownClosedOn,
  }) => _queue.run(() {
    final now = _clock.now();
    final today = LocalDate.fromDateTime(now);
    return _sessions.restart(
      sessionId,
      (facts) => ArcRestartRules.decide(
        facts,
        today: today,
        now: now,
        shownOn: shownOn,
        shownClosedOn: shownClosedOn,
      ),
    );
  });
}
