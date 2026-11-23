import 'dart:async';

import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/progress_repository.dart';
import 'package:nextrep/domain/winter_arc/arc_pause.dart';
import 'package:nextrep/domain/winter_arc/arc_restart.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_repository.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

/// Phase 12B: repository wrappers that count every call and can fail the
/// next snapshot read, for the Weekly Review's query-count and read-only
/// checks. They delegate to the real (Drift) repositories.

final class CountingProgressRepository implements ProgressRepository {
  CountingProgressRepository(this._inner);

  final ProgressRepository _inner;

  int loadArcCalls = 0;
  int writes = 0;
  int otherReads = 0;
  final loadedSessions = <int>[];

  /// Fails the next [loadArc] calls with a storage error.
  int failNextLoads = 0;

  /// While set, [loadArc] waits for it (a slow read).
  Completer<void>? gate;

  @override
  Future<ArcRecords> loadArc(int sessionId) async {
    loadArcCalls++;
    loadedSessions.add(sessionId);
    if (gate case final gate?) await gate.future;
    if (failNextLoads > 0) {
      failNextLoads--;
      throw const PersistenceFailure('simulated read failure');
    }
    return _inner.loadArc(sessionId);
  }

  @override
  Future<DayCommit<T>> commitDay<T>({
    required int sessionId,
    required LocalDate date,
    required DayCommitBuilder<T> build,
  }) {
    writes++;
    return _inner.commitDay(sessionId: sessionId, date: date, build: build);
  }

  @override
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date) {
    otherReads++;
    return _inner.progressOn(sessionId, date);
  }

  @override
  Future<DateTime?> progressUpdatedAt(
    int sessionId,
    String habitId,
    LocalDate date,
  ) {
    otherReads++;
    return _inner.progressUpdatedAt(sessionId, habitId, date);
  }

  @override
  Future<int> totalXp(int sessionId) {
    otherReads++;
    return _inner.totalXp(sessionId);
  }
}

final class CountingSessionRepository implements WinterArcRepository {
  CountingSessionRepository(this._inner);

  final WinterArcRepository _inner;

  int reads = 0;
  int writes = 0;

  @override
  Future<WinterArcSession?> latestSession() {
    reads++;
    return _inner.latestSession();
  }

  @override
  Future<WinterArcSession?> currentSession() {
    reads++;
    return _inner.currentSession();
  }

  @override
  Future<WinterArcSession?> latestCompletedSession() {
    reads++;
    return _inner.latestCompletedSession();
  }

  @override
  Future<WinterArcSession?> sessionById(int id) {
    reads++;
    return _inner.sessionById(id);
  }

  @override
  Future<List<WinterArcSession>> listSessions() {
    reads++;
    return _inner.listSessions();
  }

  @override
  Future<WinterArcSession> createSetupSession({
    required ArcKind kind,
    required LocalDate startDate,
    required LocalDate endDate,
    required DateTime createdAt,
    required List<Habit> habits,
  }) {
    writes++;
    return _inner.createSetupSession(
      kind: kind,
      startDate: startDate,
      endDate: endDate,
      createdAt: createdAt,
      habits: habits,
    );
  }

  @override
  Future<void> updateSession(WinterArcSession session) {
    writes++;
    return _inner.updateSession(session);
  }

  @override
  Future<WinterArcSession> changeFreezes(
    int sessionId,
    FreezeChange Function(WinterArcSession session, StoredArcFacts facts)
    decide,
  ) {
    writes++;
    return _inner.changeFreezes(sessionId, decide);
  }

  @override
  Future<RestartOutcome> restart(
    int sessionId,
    RestartPlan Function(RestartFacts facts) decide,
  ) {
    writes++;
    return _inner.restart(sessionId, decide);
  }

  @override
  Future<void> deleteSession(int id, {required WinterArcStatus expected}) {
    writes++;
    return _inner.deleteSession(id, expected: expected);
  }
}
