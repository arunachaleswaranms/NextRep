import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import 'arc_pause.dart';
import 'winter_arc_session.dart';

/// Persistence boundary for Winter Arc sessions.
///
/// A user can have any number of finished sessions (completed or ended)
/// but at most one unfinished one (setup or active). Implementations
/// enforce that when creating a session.
///
/// Every session returned carries its freeze intervals (oldest first) and
/// its `closedOn` date (schema v7).
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class WinterArcRepository {
  /// The most recently created session of any status, or null if none
  /// exists. Prefer the more specific lookups below: since Phase 4 the
  /// newest session isn't necessarily the one a screen should show.
  Future<WinterArcSession?> latestSession();

  /// The unfinished session (setup or active), or null. There is never more
  /// than one.
  Future<WinterArcSession?> currentSession();

  /// The most recently created **finished** session (completed or ended),
  /// or null: the read-only history the app falls back to when nothing is
  /// unfinished. An ended arc is history like a completed one, but it is
  /// never counted or awarded as completed (see [WinterArcStatus]).
  ///
  /// The name predates the `ended` status (schema v7) and is kept for the
  /// existing callers.
  Future<WinterArcSession?> latestCompletedSession();

  /// The session with [id], or null.
  Future<WinterArcSession?> sessionById(int id);

  /// Every session, newest first.
  Future<List<WinterArcSession>> listSessions();

  /// Atomically creates a session of [kind] in [WinterArcStatus.setup]
  /// together with its initial habit configuration. It has no
  /// participation date until it starts.
  ///
  /// Throws a `DomainFailure` with `DomainRule.arcInProgress`, writing
  /// nothing, if an unfinished session already exists.
  Future<WinterArcSession> createSetupSession({
    required ArcKind kind,
    required LocalDate startDate,
    required LocalDate endDate,
    required DateTime createdAt,
    required List<Habit> habits,
  });

  /// Persists [session]'s status, dates, participation start, start
  /// timestamp and closing date. The kind never changes. Freeze intervals
  /// are never written by this method (see [changeFreezes]).
  Future<void> updateSession(WinterArcSession session);

  /// Freeze, Cancel pause and Resume (Phase 12E2), in **one transaction**:
  ///
  /// 1. session [sessionId] is read with its freeze intervals, together with
  ///    [StoredArcFacts]: its last activity date
  ///    (`ArcActivityRepository.lastActivityDate`) and the latest instant
  ///    anything of it was written, inside the transaction;
  /// 2. [decide] returns the [FreezeChange] to make, or throws (typically a
  ///    `DomainFailure`) to refuse, and then nothing is written;
  /// 3. the change is applied: at most one `arc_freezes` row and, for a
  ///    [CloseFreeze], the session's `end_date`. No other row of any table
  ///    is written;
  /// 4. the stored session is read back; it must equal
  ///    `change.applyTo(session)` and keep every arc invariant
  ///    (`WinterArcRules.problemWith`), otherwise the whole transaction is
  ///    rolled back (`DomainRule.invalidArc`).
  ///
  /// Returns the stored session afterwards. Throws
  /// `DomainRule.sessionNotFound` for an unknown id, and
  /// `PersistenceFailure` on storage errors; either way nothing changed.
  Future<WinterArcSession> changeFreezes(
    int sessionId,
    FreezeChange Function(WinterArcSession session, StoredArcFacts facts)
    decide,
  );

  /// Permanently deletes session [id] and everything it owns (habits,
  /// revisions, progress, day modes, XP, achievement unlocks, reflections,
  /// freeze intervals),
  /// in one transaction, provided its status is [expected]. App-level data
  /// (reminder preferences) is never touched.
  ///
  /// The status is checked inside the transaction. Throws, deleting
  /// nothing, `DomainRule.sessionNotFound` if there is no such session,
  /// `DomainRule.arcNotDeletable` if a completed arc was expected and
  /// `DomainRule.sessionNotInSetup` if a setup arc was expected but the
  /// status differs.
  Future<void> deleteSession(int id, {required WinterArcStatus expected});
}
