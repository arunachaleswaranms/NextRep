import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import 'winter_arc_session.dart';

/// Why the clock guard refused a date: the latest of these dates is after
/// today.
enum ClockGuardBound {
  /// The arc's first participating date.
  participationStart,

  /// The latest activity row of the arc (`lastActivityDate`).
  lastActivity,

  /// The latest resume date of the arc's pauses.
  lastResume,
}

/// The outcome of [ArcClockGuard.check].
sealed class ClockGuardVerdict {
  const ClockGuardVerdict({required this.today, required this.earliestSafe});

  /// The local date that was checked.
  final LocalDate today;

  /// The earliest date the guard accepts: the latest of the participation
  /// start, the last activity date and the last resume date.
  final LocalDate earliestSafe;

  bool get isSafe => this is ClockGuardSafe;
}

/// [today] is not earlier than any recorded date of the arc.
final class ClockGuardSafe extends ClockGuardVerdict {
  const ClockGuardSafe({required super.today, required super.earliestSafe});
}

/// [today] is earlier than a recorded date of the arc (the local date
/// moved backwards). A lifecycle write must be refused; it becomes
/// possible again on [earliestSafe].
final class ClockGuardBehind extends ClockGuardVerdict {
  const ClockGuardBehind({
    required super.today,
    required super.earliestSafe,
    required this.bound,
  });

  /// Which recorded date is after [today].
  final ClockGuardBound bound;
}

/// The clock guard of addendum AD19, shared by the future Freeze (12E2)
/// and Restart (12F) transactions: a lifecycle write on local date `T` is
/// only safe when
///
/// * `T ≥` the participation start,
/// * `T ≥ lastActivityDate(s)`, when the arc has activity, and
/// * `T ≥` the latest `resumedOn` of the arc's pauses, when it has one.
///
/// **Activity** is daily progress, day modes, XP, reflections and
/// achievement unlock dates (addendum C7). A goal revision is
/// configuration, dated the day after it was written, and is never
/// activity: a revision dated tomorrow never refuses a write. Nothing else
/// (app-level settings, Focus Guard, reminders) is considered.
///
/// Pure: it reads nothing and writes nothing.
abstract final class ArcClockGuard {
  /// Checks [today] against [session]'s recorded dates.
  ///
  /// Throws [StateError] for a session in setup: it has no participation,
  /// and no lifecycle write applies to it.
  static ClockGuardVerdict check({
    required WinterArcSession session,
    required LocalDate? lastActivityDate,
    required LocalDate today,
  }) {
    var earliest = session.participationStart;
    var bound = ClockGuardBound.participationStart;
    if (lastActivityDate != null && lastActivityDate.isAfter(earliest)) {
      earliest = lastActivityDate;
      bound = ClockGuardBound.lastActivity;
    }
    for (final freeze in session.freezes) {
      if (freeze.resumedOn case final resumed? when resumed.isAfter(earliest)) {
        earliest = resumed;
        bound = ClockGuardBound.lastResume;
      }
    }
    return today.isBefore(earliest)
        ? ClockGuardBehind(today: today, earliestSafe: earliest, bound: bound)
        : ClockGuardSafe(today: today, earliestSafe: earliest);
  }
}

/// Reads the latest activity date of an arc.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class ArcActivityRepository {
  /// The latest date of any activity row of session [sessionId] (progress,
  /// day mode, XP, reflection, achievement unlock), or null when it has
  /// none. Goal revisions are never included. Read-only.
  Future<LocalDate?> lastActivityDate(int sessionId);
}

/// [ArcClockGuard] with the arc's activity read from storage and today
/// from the [Clock]. Read-only: evaluating it never writes.
///
/// Phase 12E1 provides it for the Freeze and Restart transactions of
/// Phases 12E2 and 12F, which must also re-check it inside their own
/// transaction. Nothing calls it before a write yet.
final class ArcClockGuardService {
  const ArcClockGuardService({required this._activity, required this._clock});

  final ArcActivityRepository _activity;
  final Clock _clock;

  Future<ClockGuardVerdict> evaluate(WinterArcSession session) async =>
      ArcClockGuard.check(
        session: session,
        lastActivityDate: await _activity.lastActivityDate(session.id),
        today: _clock.today(),
      );
}
