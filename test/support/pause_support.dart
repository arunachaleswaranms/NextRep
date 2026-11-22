import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_arc_activity_repository.dart';
import 'package:nextrep/domain/winter_arc/arc_pause_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'arcs.dart';
import 'fakes.dart';
import 'review_db.dart';

/// Phase 12E2 test helpers: the real Freeze service over a [TestApp]'s
/// Drift database, arcs started and lived through the app's own write
/// paths, and "only these rows changed" checks. All data is synthetic.

/// The real [ArcPauseService] over [app]'s database and clock.
ArcPauseService pauseServiceOf(TestApp app) => ArcPauseService(
  sessions: app.sessions,
  activity: DriftArcActivityRepository(app.db),
  clock: app.clock,
);

/// Starts a fresh Rolling Arc (the starter habits) with Day 1 on [day1],
/// 09:00, through the real services.
Future<WinterArcSession> startRolling(TestApp app, LocalDate day1) async {
  at(app, day1);
  await app.winterArc.beginSetup();
  return app.winterArc.startWinterArc();
}

/// Moves the clock to [date] (09:00 unless [hour]) and completes every
/// habit: a Perfect Day, with its progress, XP and possible unlocks.
Future<void> liveDay(TestApp app, LocalDate date, {int hour = 9}) async {
  at(app, date, hour: hour);
  await app.lifecycle.reconcile();
  await completeAll(app);
  await app.achievements.reconcile();
}

/// Lives every challenge date from [from] through [to] as a Perfect Day.
Future<void> liveDays(TestApp app, LocalDate from, LocalDate to) async {
  for (var d = from; !d.isAfter(to); d = d.addDays(1)) {
    await liveDay(app, d);
  }
}

/// A matcher for a [DomainFailure] of [rule].
Matcher throwsRule(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Every table except `arc_freezes`, with the session rows' `end_date`
/// removed: what Freeze, Cancel pause and Resume must leave byte-identical
/// (addendum § L3).
Future<DbSnapshot> everythingButPauses(TestApp app) async {
  final all = await snapshotAll(app.db)
    ..remove('arc_freezes');
  all['winter_arc_sessions'] = [
    for (final row in all['winter_arc_sessions']!)
      Map.of(row)..remove('end_date'),
  ];
  return all;
}

/// The stored `arc_freezes` rows.
Future<List<Map<String, Object?>>> freezeRows(TestApp app) async =>
    (await snapshotAll(app.db))['arc_freezes']!;

/// The session [id] as stored now.
Future<WinterArcSession> stored(TestApp app, int id) async =>
    (await app.sessions.sessionById(id))!;
