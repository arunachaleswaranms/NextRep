import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_fakes.dart';
import '../support/review_db.dart';

/// Phase 12F on a real in-memory Drift database: the optional deletion of
/// the old arc (ARC_CONTROL_SPEC § 7, T6–T8, addendum AD13), the Weekly
/// Review of an ended arc (ARC_MOMENTUM_SPEC § 12.3, R12), and generated
/// histories (pauses, goal changes, date rollbacks, Seasonal joins, year
/// boundaries, leap years) restarted at random points, each checked
/// against an independent calendar oracle and a backup round trip. All
/// data synthetic.

final day1 = LocalDate(2026, 10, 7);
LocalDate d(int n) => day1.addDays(n - 1);

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7, 9)));
  });
  tearDown(() => app.db.close());

  /// An arc lived Days 1–9 with a reflection, restarted on Day 10, and the
  /// new arc lived on Day 10.
  Future<(WinterArcSession old, WinterArcSession fresh)> restarted() async {
    final arc = await startRolling(app, day1);
    await liveDays(app, d(1), d(9));
    at(app, d(9));
    await app.reflections.save(
      sessionId: arc.id,
      date: d(9),
      draft: const ReflectionDraft(mood: Mood.good, win: 'Old arc'),
    );
    await app.tracking.editHabit(
      habitId: 'water',
      edit: const HabitEdit(target: 11, minimumTarget: 3),
      date: d(9),
    );
    at(app, d(10));
    final outcome = await restartNow(app, arc.id);
    await liveDay(app, d(10));
    return (outcome.ended, outcome.started);
  }

  /// [snapshot] without every row of session [id].
  DbSnapshot without(DbSnapshot snapshot, int id) => {
    for (final MapEntry(key: table, value: rows) in snapshot.entries)
      table: [
        for (final r in rows)
          if (!(r['session_id'] == id ||
              (table == 'winter_arc_sessions' && r['id'] == id)))
            r,
      ],
  };

  group('deleting the old arc (§ 7, T6–T8, AD13)', () {
    test('T7: removes exactly the ended arc, its freezes included; every '
        'other row is identical', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(3));
      at(app, d(3));
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(4));
      at(app, d(6));
      await pauseServiceOf(app).resume(sessionId: arc.id, on: d(6));
      await liveDay(app, d(6));
      at(app, d(7));
      final outcome = await restartNow(app, arc.id);
      await liveDay(app, d(7));
      expect(outcome.ended.freezes, hasLength(1), reason: 'a closed pause');
      final before = await snapshotAll(app.db);

      await app.winterArc.deleteFinishedArc(arc.id);

      final after = await snapshotAll(app.db);
      expect(after, without(before, arc.id));
      expect(
        (await snapshotAll(app.db))['arc_freezes'],
        isEmpty,
        reason: 'its freeze rows go with it',
      );
      expect((await app.sessions.currentSession())!.id, outcome.started.id);
    });

    test('a completed arc is deleted the same way', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(2));
      at(app, d(93));
      await app.lifecycle.reconcile();
      final before = await snapshotAll(app.db);
      await app.winterArc.deleteFinishedArc(arc.id);
      expect(await snapshotAll(app.db), without(before, arc.id));
    });

    test('D5: the active arc, a setup and an unknown arc are refused, with '
        'nothing deleted; the repository refuses an active arc whatever '
        'was asked', () async {
      final (old, fresh) = await restarted();
      final before = await snapshotAll(app.db);
      await expectLater(
        app.winterArc.deleteFinishedArc(fresh.id),
        throwsRule(DomainRule.arcNotDeletable),
      );
      await expectLater(
        app.sessions.deleteSession(fresh.id, expected: WinterArcStatus.active),
        throwsRule(DomainRule.arcNotDeletable),
      );
      await expectLater(
        app.sessions.deleteSession(fresh.id, expected: WinterArcStatus.ended),
        throwsRule(DomainRule.arcNotDeletable),
      );
      await expectLater(
        app.sessions.deleteSession(old.id, expected: WinterArcStatus.completed),
        throwsRule(DomainRule.arcNotDeletable),
        reason: 'the status is required inside the transaction',
      );
      await expectLater(
        app.winterArc.deleteFinishedArc(99),
        throwsRule(DomainRule.sessionNotFound),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('the service refuses an unfinished arc before reaching the '
        'repository (two independent guards)', () async {
      final (_, fresh) = await restarted();
      final counting = CountingSessionRepository(app.sessions);
      final service = WinterArcService(
        sessions: counting,
        habits: app.habits,
        clock: app.clock,
      );
      await expectLater(
        service.deleteFinishedArc(fresh.id),
        throwsRule(DomainRule.arcNotDeletable),
      );
      expect(counting.writes, 0, reason: 'deleteSession never called');
    });

    test('T8: a storage error at any cascade step leaves both arcs exactly '
        'as they were; a retry deletes', () async {
      final (old, _) = await restarted();
      for (final table in [
        'winter_arc_sessions',
        'habits',
        'habit_revisions',
        'daily_habit_progress_entries',
        'xp_transactions',
        'achievement_unlocks',
        'daily_reflections',
      ]) {
        final before = await snapshotAll(app.db);
        await app.db.customStatement(
          'CREATE TEMP TRIGGER injected_failure BEFORE DELETE ON $table '
          "BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
        await expectLater(
          app.winterArc.deleteFinishedArc(old.id),
          throwsA(anything),
          reason: table,
        );
        expect(await snapshotAll(app.db), before, reason: table);
        await app.db.customStatement('DROP TRIGGER injected_failure');
      }
      final before = await snapshotAll(app.db);
      await app.winterArc.deleteFinishedArc(old.id);
      expect(await snapshotAll(app.db), without(before, old.id));
    });

    test('derived views lose only that arc: Insights, History; a backup '
        'after the deletion round-trips', () async {
      final (old, fresh) = await restarted();
      final insightsBefore = await app.insights.snapshot();
      expect(insightsBefore.overall.arcCount, 2);
      expect(insightsBefore.overall.elapsedDays, 10);
      expect(insightsBefore.overall.completedArcs, 0);
      await app.winterArc.deleteFinishedArc(old.id);
      final insights = await app.insights.snapshot();
      expect(insights.overall.arcCount, 1);
      expect(insights.overall.elapsedDays, 1);
      expect(insights.overall.activeArc?.id, fresh.id);
      expect((await app.history.sessions()).map((s) => s.id), [fresh.id]);
      final export = await app.backup.export();
      final copy = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
      addTearDown(copy.db.close);
      await copy.backup.restore(await copy.backup.inspect(export.bytes));
      expect(
        await dumpOf(copy.db)
          ..remove('reminders'),
        await dumpOf(app.db)
          ..remove('reminders'),
      );
    });

    test('nothing is deleted by restarting, by leaving, or later: no '
        'deletion intent exists', () async {
      final (old, _) = await restarted();
      for (var t = d(10); t.isBefore(d(200)); t = t.addDays(17)) {
        at(app, t);
        await app.lifecycle.reconcile();
        await app.achievements.sync();
        expect(await app.sessions.sessionById(old.id), isNotNull);
      }
    });
  });

  group('Weekly Review of an ended arc (§ 12.3, R12)', () {
    test('the weeks up to closedOn are complete; later weeks are not '
        'reached; never changes for any later date', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(17));
      at(app, d(18));
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 12, minimumTarget: 4),
        date: d(18),
      );
      final outcome = await restartNow(app, arc.id);
      expect(outcome.ended.closedOn, d(17));
      List<ArcWeekStatus> statuses(LocalDate t) => [
        for (final w in ArcWeeks.of(outcome.ended, t).weeks) w.status,
      ];
      final reference = statuses(d(18));
      expect(reference.sublist(0, 3), everyElement(ArcWeekStatus.complete));
      expect(reference.sublist(3), everyElement(ArcWeekStatus.notReached));
      for (final t in [d(17), d(30), d(92), d(93), d(400)]) {
        final weeks = ArcWeeks.of(outcome.ended, t);
        expect(weeks.reviewableWeeks, [1, 2, 3], reason: '$t');
        expect(weeks.defaultWeek, 3, reason: '$t');
        expect(weeks.isFinalReview(3), isTrue, reason: '$t');
        expect(weeks.week(3).settledDates.last, d(17), reason: '$t');
        expect(statuses(t), reference, reason: '$t');
      }
      // The new arc has its own Week 1, in progress.
      final fresh = ArcWeeks.of(outcome.started, d(18));
      expect(fresh.week(1).status, ArcWeekStatus.inProgress);
      expect(fresh.reviewableWeeks, [1]);
    });
  });

  group('generated histories restarted at random points', () {
    for (var seed = 0; seed < 48; seed++) {
      test('seed $seed', () => _generated(seed), timeout: Timeout.factor(4));
    }
    // Runs after the seeds (tests in a file run in order).
    test('the generated histories cover every case', () {
      for (final key in [
        'restarted',
        'seasonal',
        'closed pause',
        'open pause at restart',
        'scheduled pause at restart',
        'rollback refused',
        'pending revision at restart',
        'crosses a year',
        'spans 29 Feb',
        'closed before today',
        'closed today',
      ]) {
        expect(_covered[key] ?? 0, greaterThan(0), reason: key);
      }
    });
  });
}

/// How often each case occurred in the generated histories.
final _covered = <String, int>{};
void _cover(String key) => _covered[key] = (_covered[key] ?? 0) + 1;

/// One generated history: an arc (Rolling or a Seasonal join, starting
/// near a year boundary or around a leap day) lived with partial days,
/// goal edits, pauses and resumes and date rollbacks, then restarted at a
/// random point. Checks the restart against an independent oracle, and
/// that a backup made then validates and round-trips.
Future<void> _generated(int seed) async {
  final rnd = Random(seed);
  final year = 2027 + rnd.nextInt(4); // 2028 is a leap year
  final seasonal = rnd.nextInt(5) == 0;
  final LocalDate start;
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(year)));
  addTearDown(app.db.close);
  WinterArcSession arc;
  if (seasonal) {
    start = LocalDate(year, 10, 1).addDays(rnd.nextInt(60));
    arc = await joinSeason(app, start.toLocalDateTime());
  } else {
    // Late December (crosses the year) or late February (a leap day in
    // 2028), or anywhere.
    start = switch (rnd.nextInt(3)) {
      0 => LocalDate(year, 12, 20).addDays(rnd.nextInt(12)),
      1 => LocalDate(year, 2, 20).addDays(rnd.nextInt(10)),
      _ => LocalDate(year, 1, 1).addDays(rnd.nextInt(365)),
    };
    arc = await startRolling(app, start);
  }
  const ids = ['workout', 'water', 'learning', 'english', 'no_junk_food'];
  var today = start;
  final restartAfter = 1 + rnd.nextInt(seasonal ? 40 : 70);
  for (var step = 0; step < restartAfter; step++) {
    at(app, today);
    await app.lifecycle.reconcile();
    final session = (await app.sessions.sessionById(arc.id))!;
    if (session.status != WinterArcStatus.active) return; // completed
    final roll = rnd.nextInt(20);
    if (session.isParticipatingOn(today)) {
      if (roll < 12) {
        for (final id in ids.take(1 + rnd.nextInt(3))) {
          await completeHabit(app, id);
        }
      }
      if (roll == 13 || roll == 14) {
        final dayNumber = session.dayNumberOf(today)!;
        if (dayNumber < 92) {
          await app.tracking.editHabit(
            habitId: 'water',
            edit: HabitEdit(target: 6 + rnd.nextInt(8), minimumTarget: 2),
            date: today,
          );
        }
      }
      if (roll == 15 && !seasonal && session.dayNumberOf(today)! < 92) {
        await pauseServiceOf(app)
            .pause(sessionId: arc.id, frozenFrom: today.addDays(1));
      }
    } else if (session.isFrozenOn(today) && session.hasOpenFreeze) {
      if (roll < 6) {
        await pauseServiceOf(app).resume(sessionId: arc.id, on: today);
      }
    }
    if (roll == 19 && step > 3) {
      // The date moves back for a moment: a restart is refused while it is
      // behind the history, with nothing written.
      final back = today.addDays(-1 - rnd.nextInt(3));
      at(app, back);
      // Not behind (nothing logged after `back`): a restart there would
      // be valid; it is not taken, so the history goes on.
      if (await _expectRestartGuarded(app, arc.id)) _cover('rollback refused');
      at(app, today);
    }
    today = today.addDays(1);
  }

  // Restart now (maybe while paused, or with a pause scheduled).
  at(app, today);
  await app.lifecycle.reconcile();
  var session = (await app.sessions.sessionById(arc.id))!;
  if (session.status != WinterArcStatus.active) return;
  // Sometimes today is logged first, so today is the last lived day.
  if (rnd.nextBool() && session.isParticipatingOn(today)) {
    await completeHabit(app, ids[rnd.nextInt(3)]);
  }
  // Sometimes a pause is scheduled from tomorrow just before restarting.
  if (rnd.nextInt(3) == 0 &&
      !seasonal &&
      !session.hasOpenFreeze &&
      session.isParticipatingOn(today) &&
      session.dayNumberOf(today)! < 92) {
    session = await pauseServiceOf(app)
        .pause(sessionId: arc.id, frozenFrom: today.addDays(1));
  }
  final before = await snapshotAll(app.db);
  final lastActivity = _lastActivity(before, arc.id);
  final expected = _oracleClosedOn(
    before,
    session,
    today: today,
    lastActivity: lastActivity,
  );
  final preview = await restartServiceOf(app).preview(arc.id);
  if (preview.guard is ClockGuardBehind) {
    fail('seed $seed: the clock moves only forward at the restart');
  }
  expect(preview.closedOn, expected, reason: 'seed $seed oracle');
  final open = session.hasOpenFreeze ? session.freezes.last : null;
  _cover('restarted');
  if (seasonal) _cover('seasonal');
  if (session.freezes.any((f) => !f.isOpen)) _cover('closed pause');
  if (open != null) {
    _cover(
      today.isBefore(open.frozenFrom)
          ? 'scheduled pause at restart'
          : 'open pause at restart',
    );
  }
  final revisions = before['habit_revisions']!.where(
    (r) =>
        r['session_id'] == arc.id &&
        LocalDate.parse(r['effective_from']! as String).isAfter(expected),
  );
  if (revisions.isNotEmpty) _cover('pending revision at restart');
  if (session.participationStart.year != today.year) _cover('crosses a year');
  final span = <LocalDate>[
    for (
      var t = session.participationStart;
      !t.isAfter(today);
      t = t.addDays(1)
    )
      t,
  ];
  if (span.any((t) => t.month == 2 && t.day == 29)) _cover('spans 29 Feb');
  _cover(expected == today ? 'closed today' : 'closed before today');
  final outcome = await restartNow(app, arc.id);
  expectOnlyRestart(
    before,
    await snapshotAll(app.db),
    oldId: arc.id,
    newId: outcome.started.id,
    closedOn: expected,
    removedFreeze: open?.frozenFrom,
    newHabits: 7,
  );
  final ended = outcome.ended;
  expect(ended.isFrozenOn(expected), isFalse);
  expect(ended.isParticipatingOn(expected), isTrue);
  expect(expected.isAfter(today), isFalse);
  if (lastActivity != null) expect(lastActivity.isAfter(expected), isFalse);
  expect(WinterArcRules.problemWith(ended), isNull);

  // A backup made now validates and round-trips row for row.
  final export = await app.backup.export();
  final copy = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
  addTearDown(copy.db.close);
  await copy.backup.restore(await copy.backup.inspect(export.bytes));
  final mine = _canonical(await snapshotAll(app.db));
  final theirs = _canonical(await snapshotAll(copy.db));
  for (final table in [
    'winter_arc_sessions',
    'arc_freezes',
    'habits',
    'habit_revisions',
    'daily_habit_progress_entries',
    'day_modes',
    'achievement_unlocks',
    'daily_reflections',
  ]) {
    expect(theirs[table], mine[table], reason: 'seed $seed $table');
  }
}

/// [rows] with each table's rows in a canonical order (a restore inserts
/// rows in its own order, so rowids differ).
DbSnapshot _canonical(DbSnapshot rows) => {
  for (final MapEntry(key: table, value: list) in rows.entries)
    table: [...list]..sort((a, b) => '$a'.compareTo('$b')),
};

/// A restart on the clock's date is refused (and writes nothing) exactly
/// when the clock is behind the arc's history. Returns whether it was.
Future<bool> _expectRestartGuarded(TestApp app, int id) async {
  final preview = await restartServiceOf(app).preview(id);
  if (preview.guard is! ClockGuardBehind) return false;
  final before = await snapshotAll(app.db);
  await expectLater(
    restartAs(app, id),
    throwsRule(DomainRule.clockBehindHistory),
  );
  expect(await snapshotAll(app.db), before);
  return true;
}

/// The latest activity date of [id], read from the raw rows (never a goal
/// revision).
LocalDate? _lastActivity(DbSnapshot rows, int id) {
  LocalDate? latest;
  for (final (table, column) in const [
    ('daily_habit_progress_entries', 'date'),
    ('day_modes', 'date'),
    ('xp_transactions', 'date'),
    ('daily_reflections', 'date'),
    ('achievement_unlocks', 'unlocked_on'),
  ]) {
    for (final r in rows[table]!) {
      if (r['session_id'] != id) continue;
      final date = LocalDate.parse(r[column]! as String);
      if (latest == null || date.isAfter(latest)) latest = date;
    }
  }
  return latest;
}

/// The last lived day by brute force over the raw freeze rows (spec
/// § 6.2's table), independent of the session's mapping.
LocalDate _oracleClosedOn(
  DbSnapshot rows,
  WinterArcSession session, {
  required LocalDate today,
  required LocalDate? lastActivity,
}) {
  final freezes = [
    for (final f in rows['arc_freezes']!)
      if (f['session_id'] == session.id)
        (
          from: LocalDate.parse(f['frozen_from']! as String),
          to: switch (f['resumed_on']) {
            final String s => LocalDate.parse(s),
            _ => null,
          },
        ),
  ];
  bool frozen(LocalDate date) => freezes.any(
    (f) => !date.isBefore(f.from) && (f.to == null || date.isBefore(f.to!)),
  );
  final joined = session.participationStart;
  bool participating(LocalDate date) =>
      !date.isBefore(joined) && !date.isAfter(session.endDate) && !frozen(date);
  if (participating(today) && lastActivity == today) return today;
  for (
    var date = today.addDays(-1);
    !date.isBefore(joined);
    date = date.addDays(-1)
  ) {
    if (participating(date)) return date;
  }
  return joined;
}
