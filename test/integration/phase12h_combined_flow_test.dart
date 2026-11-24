import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/arc_restart/restart_labels.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/reconciliation.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';

/// Phase 12H combined flow (roadmap § 12H, addendum § L6, brief § 4): the
/// seven v1.3 features used together on one real SQLite **file**, through
/// the app's own services and Drift transactions, with an injected clock
/// for every multi-day step. Nothing is simulated by writing dates
/// directly: setup, reorder, start, logging, goal edits, Freeze, Resume,
/// Restart and deletion all go through their services.
///
/// Saved setup → edit and reorder → save → reopen (new process) → Confirm
/// & Start → log progress (Perfect, partial, Minimum, missed, goal
/// revisions, a disabled habit, a custom habit, a reflection) → Weekly
/// Review and Calendar → Freeze scheduled → Freeze active (new process) →
/// Resume on a later date → a second pause across a week boundary →
/// Restart on a day with progress → ended history (new process) → a date
/// rollback before `closedOn` → typed-DELETE deletion of only the named
/// Arc.
///
/// At every step every screen's read model is reconciled against the
/// spec's definitions (`expectAllArcsReconcile`: Today, Journey, Calendar,
/// Weekly Review, Summary, Arc History, Insights, raw XP ledger), and that
/// reconciliation must write nothing. An earlier completed Arc (2026) is
/// kept throughout, so Insights always span completed, ended and active
/// Arcs. All data is synthetic.

const _pushUps = HabitDraft(
  title: 'Push-ups',
  type: HabitType.count,
  iconKey: 'star',
  target: 20,
  minimumTarget: 10,
  unit: 'reps',
);

/// A real database file and the app's services over it. [reopen] is a
/// process reconstruction: the connection is closed and a new one, with
/// new services, is opened on the same file.
final class _Device {
  _Device(this.file, this.clock) : app = _open(file, clock);

  final File file;
  final FakeClock clock;
  TestApp app;

  static TestApp _open(File file, FakeClock clock) => TestApp(
    AppDatabase(NativeDatabase(file, setup: AppDatabase.configureConnection)),
    clock,
  );

  Future<void> reopen() async {
    await app.db.close();
    app = _open(file, clock);
  }
}

LocalDate _d(int y, int m, int d) => LocalDate(y, m, d);

Future<void> _log(TestApp app, String habitId) => completeHabit(app, habitId);

Future<int> _habitTarget(TestApp app, String habitId) async {
  final today = await app.tracking.today();
  return today.entries.firstWhere((e) => e.habit.id == habitId).target;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nextrep_12h_flow_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('saved setup → reorder → reopen → start → log → review and calendar '
      '→ freeze scheduled → frozen → resume → second pause → restart → '
      'ended history → typed deletion of only the old Arc', () async {
    final clock = FakeClock(DateTime(2026, 7, 1, 8));
    final device = _Device(File('${dir.path}/nextrep.sqlite'), clock);
    addTearDown(() => device.app.db.close());

    // ---- An earlier completed Arc (2026), kept to the end. -------------
    final first = await runFirstArc(device.app);
    expect(first.status, WinterArcStatus.completed);
    await expectAllArcsReconcile(device.app, context: 'completed only');

    // ---- 1. Saved setup: edit and reorder, never started. ---------------
    at(device.app, _d(2027, 2, 25));
    var app = device.app;
    final draft = await app.winterArc.beginSetup();
    expect(draft.status, WinterArcStatus.setup);
    final custom = await app.winterArc.addCustomHabit(_pushUps);
    await app.winterArc.addTemplateHabit('reading');
    await app.winterArc.editSetupHabit(
      'water',
      const HabitDraft(
        title: 'Water',
        type: HabitType.count,
        iconKey: 'water',
        target: 10,
        minimumTarget: 4,
        unit: 'glasses',
      ),
    );
    await app.winterArc.setHabitEnabled('meditation', enabled: false);
    final seeded = [for (final h in await app.winterArc.setupHabits()) h.id];
    final order = [
      custom.id,
      'reading',
      'water',
      for (final id in seeded)
        if (id != custom.id && id != 'reading' && id != 'water') id,
    ];
    await app.winterArc.reorderSetupHabits(order);
    expect(
      [for (final h in await app.winterArc.setupHabits()) h.id],
      order,
      reason: 'the visible order is stored',
    );
    final setupRows = await snapshotAll(app.db);

    // ---- 2. Process reconstruction: the setup is exactly as saved. -------
    await device.reopen();
    app = device.app;
    expect(await snapshotAll(app.db), setupRows, reason: 'nothing lost');
    final reopened = await app.winterArc.setup();
    expect(reopened.session.id, draft.id);
    expect(reopened.session.status, WinterArcStatus.setup);
    expect(reopened.session.participationStartDate, isNull);
    expect([for (final h in reopened.habits) h.id], order);

    // ---- 3. Confirm & Start, days later: Day 1 is the confirmation. ----
    at(app, _d(2027, 3, 1), hour: 8);
    final beforeStart = await snapshotAll(app.db);
    await expectLater(
      app.winterArc.startWinterArc(confirmedOn: _d(2027, 2, 28)),
      throwsA(isA<DomainFailure>()),
      reason: 'a start date the user was not shown is refused',
    );
    expect(await snapshotAll(app.db), beforeStart, reason: 'nothing started');
    final arc = await app.winterArc.startWinterArc(confirmedOn: _d(2027, 3, 1));
    expect(arc.id, draft.id);
    expect(arc.status, WinterArcStatus.active);
    expect(arc.startDate, _d(2027, 3, 1), reason: 'Day 1 = confirmation');
    expect(arc.dateOfDay(92), _d(2027, 5, 31));
    for (var d = _d(2027, 2, 25); d.isBefore(arc.startDate); d = d.addDays(1)) {
      expect(arc.isParticipatingOn(d), isFalse, reason: 'S3: $d is no day');
      expect(arc.dayNumberOf(d)!, lessThan(1), reason: 'before Day 1');
    }
    final started = await app.tracking.today();
    expect(
      [for (final e in started.entries) e.habit.id],
      [
        for (final h in reopened.habits)
          if (h.enabled) h.id,
      ],
      reason: 'Today follows the saved order (habits switched off hidden)',
    );
    var f = await expectArcReconciles(app, arc.id, context: 'Day 1 start');
    expect((f.elapsed, f.settled, f.open, f.ledgerXp), (1, 0, 1, 0));

    // Reminders on, so the pause can be checked against them later.
    await app.reminders.update(
      (p) => p.copyWith(dailyEnabled: true, reflectionEnabled: true),
    );

    // ---- 4. Week 1 (Days 1–7, 1–7 Mar 2027). ---------------------------
    // Lives challenge day [n], dated by the arc as stored now (pauses
    // move later days).
    Future<void> day(int n, Future<void> Function() log) async {
      final date = (await stored(app, arc.id)).dateOfDay(n)!;
      at(app, date, hour: 8);
      await app.lifecycle.reconcile();
      await expectAllArcsReconcile(app, context: 'morning of Day $n');
      at(app, date, hour: 20);
      await log();
      await app.achievements.reconcile();
      await expectAllArcsReconcile(app, context: 'evening of Day $n');
    }

    await day(1, () => completeAll(app)); // Perfect
    await day(2, () async {
      await _log(app, custom.id);
      await _log(app, 'water');
    }); // partial
    await day(3, () async {
      await app.tracking.activateMinimumDay(date: app.clock.today());
      await completeAll(app);
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(mood: Mood.good, win: 'Kept going'),
      );
    }); // Minimum Day complete
    await day(4, () async {
      // Nothing logged (missed); water's goal raised from Day 5.
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 12, minimumTarget: 5),
        date: app.clock.today(),
      );
    });
    await day(5, () async {
      expect(await _habitTarget(app, 'water'), 12, reason: 'revision lives');
      await app.tracking.activateMinimumDay(date: app.clock.today());
      await _log(app, 'water');
    }); // Minimum Day, partial
    await day(6, () async {
      await completeAll(app);
      await app.tracking.editHabit(
        habitId: 'reading',
        edit: const HabitEdit(enabled: false),
        date: app.clock.today(),
      );
    }); // Perfect; reading off from Day 7
    await day(7, () async {
      expect(
        (await app.tracking.today()).entries.map((e) => e.habit.id),
        isNot(contains('reading')),
        reason: 'disabled from Day 7',
      );
      await _log(app, 'water');
    });

    at(app, arc.dateOfDay(8)!, hour: 8);
    f = await expectArcReconciles(app, arc.id, context: 'Week 1 complete');
    final history = await app.tracking.historyFor(arc.id);
    final week1 = WeeklyReview.fromHistory(history, 1);
    expect(week1.status, ArcWeekStatus.complete);
    expect(week1.countedDays, 7);
    expect(week1.perfectDays, 2, reason: 'Days 1 and 6');
    expect(week1.minimumDaysChosen, 2, reason: 'Days 3 and 5');
    expect(week1.minimumDaysCompleted, 1, reason: 'Day 3');
    expect(week1.fullDays, 3);
    final week1Rows = week1.dailyCompletion;

    // ---- 5. Week 2, then a pause scheduled on Day 10. -------------------
    await day(8, () => completeAll(app));
    await day(9, () => completeAll(app));
    at(app, arc.dateOfDay(10)!, hour: 19);
    await app.lifecycle.reconcile();
    await _log(app, 'water');
    // A goal edit today waits for tomorrow, whatever the pause does (F1-1).
    await app.tracking.editHabit(
      habitId: custom.id,
      edit: const HabitEdit(target: 25, minimumTarget: 12),
      date: app.clock.today(),
    );
    final beforePause = await everythingButPauses(app);
    final ledgerBeforePause = await xpRows(app.db);
    final paused = await pauseServiceOf(app)
        .pause(sessionId: arc.id, frozenFrom: _d(2027, 3, 11));
    expect(paused.freezes.single.frozenFrom, _d(2027, 3, 11), reason: 'F1-1');
    expect(await everythingButPauses(app), beforePause, reason: 'Z4');
    final scheduled = await expectAllArcsReconcile(
      app,
      context: 'freeze scheduled',
    );
    final scheduledFigures = scheduled.firstWhere(
      (x) => x.status == WinterArcStatus.active,
    );
    expect(scheduledFigures.open, 1, reason: 'today still open (F4-6)');
    expect(scheduledFigures.dayNumberToday, 10);
    final remindersNow = await app.reminders.reconcile();
    expect(remindersNow, isNotEmpty);
    for (final r in remindersNow) {
      final date = LocalDate.fromDateTime(r.at);
      expect(
        paused.isFrozenOn(date),
        isFalse,
        reason: 'no reminder pending on paused $date (Z8)',
      );
    }

    // ---- 6. Frozen: midnight passes with no write; a new process. ------
    final frozenFigures = <ArcFigures>[];
    for (final date in [
      _d(2027, 3, 11),
      _d(2027, 3, 14),
      _d(2027, 3, 15), // a Monday: a new calendar week, the same Arc week
      _d(2027, 3, 19),
    ]) {
      at(app, date, hour: 10);
      final beforeMidnight = await snapshotAll(app.db);
      await app.lifecycle.reconcile();
      await app.achievements.reconcile();
      expect(
        await snapshotAll(app.db),
        beforeMidnight,
        reason: 'a paused date writes nothing ($date)',
      );
      final figures = (await expectAllArcsReconcile(
        app,
        context: 'paused $date',
      )).firstWhere((x) => x.status == WinterArcStatus.active);
      expect(figures.open, 0, reason: 'a paused date is not open');
      expect(figures.dayNumberToday, isNull, reason: 'not a challenge day');
      frozenFigures.add(figures);
      final today = await app.tracking.today();
      expect(today.isTrackable, isFalse, reason: 'nothing to track');
      await expectLater(
        app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: date,
        ),
        throwsA(isA<DomainFailure>()),
        reason: 'no progress on a paused date',
      );
      if (date == _d(2027, 3, 14)) {
        await device.reopen();
        app = device.app;
      }
    }
    for (final figures in frozenFigures) {
      expect(
        (
          figures.elapsed,
          figures.fullDays,
          figures.perfectDays,
          figures.ledgerXp,
        ),
        (
          frozenFigures.first.elapsed,
          frozenFigures.first.fullDays,
          frozenFigures.first.perfectDays,
          frozenFigures.first.ledgerXp,
        ),
        reason: 'figures do not move however long the pause (F4-5)',
      );
    }
    expect(frozenFigures.first.elapsed, 10, reason: 'Days 1–10 lived');
    expect(await xpRows(app.db), ledgerBeforePause, reason: 'no XP paused');
    final journeyPaused = await app.tracking.journeyFor(arc.id);
    expect(
      journeyPaused.days.where((d) => d.state == JourneyDayState.missed),
      hasLength(1),
      reason: 'only Day 4 is missed; no paused date becomes one (Z3)',
    );

    // ---- 7. Resume on a different calendar date than shown. ------------
    app.clock.current = DateTime(2027, 3, 19, 23, 59, 30);
    final preview = await pauseServiceOf(app).resumePreview(arc.id);
    expect(preview.today, _d(2027, 3, 19));
    app.clock.current = DateTime(2027, 3, 20, 0, 0, 30);
    final beforeResume = await snapshotAll(app.db);
    await expectLater(
      pauseServiceOf(app).resume(sessionId: arc.id, on: preview.today),
      throwsA(isA<DomainFailure>()),
      reason: 'the sheet showed 19 Mar; midnight passed',
    );
    expect(await snapshotAll(app.db), beforeResume, reason: 'nothing stored');
    final resumed = await pauseServiceOf(app)
        .resume(sessionId: arc.id, on: _d(2027, 3, 20));
    expect(resumed.dayNumberOf(_d(2027, 3, 20)), 11, reason: 'Z5');
    expect(resumed.dayNumberOf(_d(2027, 3, 10)), 10);
    expect(resumed.endDate, _d(2027, 6, 9), reason: '31 May + 9 paused');
    expect(resumed.lengthInDays, 92);
    at(app, _d(2027, 3, 20), hour: 8);
    expect(
      await _habitTarget(app, custom.id),
      25,
      reason: 'the edit waiting for tomorrow applies on resume (F1-2)',
    );
    await expectAllArcsReconcile(app, context: 'resumed Day 11');

    // ---- 8. Days 11–14, then a pause across the Week 2/3 boundary. -----
    await day(11, () => completeAll(app));
    await day(12, () => _log(app, 'water'));
    await day(13, () => completeAll(app));
    await day(14, () => completeAll(app));
    at(app, resumed.dateOfDay(14)!, hour: 21);
    await pauseServiceOf(app)
        .pause(sessionId: arc.id, frozenFrom: _d(2027, 3, 24));
    at(app, _d(2027, 3, 26), hour: 9);
    final boundary = await expectArcReconciles(
      app,
      arc.id,
      context: 'paused at the Week 2/3 boundary',
    );
    expect(boundary.elapsed, 14);
    final weeksPaused = ArcWeeks.of(
      await stored(app, arc.id),
      app.clock.today(),
    );
    expect(weeksPaused.week(2).status, ArcWeekStatus.complete);
    expect(weeksPaused.week(3).status, ArcWeekStatus.paused);
    at(app, _d(2027, 3, 27), hour: 8);
    final second = await pauseServiceOf(app)
        .resume(sessionId: arc.id, on: _d(2027, 3, 27));
    expect(second.freezes, hasLength(2), reason: 'multiple intervals');
    expect(second.dayNumberOf(_d(2027, 3, 27)), 15);
    expect(second.endDate, _d(2027, 6, 12), reason: '+9 then +3 paused');
    // Week 1 never changed through both pauses (R10).
    final week1Again = WeeklyReview.fromHistory(
      await app.tracking.historyFor(arc.id),
      1,
    );
    expect(week1Again.dailyCompletion, week1Rows);
    expect(week1Again.xpEarned, week1.xpEarned);

    for (var n = 15; n <= 20; n++) {
      await day(n, () => n.isEven ? completeAll(app) : _log(app, 'water'));
    }

    // ---- 9. Restart on Day 21, after logging today. ---------------------
    final day21 = second.dateOfDay(21)!;
    at(app, day21, hour: 12);
    await app.lifecycle.reconcile();
    await _log(app, 'water');
    final beforeRestart = await snapshotAll(app.db);
    final oldLedger = [
      for (final x in await xpRows(app.db))
        if (x.sessionId == arc.id) x,
    ];
    final outcome = await restartNow(app, arc.id);
    final newId = outcome.started.id;
    expectOnlyRestart(
      beforeRestart,
      await snapshotAll(app.db),
      oldId: arc.id,
      newId: newId,
      closedOn: day21,
      newHabits: order.length,
    );
    final old = await stored(app, arc.id);
    expect(old.status, WinterArcStatus.ended);
    expect(old.closedOn, day21, reason: 'logged today: closedOn is today');
    expect(endedEarlyLabel(old), 'Ended early · Day 21 of 92');
    expect(
      [
        for (final x in await xpRows(app.db))
          if (x.sessionId == arc.id) x,
      ],
      oldLedger,
      reason: 'the old ledger is identical row for row',
    );
    final fresh = await stored(app, newId);
    expect(fresh.startDate, day21, reason: 'the new Day 1 is today');
    expect(fresh.isSeasonal, isFalse, reason: "a Rolling Arc");
    final freshToday = await app.tracking.today();
    expect(
      [for (final e in freshToday.entries) e.habit.id],
      [
        for (final h in reopened.habits)
          if (h.enabled && h.id != 'reading') h.id,
      ],
      reason: 'order, on/off state survive the restart',
    );
    expect(await _habitTarget(app, custom.id), 25, reason: 'latest goal');
    expect(await _habitTarget(app, 'water'), 12, reason: 'latest goal');
    expect(freshToday.entries.where((e) => e.progress.completed), isEmpty);
    final atRestart = await expectAllArcsReconcile(app, context: 'restart');
    final endedOnClose = atRestart.firstWhere(
      (x) => x.status == WinterArcStatus.ended,
    );
    final newArc = atRestart.firstWhere(
      (x) => x.status == WinterArcStatus.active,
    );
    expect(endedOnClose.open, 0, reason: 'an ended Arc has no open day');
    expect(endedOnClose.todayXp, 0);
    expect(endedOnClose.elapsed, 21, reason: 'closedOn counted once');
    expect(endedOnClose.settled, 21);
    expect((newArc.ledgerXp, newArc.elapsed, newArc.open), (0, 1, 1));

    // ---- 10. A new process; the ended Arc viewed later. ----------------
    await device.reopen();
    app = device.app;
    at(app, day21.addDays(3));
    final later = (await expectAllArcsReconcile(
      app,
      context: 'ended Arc viewed later',
    )).firstWhere((x) => x.status == WinterArcStatus.ended);
    expect(
      (later.elapsed, later.fullDays, later.perfectDays, later.settledXp),
      (
        endedOnClose.elapsed,
        endedOnClose.fullDays,
        endedOnClose.perfectDays,
        endedOnClose.settledXp,
      ),
      reason: 'the same figures for every T ≥ closedOn (F4-3)',
    );
    // The date moves back before closedOn, then returns (F4-4, R19).
    at(app, day21.addDays(-1));
    final rolledBack = (await expectAllArcsReconcile(
      app,
      context: 'rolled back before closedOn',
    )).firstWhere((x) => x.status == WinterArcStatus.ended);
    expect(rolledBack.elapsed, 20);
    expect(rolledBack.futureXp, greaterThan(0), reason: 'closedOn is future');
    expect(rolledBack.todayXp, 0);
    at(app, day21.addDays(5));
    await expectAllArcsReconcile(app, context: 'date returned');

    // ---- 11. Deletion: only the named old Arc, only when asked. --------
    final active = await stored(app, newId);
    final beforeDelete = await snapshotAll(app.db);
    await expectLater(
      app.winterArc.deleteFinishedArc(active.id),
      throwsA(isA<DomainFailure>()),
      reason: 'an active Arc is never deleted',
    );
    // Leaving the DELETE screen (cancel) stores nothing: no intent kept.
    expect(await snapshotAll(app.db), beforeDelete, reason: 'cancelled');
    await app.winterArc.deleteFinishedArc(arc.id);
    final afterDelete = await snapshotAll(app.db);
    for (final table in beforeDelete.keys) {
      final rows = beforeDelete[table]!;
      final ofOld = table == 'winter_arc_sessions' ? 'id' : 'session_id';
      final kept = [
        for (final r in rows)
          if (!r.containsKey(ofOld) || r[ofOld] != arc.id) r,
      ];
      expect(
        afterDelete[table],
        kept,
        reason: '$table: only the old Arc\'s rows are gone',
      );
    }
    expect(await app.sessions.sessionById(first.id), isNotNull);
    expect(await app.sessions.sessionById(newId), isNotNull);
    final remaining = await expectAllArcsReconcile(app, context: 'deleted');
    expect(remaining, hasLength(2), reason: 'completed 2026 + new Arc');
  });

  test('Seasonal late join: no Freeze, pre-join weeks neutral, Minimum and '
      'Perfect Days, a restart with nothing logged today ends it yesterday '
      'and starts a Rolling Arc', () async {
    final clock = FakeClock(DateTime(2027, 10, 20, 9));
    final device = _Device(File('${dir.path}/nextrep.sqlite'), clock);
    addTearDown(() => device.app.db.close());
    final app = device.app;

    final season = await joinSeason(app, DateTime(2027, 10, 20));
    expect(season.isSeasonal, isTrue);
    expect(season.startDate, _d(2027, 10, 1), reason: 'the season Day 1');
    expect(season.dayNumberOf(_d(2027, 10, 20)), 20);
    var f = await expectArcReconciles(app, season.id, context: 'join day');
    expect((f.elapsed, f.open, f.settled), (1, 1, 0), reason: 'F4-8');
    final weeks = ArcWeeks.of(season, app.clock.today());
    expect(weeks.week(1).status, ArcWeekStatus.beforeJoining);
    expect(weeks.week(2).status, ArcWeekStatus.beforeJoining);
    expect(weeks.week(3).status, ArcWeekStatus.inProgress);

    // Freeze is never offered to, nor accepted from, a Seasonal Arc.
    final pausePreview = await pauseServiceOf(app).pausePreview(season.id);
    expect(pausePreview.blocker, isNotNull, reason: 'Z1');
    final beforePause = await snapshotAll(app.db);
    await expectLater(
      pauseServiceOf(app)
          .pause(sessionId: season.id, frozenFrom: pausePreview.frozenFrom),
      throwsA(isA<DomainFailure>()),
    );
    expect(await snapshotAll(app.db), beforePause);

    for (var n = 20; n <= 30; n++) {
      at(app, season.dateOfDay(n)!, hour: 19);
      await app.lifecycle.reconcile();
      switch (n % 4) {
        case 0:
          await completeAll(app);
        case 1:
          await app.tracking.activateMinimumDay(date: app.clock.today());
          await completeAll(app);
        case 2:
          await completeHabit(app, 'water');
        case _:
          break; // nothing logged
      }
      await app.achievements.reconcile();
      await expectAllArcsReconcile(app, context: 'season Day $n');
    }

    // Day 31: nothing logged today, Restart → closed on Day 30 (F2-1).
    at(app, season.dateOfDay(31)!, hour: 9);
    final outcome = await restartNow(app, season.id);
    expect(outcome.ended.closedOn, season.dateOfDay(30));
    expect(endedEarlyLabel(outcome.ended), 'Ended early · Day 30 of 92');
    expect(outcome.started.isSeasonal, isFalse, reason: 'F2-9: Rolling');
    expect(outcome.started.startDate, app.clock.today());
    final figures = await expectAllArcsReconcile(app, context: 'restarted');
    final ended = figures.firstWhere((x) => x.status == WinterArcStatus.ended);
    expect(ended.elapsed, 11, reason: 'Days 20–30: no pre-join date');
    expect(ended.open, 0);
    await device.reopen();
    await expectAllArcsReconcile(device.app, context: 'new process');
  });

  test(
    'Rolling Arc through Week 13: a 400-day pause, Freeze on Day 91, '
    'Day 92 open, completion, and a rollback into the completed Arc',
    () async {
      final clock = FakeClock(DateTime(2028, 1, 3, 9));
      final device = _Device(File('${dir.path}/nextrep.sqlite'), clock);
      addTearDown(() => device.app.db.close());
      var app = device.app;
      final arc = await startRolling(app, _d(2028, 1, 3));

      Future<WinterArcSession> live(int n) async {
        final s = await stored(app, arc.id);
        at(app, s.dateOfDay(n)!, hour: 19);
        await app.lifecycle.reconcile();
        if (n % 7 == 4) {
          // nothing logged: a missed day
        } else if (n % 5 == 0) {
          await app.tracking.activateMinimumDay(date: app.clock.today());
          await completeAll(app);
        } else {
          await completeAll(app);
        }
        await app.achievements.reconcile();
        return s;
      }

      for (var n = 1; n <= 86; n++) {
        await live(n);
        if (n == 1 || n == 84 || n == 85 || n == 86) {
          await expectAllArcsReconcile(app, context: 'Day $n');
        }
      }
      // A long pause from Day 87: 400 paused dates.
      var s = await stored(app, arc.id);
      final day86 = s.dateOfDay(86)!;
      await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: day86.addDays(1));
      for (final k in [1, 200, 400]) {
        at(app, day86.addDays(k));
        final p = await expectArcReconciles(app, arc.id, context: 'paused +$k');
        expect(p.elapsed, 86, reason: 'figures frozen at Day 86');
        expect(p.open, 0);
      }
      await device.reopen();
      app = device.app;
      at(app, day86.addDays(401));
      s = await pauseServiceOf(app)
          .resume(sessionId: arc.id, on: day86.addDays(401));
      expect(
        s.dayNumberOf(day86.addDays(401)),
        87,
        reason: 'numbering goes on',
      );
      expect(s.lengthInDays, 92);
      for (var n = 87; n <= 91; n++) {
        await live(n);
      }
      // Freeze on Day 91 (F1-8): the pause starts on the planned last date.
      s = await stored(app, arc.id);
      final day91 = s.dateOfDay(91)!;
      expect(s.endDate, day91.addDays(1));
      await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: day91.addDays(1));
      at(app, day91.addDays(3));
      var p = await expectArcReconciles(app, arc.id, context: 'paused Day 91');
      expect(p.status, WinterArcStatus.active, reason: 'Z6: never completes');
      at(app, day91.addDays(6), hour: 8);
      s = await pauseServiceOf(app)
          .resume(sessionId: arc.id, on: day91.addDays(6));
      expect(s.dayNumberOf(day91.addDays(6)), 92, reason: 'resume = Day 92');
      expect(s.freezes, hasLength(2));

      // Day 92: open, no Freeze offered (F1-9), Week 13 in progress.
      final preview = await pauseServiceOf(app).pausePreview(arc.id);
      expect(preview.blocker, isNotNull, reason: 'not on Day 92');
      p = await expectArcReconciles(app, arc.id, context: 'Day 92 morning');
      expect((p.open, p.dayNumberToday, p.elapsed), (1, 92, 92));
      await live(92);
      p = await expectArcReconciles(app, arc.id, context: 'Day 92 evening');
      final week13 = WeeklyReview.fromHistory(
        await app.tracking.historyFor(arc.id),
        13,
      );
      expect(week13.status, ArcWeekStatus.inProgress);
      expect(week13.countedDays, 7, reason: 'Days 85–91 settled');
      expect(week13.today, isNotNull, reason: 'Day 92 so far');

      // The day after: completed; Week 13 has 8 days.
      at(app, day91.addDays(7));
      await app.lifecycle.reconcile();
      await app.achievements.reconcile();
      final done = await stored(app, arc.id);
      expect(done.status, WinterArcStatus.completed);
      p = await expectArcReconciles(app, arc.id, context: 'completed');
      expect(
        (p.elapsed, p.settled, p.open, p.todayXp, p.futureXp),
        (92, 92, 0, 0, 0),
      );
      final final13 = WeeklyReview.fromHistory(
        await app.tracking.historyFor(arc.id),
        13,
      );
      expect(final13.status, ArcWeekStatus.complete);
      expect(final13.countedDays, 8, reason: 'Week 13 = Days 85–92');
      expect(final13.isFinalReview, isTrue);

      // The clock moves back into the completed Arc (F4-7, R22).
      final rows = await snapshotAll(app.db);
      at(app, day91.addDays(-1));
      await app.lifecycle.reconcile();
      p = await expectArcReconciles(app, arc.id, context: 'rolled back');
      expect(p.status, WinterArcStatus.completed, reason: 'never reopened');
      expect(p.open, 1, reason: 'one open day');
      expect(p.futureXp, greaterThan(0), reason: 'later XP is future-dated');
      expect(await snapshotAll(app.db), rows, reason: 'nothing written');
    },
  );
}
