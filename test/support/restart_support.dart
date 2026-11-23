import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_arc_activity_repository.dart';
import 'package:nextrep/domain/winter_arc/arc_restart.dart';
import 'package:nextrep/domain/winter_arc/arc_restart_service.dart';

import 'fakes.dart';
import 'review_db.dart';

/// Phase 12F test helpers: the real Restart service over a [TestApp]'s
/// Drift database, and the "only these rows changed" check of spec § 10 T2
/// / addendum § L7 F2-12. All data is synthetic.

/// The real [ArcRestartService] over [app]'s database and clock.
ArcRestartService restartServiceOf(TestApp app) => ArcRestartService(
  sessions: app.sessions,
  habits: app.habits,
  activity: DriftArcActivityRepository(app.db),
  clock: app.clock,
);

/// Restarts arc [id] now, confirming exactly what the screen would show
/// (its preview's today and last lived day).
Future<RestartOutcome> restartNow(TestApp app, int id) async {
  final service = restartServiceOf(app);
  final preview = await service.preview(id);
  expect(
    preview.canRestart,
    isTrue,
    reason: 'restart offered: ${preview.blocker} ${preview.guard}',
  );
  return service.restart(
    sessionId: id,
    shownOn: preview.today,
    shownClosedOn: preview.closedOn!,
  );
}

/// Restarts arc [id] confirming [shownOn] and [shownClosedOn] as given
/// (for refusals).
Future<RestartOutcome> restartAs(
  TestApp app,
  int id, {
  LocalDate? shownOn,
  LocalDate? shownClosedOn,
}) {
  final today = app.clock.today();
  return restartServiceOf(app).restart(
    sessionId: id,
    shownOn: shownOn ?? today,
    shownClosedOn: shownClosedOn ?? today,
  );
}

const _restartTables = {'winter_arc_sessions', 'arc_freezes', 'habits'};

/// Checks that [after] is [before] plus exactly one Restart of arc [oldId]
/// into the new arc [newId] (spec § 10 T2, T3, addendum § L7 F2-12):
///
/// * every table other than sessions, freezes and habits is identical, row
///   for row (progress, day modes, XP, unlocks, reflections, goal
///   revisions, reminder, Focus Guard and sound settings);
/// * the old session row differs only in `status` (`ended`) and
///   `closed_on`; every other session row is identical; one new row;
/// * the freezes are identical except the removed open one
///   ([removedFreeze]);
/// * every existing habit row is identical; the new arc has exactly
///   [newHabits] habit rows, and nothing else of it exists.
void expectOnlyRestart(
  DbSnapshot before,
  DbSnapshot after, {
  required int oldId,
  required int newId,
  required LocalDate closedOn,
  required int newHabits,
  LocalDate? removedFreeze,
}) {
  expect(after.keys.toSet(), before.keys.toSet());
  for (final table in before.keys) {
    if (_restartTables.contains(table)) continue;
    expect(after[table], before[table], reason: '$table changed');
  }
  // Sessions.
  final sessionsBefore = before['winter_arc_sessions']!;
  final sessionsAfter = after['winter_arc_sessions']!;
  expect(sessionsAfter, hasLength(sessionsBefore.length + 1));
  for (final row in sessionsBefore) {
    final now = sessionsAfter.singleWhere((r) => r['id'] == row['id']);
    if (row['id'] == oldId) {
      expect(row['status'], 'active');
      expect(now, {
        ...row,
        'status': 'ended',
        'closed_on': closedOn.toIsoString(),
      }, reason: 'only status and closed_on of the old arc change');
    } else {
      expect(now, row, reason: 'session ${row['id']} changed');
    }
  }
  final added = sessionsAfter.singleWhere((r) => r['id'] == newId);
  expect(added['status'], 'active');
  expect(added['arc_kind'], 'rolling92');
  expect(added['closed_on'], isNull);
  // Freezes.
  final freezesBefore = [
    for (final f in before['arc_freezes']!)
      if (!(f['session_id'] == oldId &&
          f['resumed_on'] == null &&
          removedFreeze != null &&
          f['frozen_from'] == removedFreeze.toIsoString()))
        f,
  ];
  expect(
    freezesBefore.length,
    before['arc_freezes']!.length - (removedFreeze == null ? 0 : 1),
    reason: 'the removed freeze was the open one',
  );
  expect(after['arc_freezes'], freezesBefore, reason: 'freezes');
  // Habits.
  final habitsAfter = after['habits']!;
  expect(
    [
      for (final h in habitsAfter)
        if (h['session_id'] != newId) h,
    ],
    before['habits'],
    reason: 'existing habit rows are identical',
  );
  expect(
    habitsAfter.where((h) => h['session_id'] == newId),
    hasLength(newHabits),
  );
  // Nothing else belongs to the new arc.
  for (final table in before.keys) {
    if (table == 'winter_arc_sessions' || table == 'habits') continue;
    final rows = after[table]!;
    if (rows.isNotEmpty && rows.first.containsKey('session_id')) {
      expect(
        rows.where((r) => r['session_id'] == newId),
        isEmpty,
        reason: '$table has rows of the new arc',
      );
    }
  }
}
