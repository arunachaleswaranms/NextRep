import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/journey/arc_calendar.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/arc_pause.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/review_db.dart';

/// Phase 12E2: Freeze, Cancel pause and Resume through the real service on
/// a real in-memory Drift database with an injected clock (ARC_CONTROL_SPEC
/// § 5, § 10 Z1–Z12; addendum § L3 and § L7 F1). Every write goes through
/// the app's own write paths; "nothing else changed" is checked on full
/// table snapshots. All data is synthetic.

final day1 = LocalDate(2027, 3, 1); // a Monday; Day 92 is 31 May 2027
LocalDate d(int n) => day1.addDays(n - 1);

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(
      memoryDatabase(),
      FakeClock(DateTime(2027, 3, 1, 9)),
      scheduler: FakeReminderScheduler(granted: true),
    );
  });
  tearDown(() => app.db.close());

  Future<WinterArcSession> pauseOn(int id, LocalDate today) {
    at(app, today);
    return pauseServiceOf(app)
        .pause(sessionId: id, frozenFrom: today.addDays(1));
  }

  Future<WinterArcSession> resumeOn(int id, LocalDate today) {
    at(app, today);
    return pauseServiceOf(app).resume(sessionId: id, on: today);
  }

  group('Freeze starts tomorrow; today still counts (F2, Z2, Z10)', () {
    for (final day in [1, 25, 91]) {
      test('Freeze on Day $day', () async {
        final arc = await startRolling(app, day1);
        at(app, d(day));
        await completeHabit(app, 'water'); // activity today
        final before = await everythingButPauses(app);
        final xpBefore = await xpRows(app.db);

        final paused = await pauseOn(arc.id, d(day));

        expect(paused.freezes, hasLength(1));
        expect(paused.freezes.single.frozenFrom, d(day + 1));
        expect(paused.freezes.single.isOpen, isTrue);
        expect(paused.endDate, d(92), reason: 'end moves only on Resume');
        expect(await everythingButPauses(app), before, reason: 'F7');
        expect(await xpRows(app.db), xpBefore, reason: 'no XP for Freeze');
        if (day == 91) {
          expect(
            paused.freezes.single.frozenFrom,
            d(92),
            reason: 'F1-8: the planned last date',
          );
        }

        // Today is a normal challenge day until midnight.
        final today = await app.tracking.today();
        expect(today.isTrackable, isTrue);
        expect(today.position, isA<ArcInProgress>());
        expect((today.position as ArcInProgress).dayNumber, day);
        await app.tracking.activateMinimumDay(date: d(day));
        await completeAll(app);
        await app.reflections.save(
          sessionId: arc.id,
          date: d(day),
          draft: const ReflectionDraft(mood: Mood.good, win: 'Still counts'),
        );
        if (day < 91) {
          final edit = await app.tracking.editHabit(
            habitId: 'water',
            edit: const HabitEdit(target: 9, minimumTarget: 3),
            date: d(day),
          );
          expect(edit.value.configFrom, d(day + 1), reason: 'Z10');
        }
        final after = await stored(app, arc.id);
        expect(after.freezes.single.frozenFrom, d(day + 1));
        expect(await xpRows(app.db), isNot(xpBefore), reason: 'today earned');
      });
    }

    test('Day 92: not offered and refused by the service (Z1, F1-9)', () async {
      final arc = await startRolling(app, day1);
      at(app, d(92));
      final session = await stored(app, arc.id);
      expect(ArcPauseRules.blockerOn(session, d(92)), PauseBlocker.lastDay);
      final preview = await pauseServiceOf(app).pausePreview(arc.id);
      expect(preview.canPause, isFalse);
      final before = await snapshotAll(app.db);
      await expectLater(
        pauseOn(arc.id, d(92)),
        throwsRule(DomainRule.pauseUnavailable),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('a stale sheet (midnight passed) is refused: nothing is stored on '
        'another date', () async {
      final arc = await startRolling(app, day1);
      at(app, d(10), hour: 23);
      final shown = (await pauseServiceOf(app).pausePreview(arc.id)).frozenFrom;
      expect(shown, d(11));
      app.clock.current = DateTime(2027, 3, 11, 0, 0, 1);
      final before = await snapshotAll(app.db);
      await expectLater(
        pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: shown),
        throwsRule(DomainRule.pauseDateChanged),
      );
      expect(await snapshotAll(app.db), before);
      // Re-read: the new dates, and then it works.
      final fresh = await pauseServiceOf(app).pausePreview(arc.id);
      expect(fresh.frozenFrom, d(12));
      final paused = await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: fresh.frozenFrom);
      expect(paused.freezes.single.frozenFrom, d(12));
    });
  });

  group('refused for every arc that is not an active Rolling Arc (F1, Z1)', () {
    Future<void> refused(int id, LocalDate today, PauseBlocker blocker) async {
      at(app, today);
      final session = await stored(app, id);
      expect(ArcPauseRules.blockerOn(session, today), blocker);
      final before = await snapshotAll(app.db);
      await expectLater(
        pauseOn(id, today),
        throwsRule(DomainRule.pauseUnavailable),
      );
      expect(await snapshotAll(app.db), before);
    }

    test('Seasonal', () async {
      final arc = await joinSeason(app, DateTime(2027, 10, 5));
      await refused(arc.id, LocalDate(2027, 10, 5), PauseBlocker.seasonal);
    });

    test('setup', () async {
      at(app, day1);
      final setup = await app.winterArc.beginSetup();
      await refused(setup.id, day1, PauseBlocker.notActive);
    });

    test('completed', () async {
      final done = await runFirstArc(app);
      await refused(done.id, app.clock.today(), PauseBlocker.notActive);
    });

    test('ended', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(3));
      await endArc(app, arc.id, d(3));
      await refused(arc.id, d(3), PauseBlocker.notActive);
    });

    test('already scheduled, and paused', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(5));
      // A repeated request for the same start changes nothing.
      final again = await pauseOn(arc.id, d(5));
      expect(again.freezes, hasLength(1));
      expect(ArcPauseRules.blockerOn(again, d(5)), PauseBlocker.scheduled);
      await refused(arc.id, d(6), PauseBlocker.paused);
      await refused(arc.id, d(40), PauseBlocker.paused);
    });

    test('before the first day (clock moved back)', () async {
      final arc = await startRolling(app, day1);
      await refused(arc.id, d(0), PauseBlocker.notChallengeDay);
    });
  });

  group('Cancel pause (F3)', () {
    test('schedule and cancel on the same day: every table is exactly as '
        'before', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(4));
      final before = await snapshotAll(app.db);
      await pauseOn(arc.id, d(4));
      final cancelled = await pauseServiceOf(app)
          .cancelPause(sessionId: arc.id);
      expect(cancelled.freezes, isEmpty);
      expect(await snapshotAll(app.db), before);
      // Nothing was paused: tomorrow is Day 5.
      at(app, d(5));
      final tomorrow = await app.tracking.today();
      expect((tomorrow.position as ArcInProgress).dayNumber, 5);
    });

    test('after midnight the pause has begun: Cancel is refused, nothing '
        'changes', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(4));
      app.clock.current = DateTime(2027, 3, 5, 0, 0, 1);
      final before = await snapshotAll(app.db);
      await expectLater(
        pauseServiceOf(app).cancelPause(sessionId: arc.id),
        throwsRule(DomainRule.pauseAlreadyStarted),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('with nothing scheduled, nothing is written', () async {
      final arc = await startRolling(app, day1);
      at(app, d(2));
      final before = await snapshotAll(app.db);
      await pauseServiceOf(app).cancelPause(sessionId: arc.id);
      expect(await snapshotAll(app.db), before);
    });
  });

  group('midnight and the paused day (F6, Z2, Z3, Z6)', () {
    test('scheduled → paused at midnight with no write; every write is '
        'refused on a paused date', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(10));
      await pauseOn(arc.id, d(10));
      final before = await snapshotAll(app.db);

      app.clock.current = DateTime(2027, 3, 11, 0, 0, 1);
      await app.lifecycle.reconcile();
      await app.achievements.reconcile();
      final today = await app.tracking.today();
      await app.tracking.journey();
      await app.history.card(arc.id);
      await app.insights.snapshot();
      await app.reflections.journal();
      await app.tracking.habitSettings();
      expect(await snapshotAll(app.db), before, reason: 'no midnight write');

      expect(today.position, isA<ArcPaused>());
      final position = today.position as ArcPaused;
      expect(position.lastDayNumber, 10);
      expect(position.pausedSince, d(11));
      expect(position.resumesOn, isNull);
      expect(today.isTrackable, isFalse);
      expect(today.canSwitchToMinimum, isFalse);
      final settings = await app.tracking.habitSettings();
      expect(settings.pausedToday, isTrue);
      expect(settings.editable, isFalse);
      expect(
        (await app.reflections.journal()).canWriteToday,
        isFalse,
        reason: 'no reflection on a paused date',
      );

      final date = d(11);
      await expectLater(
        app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: date,
        ),
        throwsRule(DomainRule.arcNotRunningToday),
      );
      await expectLater(
        app.tracking.activateMinimumDay(date: date),
        throwsRule(DomainRule.arcNotRunningToday),
      );
      await expectLater(
        app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 12),
          date: date,
        ),
        throwsRule(DomainRule.arcNotRunningToday),
      );
      await expectLater(
        app.reflections.save(
          sessionId: arc.id,
          date: date,
          draft: const ReflectionDraft(mood: Mood.good, win: 'no'),
        ),
        throwsA(isA<DomainFailure>()),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('a paused arc never completes, however long (Z6, F12)', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(91));
      for (final days in [92, 93, 200, 400]) {
        at(app, d(days));
        final home = await app.lifecycle.reconcile();
        expect(home!.status, WinterArcStatus.active, reason: 'day $days');
      }
    });

    test('paused dates are never missed: Journey, Calendar and the summary '
        'count none of them (Z3)', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(3));
      await pauseOn(arc.id, d(3));
      at(app, d(30)); // 27 paused dates so far
      final journey = await app.tracking.journey();
      expect(journey.days, hasLength(92));
      expect(
        journey.days.where((j) => j.state == JourneyDayState.missed),
        isEmpty,
      );
      expect(
        journey.days.take(3).map((j) => j.state),
        everyElement(JourneyDayState.perfect),
      );
      expect(journey.days.skip(3).every((j) => j.date == null), isTrue);
      final card = await app.history.card(arc.id);
      expect(card.summary.daysElapsed, 3);
      expect(card.summary.consistencyPercent, 100);
      final calendar = ArcCalendar.of(journey);
      expect(calendar.pauses.single.afterDay, 3);
      expect(calendar.pauses.single.scheduled, isFalse);
    });
  });

  group('Resume (F5, Z5, AD7)', () {
    test('the worked example: Day 10, nine paused dates, Day 11 on 20 March, '
        'last day 9 June, completes on 10 June', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(10));
      await pauseOn(arc.id, d(10));
      final before = await everythingButPauses(app);
      final xpBefore = await xpRows(app.db);

      final resumed = await resumeOn(arc.id, LocalDate(2027, 3, 20));

      expect(await everythingButPauses(app), before, reason: 'Z4');
      expect(await xpRows(app.db), xpBefore, reason: 'no XP for Resume');
      expect(resumed.freezes.single.resumedOn, LocalDate(2027, 3, 20));
      expect(resumed.freezes.single.pausedDays, 9);
      expect(resumed.endDate, LocalDate(2027, 6, 9));
      expect(resumed.lengthInDays, 92);
      expect(resumed.dayNumberOf(LocalDate(2027, 3, 20)), 11);
      expect(resumed.dateOfDay(92), LocalDate(2027, 6, 9));
      for (var n = 1; n <= 10; n++) {
        expect(resumed.dateOfDay(n), d(n), reason: 'lived days keep dates');
      }
      expect(WinterArcRules.problemWith(resumed), isNull);
      final today = await app.tracking.today();
      expect(today.isTrackable, isTrue);
      expect((today.position as ArcInProgress).dayNumber, 11);

      at(app, LocalDate(2027, 6, 9));
      expect((await app.lifecycle.reconcile())!.status, WinterArcStatus.active);
      at(app, LocalDate(2027, 6, 10));
      expect(
        (await app.lifecycle.reconcile())!.status,
        WinterArcStatus.completed,
      );
    });

    test(
      'Resume on the first paused date deletes the empty interval',
      () async {
        final arc = await startRolling(app, day1);
        await liveDay(app, d(6));
        final before = await snapshotAll(app.db);
        await pauseOn(arc.id, d(6));
        final resumed = await resumeOn(arc.id, d(7));
        expect(resumed.freezes, isEmpty);
        expect(resumed.endDate, d(92));
        expect(await snapshotAll(app.db), before);
        expect(
          ((await app.tracking.today()).position as ArcInProgress).dayNumber,
          7,
        );
      },
    );

    test('Day 91: the resume date is Day 92; completes the day after '
        '(F1-8)', () async {
      final arc = await startRolling(app, day1);
      at(app, d(91));
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 11, minimumTarget: 3),
        date: d(91),
      );
      await pauseOn(arc.id, d(91));
      final r = LocalDate(2027, 6, 5);
      final resumed = await resumeOn(arc.id, r);
      expect(resumed.dayNumberOf(r), 92);
      expect(resumed.endDate, r);
      final today = await app.tracking.today();
      expect(
        today.entries.firstWhere((e) => e.habit.id == 'water').target,
        11,
        reason: 'the waiting revision applies on Day 92',
      );
      at(app, r.addDays(1));
      expect(
        (await app.lifecycle.reconcile())!.status,
        WinterArcStatus.completed,
      );
    });

    test('refusals: a stale date, a pause not started, an arc not paused; '
        'nothing changes', () async {
      final arc = await startRolling(app, day1);
      at(app, d(4));
      final service = pauseServiceOf(app);
      var before = await snapshotAll(app.db);
      await expectLater(
        service.resume(sessionId: arc.id, on: d(4)),
        completes,
        reason: 'running today: already resumed, nothing to do',
      );
      expect(await snapshotAll(app.db), before);
      await pauseOn(arc.id, d(4));
      before = await snapshotAll(app.db);
      await expectLater(
        service.resume(sessionId: arc.id, on: d(4)),
        throwsRule(DomainRule.notPaused),
      );
      at(app, d(9));
      await expectLater(
        service.resume(sessionId: arc.id, on: d(8)),
        throwsRule(DomainRule.resumeDateChanged),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('duplicate and concurrent requests: one row, one closure', () async {
      final arc = await startRolling(app, day1);
      at(app, d(3));
      final service = pauseServiceOf(app);
      await Future.wait([
        service.pause(sessionId: arc.id, frozenFrom: d(4)),
        service.pause(sessionId: arc.id, frozenFrom: d(4)),
        service.pause(sessionId: arc.id, frozenFrom: d(4)),
      ]);
      expect(await freezeRows(app), hasLength(1));
      at(app, d(8));
      final results = await Future.wait([
        service.resume(sessionId: arc.id, on: d(8)),
        service.resume(sessionId: arc.id, on: d(8)),
      ]);
      expect(results.map((s) => s.endDate).toSet(), {d(92).addDays(4)});
      final rows = await freezeRows(app);
      expect(rows, hasLength(1));
      expect(rows.single['resumed_on'], d(8).toIsoString());
    });
  });

  group('goal revisions wait for the resume date (F1-1 … F1-4, Z10, Z11)', () {
    Future<List<Map<String, Object?>>> revisions() async =>
        (await snapshotAll(app.db))['habit_revisions']!;

    test('F1-1, F1-2: an edit today, then Freeze: the pause still starts '
        'tomorrow; the edit applies on the resume date; its row never '
        'changes', () async {
      final arc = await startRolling(app, day1);
      at(app, d(10));
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 20, minimumTarget: 5),
        date: d(10),
      );
      final stored0 = await revisions();
      expect(stored0.single['effective_from'], d(11).toIsoString());

      final paused = await pauseOn(arc.id, d(10));
      expect(paused.freezes.single.frozenFrom, d(11), reason: 'Z10');
      expect(await revisions(), stored0);

      final r = LocalDate(2027, 3, 20);
      await resumeOn(arc.id, r);
      expect(await revisions(), stored0, reason: 'Z11: never re-dated');
      final history = await app.habits.historyForSession(arc.id);
      final water = history.habit('water')!;
      expect(history.configOn(water, r).target, 20);
      for (var n = 1; n <= 10; n++) {
        expect(history.configOn(water, d(n)).target, 8, reason: 'Day $n');
      }
      final today = await app.tracking.today();
      expect(today.entries.firstWhere((e) => e.habit.id == 'water').target, 20);
    });

    test('F1-3: three habits edited on the same day all wait and all apply '
        'on resume', () async {
      final arc = await startRolling(app, day1);
      at(app, d(5));
      for (final (id, edit) in const [
        ('water', HabitEdit(target: 10, minimumTarget: 4)),
        ('workout', HabitEdit(target: 45, minimumTarget: 15)),
        ('learning', HabitEdit(enabled: false)),
      ]) {
        await app.tracking.editHabit(habitId: id, edit: edit, date: d(5));
      }
      final before = await revisions();
      expect(before, hasLength(3));
      await pauseOn(arc.id, d(5));
      final r = d(5).addDays(7);
      await resumeOn(arc.id, r);
      expect(await revisions(), before);
      final today = await app.tracking.today();
      final targets = {for (final e in today.entries) e.habit.id: e.target};
      expect(targets['water'], 10);
      expect(targets['workout'], 45);
      expect(targets.containsKey('learning'), isFalse, reason: 'switched off');
    });

    test('F1-4: a second edit of the same habit replaces the first; one '
        'revision, dated tomorrow', () async {
      final arc = await startRolling(app, day1);
      at(app, d(5));
      for (final target in [10, 12]) {
        await app.tracking.editHabit(
          habitId: 'water',
          edit: HabitEdit(target: target, minimumTarget: 4),
          date: d(5),
        );
      }
      await pauseOn(arc.id, d(5));
      final rows = await revisions();
      expect(rows, hasLength(1));
      expect(rows.single['effective_from'], d(6).toIsoString());
      expect(rows.single['target'], 12);
    });

    test(
      'with a pause scheduled, Habits says an edit waits for the resume',
      () async {
        final arc = await startRolling(app, day1);
        at(app, d(5));
        expect((await app.tracking.habitSettings()).waitsForResume, isFalse);
        await pauseOn(arc.id, d(5));
        final settings = await app.tracking.habitSettings();
        expect(settings.waitsForResume, isTrue);
        expect(settings.configEditable, isTrue, reason: 'F7a: edits allowed');
      },
    );
  });

  group('clock guard (F2a, AD19, Z12, F1-6, F1-7, F1-10)', () {
    test(
      'F1-6, F1-7: activity dated 18 Oct, clock on 17 Oct: refused and '
      'nothing stored; the refusal names 18 Oct; on 18 Oct it works',
      () async {
        final arc = await startRolling(app, LocalDate(2027, 10, 1));
        await liveDay(app, LocalDate(2027, 10, 18));
        at(app, LocalDate(2027, 10, 17));
        final preview = await pauseServiceOf(app).pausePreview(arc.id);
        expect(preview.blocker, isNull);
        final guard = preview.guard as ClockGuardBehind;
        expect(guard.earliestSafe, LocalDate(2027, 10, 18));
        expect(guard.bound, ClockGuardBound.lastActivity);
        final before = await snapshotAll(app.db);
        await expectLater(
          pauseOn(arc.id, LocalDate(2027, 10, 17)),
          throwsRule(DomainRule.clockBehindHistory),
        );
        expect(await snapshotAll(app.db), before);

        final paused = await pauseOn(arc.id, LocalDate(2027, 10, 18));
        expect(paused.freezes.single.frozenFrom, LocalDate(2027, 10, 19));
      },
    );

    test(
      'a goal revision dated tomorrow is configuration, never activity',
      () async {
        final arc = await startRolling(app, day1);
        at(app, d(5));
        await app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 9, minimumTarget: 3),
          date: d(5),
        );
        final preview = await pauseServiceOf(app).pausePreview(arc.id);
        expect(preview.guard.isSafe, isTrue);
        expect(preview.canPause, isTrue);
      },
    );

    for (final logAfterResume in [false, true]) {
      test('F1-10: freeze, resume (${logAfterResume ? 'with' : 'without'} '
          'activity after it), date moves back before the pause: refused '
          'until the resume date; intervals never overlap', () async {
        final arc = await startRolling(app, day1);
        await pauseOn(arc.id, d(10));
        await resumeOn(arc.id, d(15));
        if (logAfterResume) await liveDay(app, d(15));
        at(app, d(9));
        final session = await stored(app, arc.id);
        expect(session.isParticipatingOn(d(9)), isTrue, reason: 'trackable');
        final preview = await pauseServiceOf(app).pausePreview(arc.id);
        expect((preview.guard as ClockGuardBehind).earliestSafe, d(15));
        final before = await snapshotAll(app.db);
        await expectLater(
          pauseOn(arc.id, d(9)),
          throwsRule(DomainRule.clockBehindHistory),
        );
        expect(await snapshotAll(app.db), before);
        // Tracking today still works (spec § 5.4).
        await completeHabit(app, 'water');
        // From the resume date on it is allowed again; no overlap.
        final again = await pauseOn(arc.id, d(15));
        expect(again.freezes, hasLength(2));
        expect(again.freezes.last.frozenFrom, d(16));
        expect(WinterArcRules.problemWith(again), isNull);
      });
    }
  });

  group('time zone and clock moves (spec § 5.4)', () {
    test(
      'back before a scheduled pause: that date is a challenge date',
      () async {
        final arc = await startRolling(app, day1);
        await pauseOn(arc.id, d(10));
        at(app, d(12)); // paused
        expect((await app.tracking.today()).isTrackable, isFalse);
        at(app, d(9)); // back before frozenFrom
        final today = await app.tracking.today();
        expect(today.isTrackable, isTrue);
        expect((today.position as ArcInProgress).dayNumber, 9);
        await completeHabit(app, 'water');
        final s = await stored(app, arc.id);
        expect(s.scheduledPauseOn(d(9))!.frozenFrom, d(11));
      },
    );

    test('into a closed pause: paused, read-only, "continues on" its resume '
        'date, and Resume is not offered again', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(10));
      await resumeOn(arc.id, d(15));
      await liveDay(app, d(15));
      at(app, d(13));
      final today = await app.tracking.today();
      final position = today.position as ArcPaused;
      expect(position.resumesOn, d(15));
      expect(position.lastDayNumber, 10);
      expect(today.isTrackable, isFalse);
      final preview = await pauseServiceOf(app).resumePreview(arc.id);
      expect(preview.canResume, isFalse);
      final before = await snapshotAll(app.db);
      await expectLater(
        resumeOn(arc.id, d(13)),
        throwsRule(DomainRule.notPaused),
      );
      await expectLater(
        pauseOn(arc.id, d(13)),
        throwsRule(DomainRule.pauseUnavailable),
      );
      expect(await snapshotAll(app.db), before);
      // The date returns: Day 11 again, with its rows.
      at(app, d(15));
      final back = await app.tracking.today();
      expect((back.position as ArcInProgress).dayNumber, 11);
      expect(back.isPerfect, isTrue);
    });

    test('daylight saving and late or early hours change nothing', () async {
      final arc = await startRolling(app, day1);
      // US DST starts 14 Mar 2027, EU on 28 Mar 2027.
      app.clock.current = DateTime(2027, 3, 13, 23, 59);
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(14));
      app.clock.current = DateTime(2027, 3, 29, 0, 0, 1);
      final resumed = await pauseServiceOf(app)
          .resume(sessionId: arc.id, on: LocalDate(2027, 3, 29));
      expect(resumed.freezes.single.pausedDays, 15);
      expect(resumed.dayNumberOf(LocalDate(2027, 3, 29)), 14);
      expect(resumed.endDate, d(92).addDays(15));
    });

    test('a year boundary and a leap day', () async {
      final arc = await startRolling(app, LocalDate(2027, 12, 1));
      expect(arc.endDate, LocalDate(2028, 3, 1));
      await pauseOn(arc.id, LocalDate(2027, 12, 30)); // Day 30
      var s = await resumeOn(arc.id, LocalDate(2028, 1, 3));
      expect(s.freezes.single.pausedDays, 3);
      expect(s.dayNumberOf(LocalDate(2028, 1, 3)), 31);
      expect(s.endDate, LocalDate(2028, 3, 4));
      // Day 86 is 27 Feb 2028; paused 28 Feb, 29 Feb and 1 Mar.
      expect(s.dayNumberOf(LocalDate(2028, 2, 27)), 86);
      await pauseOn(arc.id, LocalDate(2028, 2, 27));
      s = await resumeOn(arc.id, LocalDate(2028, 3, 2));
      expect(s.freezes.last.pausedDays, 3);
      expect(s.dayNumberOf(LocalDate(2028, 3, 2)), 87);
      expect(s.dateOfDay(92), LocalDate(2028, 3, 7));
      expect(s.endDate, LocalDate(2028, 3, 7));
      expect(WinterArcRules.problemWith(s), isNull);
    });
  });

  group('several pauses and a long one (F1-11, F13)', () {
    test(
      'five freeze/resume cycles: continuous day numbers, end = start + '
      '91 + paused days, no XP, unlock or progress row from any of them',
      () async {
        final arc = await startRolling(app, day1);
        var today = d(1);
        var lived = 0;
        var paused = 0;
        for (final k in [1, 2, 3, 5, 8]) {
          await liveDay(app, today);
          lived++;
          final before = await everythingButPauses(app);
          await pauseOn(arc.id, today);
          final r = today.addDays(1 + k);
          final s = await resumeOn(arc.id, r);
          expect(await everythingButPauses(app), before, reason: 'k=$k');
          paused += k;
          expect(s.dayNumberOf(r), lived + 1);
          expect(s.endDate, day1.addDays(91 + paused));
          expect(s.dateOfDay(92), s.endDate);
          today = r;
        }
        final s = await stored(app, arc.id);
        expect(s.freezes, hasLength(5));
        expect(s.pausedDays, 19);
        // Lived days keep their numbers.
        final journey = await app.tracking.journey();
        expect(
          journey.days.take(5).map((j) => j.state),
          everyElement(JourneyDayState.perfect),
        );
      },
    );

    test('pausing again on the resume date leaves a lived day between '
        '(F13)', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(4));
      await resumeOn(arc.id, d(8));
      final again = await pauseOn(arc.id, d(8));
      expect(again.freezes.last.frozenFrom, d(9));
      expect(WinterArcRules.problemWith(again), isNull);
    });

    test('a 400-day pause', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(25));
      await pauseOn(arc.id, d(25));
      at(app, d(26).addDays(399));
      expect((await app.lifecycle.reconcile())!.status, WinterArcStatus.active);
      final preview = await pauseServiceOf(app).resumePreview(arc.id);
      expect(preview.pausedDays, 399);
      final r = d(26).addDays(400);
      final s = await resumeOn(arc.id, r);
      expect(s.freezes.single.pausedDays, 400);
      expect(s.dayNumberOf(r), 26);
      expect(s.endDate, d(92).addDays(400));
      expect(s.dateOfDay(92), s.endDate);
      expect(s.dateOfDay(25), d(25));
    });
  });

  group('streaks join across a pause (F8, Z7)', () {
    test('a Perfect Day streak of 5 + 2 lived days is 7', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(5));
      await pauseOn(arc.id, d(5));
      final r = d(6).addDays(10);
      await resumeOn(arc.id, r);
      await liveDay(app, r);
      await liveDay(app, r.addDays(1));
      final history = await app.tracking.history();
      expect(history.perfectDays.streak.current, 7);
      expect(history.perfectDays.total, 7);
      expect(history.habitStreak('water').current, 7);
      expect(history.elapsedDates, hasLength(7));
    });
  });

  group('atomic: a failure at any step leaves everything as it was', () {
    Future<void> failOn(String when, String table) => app.db.customStatement(
      'CREATE TEMP TRIGGER injected_failure $when ON $table '
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    Future<void> heal() =>
        app.db.customStatement('DROP TRIGGER injected_failure');

    test('Freeze: the insert fails', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(3));
      final before = await snapshotAll(app.db);
      await failOn('BEFORE INSERT', 'arc_freezes');
      await expectLater(
        pauseOn(arc.id, d(3)),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await snapshotAll(app.db), before);
      await heal();
      expect((await pauseOn(arc.id, d(3))).freezes, hasLength(1));
    });

    test(
      'Resume: the end date fails after the freeze row was closed',
      () async {
        final arc = await startRolling(app, day1);
        await pauseOn(arc.id, d(3));
        at(app, d(9));
        final before = await snapshotAll(app.db);
        await failOn('BEFORE UPDATE', 'winter_arc_sessions');
        await expectLater(
          resumeOn(arc.id, d(9)),
          throwsA(isA<PersistenceFailure>()),
        );
        expect(await snapshotAll(app.db), before, reason: 'row still open');
        final still = await stored(app, arc.id);
        expect(still.hasOpenFreeze, isTrue);
        expect(still.endDate, d(92));
        await heal();
        expect((await resumeOn(arc.id, d(9))).endDate, d(92).addDays(5));
      },
    );

    test('Resume: closing the freeze row fails', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(3));
      at(app, d(9));
      final before = await snapshotAll(app.db);
      await failOn('BEFORE UPDATE', 'arc_freezes');
      await expectLater(
        resumeOn(arc.id, d(9)),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('Cancel pause: the delete fails', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(3));
      final before = await snapshotAll(app.db);
      await failOn('BEFORE DELETE', 'arc_freezes');
      await expectLater(
        pauseServiceOf(app).cancelPause(sessionId: arc.id),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await snapshotAll(app.db), before);
    });

    test('a change that would break an arc invariant is rolled back', () async {
      final seasonal = await joinSeason(app, DateTime(2027, 10, 5));
      final before = await snapshotAll(app.db);
      await expectLater(
        app.sessions.changeFreezes(
          seasonal.id,
          (s, _) => ScheduleFreeze(
            ArcFreeze(
              frozenFrom: LocalDate(2027, 10, 6),
              requestedAt: DateTime(2027, 10, 5, 9),
            ),
          ),
        ),
        throwsRule(DomainRule.invalidArc),
      );
      expect(await snapshotAll(app.db), before);

      final arc = await app.sessions.currentSession();
      expect(arc!.id, seasonal.id);
    });

    test('a resume with a wrong end date is rolled back', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(3));
      at(app, d(9));
      final before = await snapshotAll(app.db);
      await expectLater(
        app.sessions.changeFreezes(
          arc.id,
          (s, _) => CloseFreeze(
            frozenFrom: d(4),
            resumedOn: d(9),
            resumedAt: DateTime(2027, 3, 9, 9),
            endDate: s.endDate.addDays(6), // one too many
          ),
        ),
        throwsRule(DomainRule.invalidArc),
      );
      expect(await snapshotAll(app.db), before);
    });
  });

  group('reminders (F9, Z8)', () {
    Future<void> remindersOn() => app.reminders.update(
      (p) => p.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
        hydrationEnabled: true,
      ),
    );

    LocalDate dateOf(PlannedReminder r) => LocalDate.fromDateTime(r.at);

    test('nothing pending for a paused date after Freeze; re-planned after '
        'Cancel and after Resume, with the continuing day numbers', () async {
      final arc = await startRolling(app, day1);
      at(app, d(10), hour: 6);
      await remindersOn();
      final planned = app.scheduler.pending;
      expect(planned.map(dateOf).toSet(), hasLength(14));

      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(11));
      await app.reminders.reconcile();
      expect(app.scheduler.pending, isNotEmpty, reason: 'today still counts');
      expect(app.scheduler.pending.map(dateOf).toSet(), {
        d(10),
      }, reason: 'Z8: none on or after the first paused date');

      await pauseServiceOf(app).cancelPause(sessionId: arc.id);
      await app.reminders.reconcile();
      expect(app.scheduler.pending.map(dateOf).toSet(), hasLength(14));

      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(11));
      app.clock.current = DateTime(2027, 3, 15, 6);
      await app.reminders.reconcile();
      expect(app.scheduler.pending, isEmpty, reason: 'paused today');

      final r = LocalDate(2027, 3, 15);
      await pauseServiceOf(app).resume(sessionId: arc.id, on: r);
      await app.reminders.reconcile();
      final pending = app.scheduler.pending;
      expect(pending.length, lessThanOrEqualTo(ReminderPlanner.maxPending));
      expect(pending.map(dateOf).every((date) => !date.isBefore(r)), isTrue);
      final daily = pending.where((p) => p.kind == ReminderKind.daily).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      expect(daily.first.title, 'Winter Arc · Day 11');
      expect(daily, hasLength(14));
      expect(
        pending.where((p) => p.kind == ReminderKind.hydration),
        isNotEmpty,
        reason: 'Hydration Coach follows',
      );
    });

    test('a pause scheduled on Day 91 leaves nothing for Day 92 until '
        'Resume', () async {
      final arc = await startRolling(app, day1);
      at(app, d(91), hour: 6);
      await remindersOn();
      await pauseOn(arc.id, d(91));
      app.clock.current = DateTime(2027, 5, 30, 6);
      await app.reminders.reconcile();
      expect(app.scheduler.pending.map(dateOf).toSet(), {d(91)});
    });
  });

  group('process restart (a file database closed and reopened)', () {
    test('after scheduling and while paused, the state follows from the '
        'stored dates', () async {
      final dir = await Directory.systemTemp.createTemp('nextrep_pause');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/nextrep.sqlite');
      final clock = FakeClock(DateTime(2027, 3, 10, 21));
      AppDatabase open() => AppDatabase(NativeDatabase(file));

      var db = open();
      var run = TestApp(db, clock);
      final arc = await startRolling(run, day1);
      at(run, d(10), hour: 21);
      await completeHabit(run, 'water');
      await pauseServiceOf(run).pause(sessionId: arc.id, frozenFrom: d(11));
      await db.close();

      // Killed before midnight, relaunched after it.
      clock.current = DateTime(2027, 3, 11, 8);
      db = open();
      run = TestApp(db, clock);
      await run.lifecycle.reconcile();
      final paused = await run.tracking.today();
      expect(paused.position, isA<ArcPaused>());
      await db.close();

      // Rebooted a few days later, then resumed.
      clock.current = DateTime(2027, 3, 14, 8);
      db = open();
      run = TestApp(db, clock);
      await pauseServiceOf(run)
          .resume(sessionId: arc.id, on: LocalDate(2027, 3, 14));
      await db.close();

      db = open();
      run = TestApp(db, clock);
      final today = await run.tracking.today();
      expect((today.position as ArcInProgress).dayNumber, 11);
      expect((await run.sessions.sessionById(arc.id))!.endDate, d(95));
      await db.close();
    });
  });

  group('backup format 4 carries scheduled, open and closed pauses', () {
    // Every arc row (XP without its internal row id, as a backup carries
    // it), and the freeze and session rows exactly.
    Future<Map<String, Object?>> arcTables(AppDatabase db) async {
      final all = await snapshotAll(db);
      return {
        ...await dumpOf(db)
          ..remove('reminders'),
        'arc_freezes': all['arc_freezes'],
        'winter_arc_sessions': all['winter_arc_sessions'],
      };
    }

    Future<TestApp> restoredCopy() async {
      final export = await app.backup.export();
      final fresh = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
      addTearDown(fresh.db.close);
      await fresh.backup.restore(await fresh.backup.inspect(export.bytes));
      expect(await arcTables(fresh.db), await arcTables(app.db));
      return fresh;
    }

    test('scheduled: restored scheduled; cancel works there', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(10));
      await pauseOn(arc.id, d(10));
      final copy = await restoredCopy();
      final restored = (await copy.sessions.sessionById(arc.id))!;
      expect(restored.scheduledPauseOn(d(10))!.frozenFrom, d(11));
      await pauseServiceOf(copy).cancelPause(sessionId: arc.id);
      expect((await copy.sessions.sessionById(arc.id))!.freezes, isEmpty);
    });

    test('F1-5: open, with a revision on a paused date and closed pauses '
        'before it; the restored arc is paused and its revision applies on '
        'resume', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(2));
      await pauseOn(arc.id, d(2));
      await resumeOn(arc.id, d(5));
      await liveDay(app, d(5));
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 14, minimumTarget: 4),
        date: d(5),
      );
      await pauseOn(arc.id, d(5));
      at(app, d(9));
      final copy = await restoredCopy();
      final today = await copy.tracking.today();
      expect(today.position, isA<ArcPaused>());
      final r = d(12);
      at(copy, r);
      final resumed = await pauseServiceOf(copy)
          .resume(sessionId: arc.id, on: r);
      expect(resumed.dayNumberOf(r), 4);
      final after = await copy.tracking.today();
      expect(after.entries.firstWhere((e) => e.habit.id == 'water').target, 14);

      // And the source's own round trip after resuming.
      at(app, r);
      await resumeOn(arc.id, r);
      await restoredCopy();
    });
  });

  group('Weekly Review and Calendar while paused (spec § 12.3, R10, R11)', () {
    test('the paused week, the resumed week, a complete week before the '
        'pause unchanged', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(10));
      final weekOneBefore = WeeklyReview.fromHistory(
        await app.tracking.history(),
        1,
      );
      await pauseOn(arc.id, d(10));

      at(app, d(14)); // paused since d(11)
      var history = await app.tracking.history();
      var weeks = ArcWeeks.of(history.session, history.today);
      expect(weeks.week(2).status, ArcWeekStatus.paused);
      final paused = WeeklyReview.fromHistory(history, 2, weeks: weeks);
      expect(paused.today, isNull, reason: 'no Today so far while paused');
      expect(paused.countedDays, 3); // Days 8–10
      final week1 = WeeklyReview.fromHistory(history, 1, weeks: weeks);
      expect(week1.fullDays, weekOneBefore.fullDays);
      expect(week1.xpEarned, weekOneBefore.xpEarned);
      expect(week1.countedDays, weekOneBefore.countedDays);
      final calendar = ArcCalendar.of(await app.tracking.journey());
      expect(calendar.pauses.single.scheduled, isFalse);
      expect(calendar.pauses.single.freeze.isOpen, isTrue);

      final r = d(17);
      await resumeOn(arc.id, r);
      history = await app.tracking.history();
      weeks = ArcWeeks.of(history.session, history.today);
      expect(weeks.week(2).status, ArcWeekStatus.inProgress);
      expect(weeks.week(2).pausedDaysWithin, 6);
      final resumedWeek1 = WeeklyReview.fromHistory(history, 1, weeks: weeks);
      expect(resumedWeek1.xpEarned, weekOneBefore.xpEarned, reason: 'R10');
      final journey = await app.tracking.journey();
      final cal = ArcCalendar.of(journey);
      expect(cal.pauses.single.afterDay, 10);
      expect(cal.pauses.single.freeze.resumedOn, r);
      expect(journey.days[10].date, r, reason: 'Day 11 on the resume date');
    });
  });

  group('an arc with no pause behaves exactly as before (Z9)', () {
    test('the same days with and without a pause that was cancelled give the '
        'same rows, Journey, reviews and summary', () async {
      Future<List<Object>> run(bool cancelOne) async {
        final local = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2027, 3, 1)),
        );
        addTearDown(local.db.close);
        final arc = await startRolling(local, day1);
        for (var n = 1; n <= 12; n++) {
          at(local, d(n));
          if (n.isOdd) await completeAll(local);
          if (n == 4) await local.tracking.activateMinimumDay(date: d(n));
          if (cancelOne && n == 6) {
            await pauseServiceOf(local)
                .pause(sessionId: arc.id, frozenFrom: d(7));
            await pauseServiceOf(local).cancelPause(sessionId: arc.id);
          }
        }
        await local.achievements.reconcile();
        final history = await local.tracking.history();
        return [
          await dumpOf(local.db),
          [for (final j in (await local.tracking.journey()).days) j.state],
          WeeklyReview.fromHistory(history, 2).fullDays,
          (await local.history.card(arc.id)).summary.consistencyPercent,
        ];
      }

      expect(await run(true), equals(await run(false)));
    });
  });

  group('previews', () {
    test(
      'the Pause preview names today, tomorrow and both day numbers',
      () async {
        final arc = await startRolling(app, day1);
        at(app, d(25));
        final p = await pauseServiceOf(app).pausePreview(arc.id);
        expect(p.today, d(25));
        expect(p.frozenFrom, d(26));
        expect(p.todayDayNumber, 25);
        expect(p.nextDayNumber, 26);
        expect(p.canPause, isTrue);
      },
    );

    test('the Resume preview is exactly what Resume stores', () async {
      final arc = await startRolling(app, day1);
      await pauseOn(arc.id, d(25));
      await resumeOn(arc.id, d(30));
      await pauseOn(arc.id, d(30));
      at(app, d(37));
      final p = await pauseServiceOf(app).resumePreview(arc.id);
      expect(p.canResume, isTrue);
      expect(p.dayNumber, 27);
      expect(p.pausedDays, 6);
      expect(p.totalPausedDays, 10);
      final resumed = await resumeOn(arc.id, d(37));
      expect(p.lastDay, resumed.endDate);
      expect(p.resumed!.endDate, resumed.endDate);
      expect(p.resumed!.freezes.last.resumedOn, resumed.freezes.last.resumedOn);
    });
  });
}
