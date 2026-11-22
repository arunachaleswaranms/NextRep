import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import 'arc_clock_guard.dart';
import 'arc_pause.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Freeze, Cancel pause and Resume of an active Rolling Arc (Phase 12E2,
/// ARC_CONTROL_SPEC § 5).
///
/// Every write is one `WinterArcRepository.changeFreezes` transaction: the
/// stored session and its last activity date are re-read inside it, the
/// pure [ArcPauseRules] decide with one clock read, and at most one
/// `arc_freezes` row (and, on Resume, the session's end date) is written.
/// A refusal or a storage error writes nothing. No XP, progress, day mode,
/// reflection, unlock or goal revision is ever touched.
///
/// Each write takes the arc the user was looking at ([sessionId]) and the
/// date the screen showed, so a sheet left open over midnight is refused
/// rather than applied to a date the user wasn't shown.
///
/// Writes run one at a time ([SerialQueue]); a repeated request finds its
/// own result already stored and changes nothing. Reminders are re-planned
/// by the caller afterwards (`ReminderService.reconcile`).
final class ArcPauseService {
  ArcPauseService({
    required this._sessions,
    required this._activity,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final ArcActivityRepository _activity;
  final Clock _clock;
  final _queue = SerialQueue();

  /// What the Pause sheet shows for arc [sessionId] now. Read-only.
  Future<PausePreview> pausePreview(int sessionId) async {
    final session = await _require(sessionId);
    final today = _clock.today();
    return PausePreview(
      session: session,
      today: today,
      blocker: ArcPauseRules.blockerOn(session, today),
      guard: session.participationStartDate == null
          ? ClockGuardSafe(today: today, earliestSafe: today)
          : ArcClockGuard.check(
              session: session,
              lastActivityDate: await _activity.lastActivityDate(session.id),
              today: today,
            ),
    );
  }

  /// What the Resume sheet shows for arc [sessionId] now. Read-only.
  Future<ResumePreview> resumePreview(int sessionId) async {
    final session = await _require(sessionId);
    final now = _clock.now();
    final today = LocalDate.fromDateTime(now);
    WinterArcSession? resumed;
    if (session.openFreeze case final open?
        when session.status == WinterArcStatus.active &&
            !today.isBefore(open.frozenFrom)) {
      resumed = ArcPauseRules.resume(
        session,
        today: today,
        now: now,
        shownOn: today,
      ).applyTo(session);
    }
    return ResumePreview(session: session, today: today, resumed: resumed);
  }

  /// Schedules a pause of arc [sessionId] from tomorrow, which the Pause
  /// sheet showed as [frozenFrom]. See [ArcPauseRules.pause] for the
  /// refusals. Returns the stored arc.
  Future<WinterArcSession> pause({
    required int sessionId,
    required LocalDate frozenFrom,
  }) => _queue.run(() {
    final now = _clock.now();
    final today = LocalDate.fromDateTime(now);
    return _sessions.changeFreezes(
      sessionId,
      (session, facts) => ArcPauseRules.pause(
        session,
        today: today,
        now: now,
        lastActivityDate: facts.lastActivityDate,
        shownFrozenFrom: frozenFrom,
      ),
    );
  });

  /// Deletes the pause of arc [sessionId] that has not started yet, on
  /// the day it was scheduled, with the clock checks of
  /// [ArcPauseRules.cancel] made inside the transaction. Returns the stored
  /// arc.
  Future<WinterArcSession> cancelPause({required int sessionId}) =>
      _queue.run(() {
        final now = _clock.now();
        final today = LocalDate.fromDateTime(now);
        return _sessions.changeFreezes(
          sessionId,
          (session, facts) => ArcPauseRules.cancel(
            session,
            today: today,
            now: now,
            lastActivityDate: facts.lastActivityDate,
            latestRecordedAt: facts.latestRecordedAt,
          ),
        );
      });

  /// Resumes arc [sessionId] today, which the Resume sheet showed as [on].
  /// See [ArcPauseRules.resume]. Returns the stored arc.
  Future<WinterArcSession> resume({
    required int sessionId,
    required LocalDate on,
  }) => _queue.run(() {
    final now = _clock.now();
    final today = LocalDate.fromDateTime(now);
    return _sessions.changeFreezes(
      sessionId,
      (session, _) =>
          ArcPauseRules.resume(session, today: today, now: now, shownOn: on),
    );
  });

  Future<WinterArcSession> _require(int sessionId) async {
    final session = await _sessions.sessionById(sessionId);
    if (session == null) {
      throw DomainFailure(DomainRule.sessionNotFound, 'No session $sessionId');
    }
    return session;
  }
}
