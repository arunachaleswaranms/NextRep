import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import 'winter_arc_session.dart';

/// Persistence boundary for Winter Arc sessions.
///
/// A user can have any number of completed sessions but at most one
/// unfinished one (setup or active). Implementations enforce that when
/// creating a session.
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

  /// The most recently created completed session, or null.
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

  /// Persists [session]'s status, dates, participation start and start
  /// timestamp. The kind never changes.
  Future<void> updateSession(WinterArcSession session);

  /// Permanently deletes session [id] and everything it owns (habits,
  /// revisions, progress, day modes, XP, achievement unlocks, reflections),
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
