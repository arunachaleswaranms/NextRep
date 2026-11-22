import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/arc_restart.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';

/// Phase 12F: Restart through the real service on a real in-memory Drift
/// database with an injected clock (ARC_CONTROL_SPEC § 6, § 10 T1–T11;
/// addendum AD10–AD13, AD19, § L4 and § L7 F2-1 … F2-14). Every write goes
/// through the app's own write paths; "nothing else changed" is checked on
/// full table snapshots. All data is synthetic.

final day1 = LocalDate(2026, 10, 7); // the spec's worked example (§ 6.7)
LocalDate d(int n) => day1.addDays(n - 1);

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(
      memoryDatabase(),
      FakeClock(DateTime(2026, 10, 7, 9)),
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

  Future<HabitHistory> habitsOf(int id) => app.habits.historyForSession(id);

  /// Restarts [id] now and checks T2/T3/F2-12 on full snapshots.
  Future<RestartOutcome> restartChecked(
    int id, {
    required LocalDate closedOn,
    LocalDate? removedFreeze,
  }) async {
    final before = await snapshotAll(app.db);
    final oldHabits = (await habitsOf(id)).habits.length;
    final outcome = await restartNow(app, id);
    expectOnlyRestart(
      before,
      await snapshotAll(app.db),
      oldId: id,
      newId: outcome.started.id,
      closedOn: closedOn,
      removedFreeze: removedFreeze,
      newHabits: oldHabits,
    );
    expect(outcome.ended.status, WinterArcStatus.ended);
    expect(outcome.ended.closedOn, closedOn);
    final today = app.clock.today();
    expect(outcome.started.startDate, today, reason: 'Day 1 is today');
    expect(outcome.started.endDate, today.addDays(91), reason: 'Day 92');
    expect(outcome.started.participationStartDate, today);
    expect(outcome.started.kind, ArcKind.rolling92);
    expect(outcome.started.freezes, isEmpty);
    expect((await app.sessions.currentSession())!.id, outcome.started.id);
    return outcome;
  }

  group('the last lived day (§ 6.2, AD11, T9)', () {
    test('§ 6.7 row 1 / F2-2: logged today and a goal edited today: '
        'closed today; the waiting revision stays, unapplied', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(9));
      at(app, d(10));
      await completeHabit(app, 'water');
      await completeHabit(app, 'workout');
      await app.tracking.editHabit(
        habitId: 'learning',
        edit: const HabitEdit(target: 45, minimumTarget: 15),
        date: d(10),
      );
      final revisionsBefore = (await snapshotAll(app.db))['habit_revisions'];

      final outcome = await restartChecked(arc.id, closedOn: d(10));

      final ended = outcome.ended;
      expect(ended.dayNumberOf(ended.closedOn!), 10);
      expect(
        (await snapshotAll(app.db))['habit_revisions'],
        revisionsBefore,
        reason: 'the 17 Oct revision is stored unchanged in the old arc',
      );
      final history = await app.tracking.historyFor(arc.id);
      expect(history.elapsedDates.last, d(10));
      expect(history.elapsedDates, hasLength(10));
      final learning = history.records.habits.habit('learning')!;
      expect(
        history.records.habits.configOn(learning, d(10)).target,
        isNot(45),
        reason: 'the edit never changed a lived day',
      );
      // The new arc starts with the edited goal.
      final fresh = await habitsOf(outcome.started.id);
      expect(fresh.habit('learning')!.target, 45);
      expect(fresh.habit('learning')!.minimumTarget, 15);
      expect(fresh.revisions, isEmpty, reason: 'no revision is copied');
    });

    test('§ 6.7 row 2 / F2-1: nothing logged today, goal edited: closed '
        'yesterday; today and tomorrow are not lived', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(9));
      at(app, d(10));
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 12, minimumTarget: 4),
        date: d(10),
      );
      final outcome = await restartChecked(arc.id, closedOn: d(9));
      expect(outcome.ended.dayNumberOf(d(9)), 9);
      final history = await app.tracking.historyFor(arc.id);
      expect(history.elapsedDates, hasLength(9));
      expect(history.elapsedDates.contains(d(10)), isFalse);
      expect(history.elapsedDates.contains(d(11)), isFalse);
      expect((await habitsOf(outcome.started.id)).habit('water')!.target, 12);
    });

    test('§ 6.7 row 5 / F2-10: Day 1 with nothing logged: closed on the '
        'participation start, one counted day', () async {
      final arc = await startRolling(app, day1);
      final outcome = await restartChecked(arc.id, closedOn: d(1));
      expect(outcome.ended.participationLengthInDays, 1);
      expect(outcome.ended.participatingDatesThrough(d(30)), [
        d(1),
      ], reason: 'one counted day');
      final history = await app.tracking.historyFor(arc.id);
      expect(history.elapsedDates, [d(1)]);
    });

    test('Day 1 with activity: closed on Day 1', () async {
      final arc = await startRolling(app, day1);
      await completeHabit(app, 'water');
      await restartChecked(arc.id, closedOn: d(1));
    });

    test('a reflection alone is activity; a revision alone is not', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(1));
      at(app, d(2));
      await app.reflections.save(
        sessionId: arc.id,
        date: d(2),
        draft: const ReflectionDraft(mood: Mood.good, win: 'Today counts'),
      );
      expect(
        (await restartServiceOf(app).preview(arc.id)).closedOn,
        d(2),
        reason: 'a reflection is activity',
      );
    });

    test('a Minimum Day alone is activity', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(1));
      at(app, d(2));
      await app.tracking.activateMinimumDay(date: d(2));
      await restartChecked(arc.id, closedOn: d(2));
    });

    test('§ 6.7 row 4 / F2-7: paused since 20 Oct, restarted 25 Oct: '
        'closed 19 Oct (Day 13), the unresumed pause removed', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(13));
      await pauseOn(arc.id, LocalDate(2026, 10, 19));
      at(app, LocalDate(2026, 10, 25));
      final outcome = await restartChecked(
        arc.id,
        closedOn: LocalDate(2026, 10, 19),
        removedFreeze: LocalDate(2026, 10, 20),
      );
      expect(outcome.ended.dayNumberOf(LocalDate(2026, 10, 19)), 13);
      expect(outcome.ended.freezes, isEmpty);
      expect(
        outcome.ended.isParticipatingOn(LocalDate(2026, 10, 20)),
        isFalse,
        reason: 'after closedOn: not reached',
      );
    });

    test('F2-7: paused on its first paused date', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(5));
      await pauseOn(arc.id, d(5));
      at(app, d(6));
      await restartChecked(arc.id, closedOn: d(5), removedFreeze: d(6));
    });

    test('F2-7 after earlier closed pauses: closed pauses are kept, the '
        'open one removed, never a paused date', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(3));
      await pauseOn(arc.id, d(3)); // paused d(4)…
      await resumeOn(arc.id, d(8)); // resumed: d(8) is Day 4
      await liveDay(app, d(8));
      await pauseOn(arc.id, d(8)); // open from d(9)
      at(app, d(15));
      final before = (await stored(app, arc.id)).freezes;
      final outcome = await restartChecked(
        arc.id,
        closedOn: d(8),
        removedFreeze: d(9),
      );
      expect(outcome.ended.freezes, [before.first]);
      expect(outcome.ended.dayNumberOf(d(8)), 4);
      expect(outcome.ended.isFrozenOn(outcome.ended.closedOn!), isFalse);
      expect(outcome.ended.endDate, before.isEmpty ? null : d(92).addDays(4));
    });

    test('F2-6: a freeze scheduled for tomorrow is removed; closed today '
        'with activity, yesterday without', () async {
      for (final logged in [true, false]) {
        final local = TestApp(memoryDatabase(), FakeClock(DateTime(2026)));
        addTearDown(local.db.close);
        final arc = await startRolling(local, day1);
        await liveDays(local, d(1), d(4));
        at(local, d(5));
        if (logged) await completeHabit(local, 'water');
        await pauseServiceOf(local).pause(sessionId: arc.id, frozenFrom: d(6));
        final before = await snapshotAll(local.db);
        final outcome = await restartNow(local, arc.id);
        expectOnlyRestart(
          before,
          await snapshotAll(local.db),
          oldId: arc.id,
          newId: outcome.started.id,
          closedOn: logged ? d(5) : d(4),
          removedFreeze: d(6),
          newHabits: 7,
        );
      }
    });

    test('F2-8: Day 91 and Day 92: ended (never completed), no Summit, '
        'closed on or before the planned last date', () async {
      for (final (day, logged) in [(91, true), (92, true), (92, false)]) {
        final local = TestApp(memoryDatabase(), FakeClock(DateTime(2026)));
        addTearDown(local.db.close);
        final arc = await startRolling(local, day1);
        await liveDays(local, d(1), d(day - 1));
        at(local, d(day));
        if (logged) await completeAll(local);
        final preview = await restartServiceOf(local).preview(arc.id);
        expect(preview.isLastDay, day == 92);
        final outcome = await restartNow(local, arc.id);
        final closed = logged ? d(day) : d(day - 1);
        expect(outcome.ended.closedOn, closed);
        expect(outcome.ended.closedOn!.isAfter(d(92)), isFalse);
        expect(outcome.ended.status, WinterArcStatus.ended);
        // The next days: never completed, never a Summit.
        for (final later in [d(93), d(94), d(200)]) {
          at(local, later);
          await local.lifecycle.reconcile();
          await local.achievements.sync();
          await local.achievements.backfillCatalog();
          final stored = (await local.sessions.sessionById(arc.id))!;
          expect(stored.status, WinterArcStatus.ended);
          final unlocks = await local.achievementStore.unlocks(arc.id);
          expect(
            unlocks.map((u) => u.key),
            isNot(contains(AchievementKey.summit)),
          );
        }
      }
    });

    test('F2-9: an active Seasonal Arc and a late join become Rolling arcs '
        'on Day 1; the season keeps its dates', () async {
      for (final join in [DateTime(2026, 10, 1), DateTime(2026, 10, 15)]) {
        final local = TestApp(memoryDatabase(), FakeClock(DateTime(2026)));
        addTearDown(local.db.close);
        final arc = await joinSeason(local, join);
        final joined = LocalDate.fromDateTime(join);
        await liveDays(local, joined, LocalDate(2026, 11, 13));
        at(local, LocalDate(2026, 11, 14)); // Day 45 of the season
        final before = await snapshotAll(local.db);
        final outcome = await restartNow(local, arc.id);
        expectOnlyRestart(
          before,
          await snapshotAll(local.db),
          oldId: arc.id,
          newId: outcome.started.id,
          closedOn: LocalDate(2026, 11, 13),
          newHabits: 7,
        );
        final ended = outcome.ended;
        expect(ended.kind, ArcKind.seasonalWinter);
        expect(ended.startDate, LocalDate(2026, 10, 1));
        expect(ended.endDate, LocalDate(2026, 12, 31));
        expect(ended.participationStartDate, joined);
        expect(ended.dayNumberOf(ended.closedOn!), 44, reason: 'season day');
        expect(outcome.started.kind, ArcKind.rolling92);
        expect(outcome.started.startDate, LocalDate(2026, 11, 14));
        expect(outcome.started.endDate, LocalDate(2027, 2, 13));
      }
    });

    test('F2-9: a seasonal late join restarted on its join day with '
        'nothing logged closes on the join day', () async {
      final arc = await joinSeason(app, DateTime(2026, 10, 20));
      final outcome = await restartChecked(
        arc.id,
        closedOn: LocalDate(2026, 10, 20),
      );
      expect(outcome.ended.dayNumberOf(outcome.ended.closedOn!), 20);
    });
  });

  group('the new arc (§ 6.3, T3, AD11)', () {
    test('same habits, goals, on/off and order; custom habits; '
        'nothing else', () async {
      at(app, day1);
      await app.winterArc.beginSetup();
      await app.winterArc.addTemplateHabit('journal');
      final custom = await app.winterArc.addCustomHabit(
        const HabitDraft(
          title: 'Stretch',
          type: HabitType.duration,
          target: 20,
          minimumTarget: 5,
          unit: 'min',
          iconKey: 'meditation',
        ),
      );
      await app.winterArc.setHabitEnabled('english', enabled: false);
      final setupIds = (await app.winterArc.setupHabits())
          .map((h) => h.id)
          .toList();
      await app.winterArc.reorderSetupHabits(setupIds.reversed.toList());
      final arc = await app.winterArc.startWinterArc();
      await liveDays(app, d(1), d(3));
      at(app, d(4));
      await app.tracking.activateMinimumDay(date: d(4));
      await app.tracking.editHabit(
        habitId: custom.id,
        edit: const HabitEdit(target: 30, minimumTarget: 10),
        date: d(4),
      );
      await app.tracking.editHabit(
        habitId: 'journal',
        edit: const HabitEdit(title: 'Breathe', enabled: false),
        date: d(4),
      );
      final old = await habitsOf(arc.id);
      final outcome = await restartChecked(arc.id, closedOn: d(4));
      final fresh = await habitsOf(outcome.started.id);

      expect(
        fresh.habits.map((h) => h.id),
        old.habits.map((h) => h.id),
        reason: 'same ids, same display order',
      );
      for (final h in fresh.habits) {
        final o = old.habit(h.id)!;
        final latest = old.latestConfig(o);
        expect(h.title, o.title, reason: h.id);
        expect(h.type, o.type, reason: h.id);
        expect(h.unit, o.unit, reason: h.id);
        expect(h.iconKey, o.iconKey, reason: h.id);
        expect(h.sortOrder, o.sortOrder, reason: h.id);
        expect(h.baseline, latest, reason: '${h.id}: latest configuration');
        expect(h.createdAt, app.clock.now());
      }
      expect(fresh.habit(custom.id)!.target, 30);
      expect(fresh.habit(custom.id)!.id, startsWith('custom_'));
      expect(fresh.habit('journal')!.title, 'Breathe');
      expect(fresh.habit('journal')!.enabled, isFalse);
      expect(fresh.habit('english')!.enabled, isFalse, reason: 'off stays off');
      expect(fresh.revisions, isEmpty);

      // Fresh Day 1: no progress, mode, XP, unlock or reflection; level 1.
      final today = await app.tracking.today();
      expect(today.session.id, outcome.started.id);
      expect((today.position as ArcInProgress).dayNumber, 1);
      expect(today.completion.completed, 0);
      expect(today.mode.isMinimum, isFalse);
      final records = await app.progress.loadArc(outcome.started.id);
      expect(records.totalXp, 0);
      expect(await app.achievementStore.unlocks(outcome.started.id), isEmpty);
      final summary = ArcSummary.fromHistory(
        await app.tracking.historyFor(outcome.started.id),
        achievementsUnlocked: 0,
        achievementsTotal: 0,
      );
      expect(summary.level.level, 1);
      expect(summary.totalXp, 0);
    });

    test('F2-3: several revisions over the arc: the latest of each habit, '
        'pending included; the old revision rows are identical', () async {
      final arc = await startRolling(app, day1);
      for (final (day, target) in [(2, 9), (5, 10), (9, 11)]) {
        await liveDay(app, d(day));
        await app.tracking.editHabit(
          habitId: 'water',
          edit: HabitEdit(target: target, minimumTarget: 3),
          date: d(day),
        );
      }
      at(app, d(12));
      await completeHabit(app, 'workout');
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 13, minimumTarget: 5),
        date: d(12),
      );
      await app.tracking.editHabit(
        habitId: 'learning',
        edit: const HabitEdit(enabled: false),
        date: d(12),
      );
      final outcome = await restartChecked(arc.id, closedOn: d(12));
      final fresh = await habitsOf(outcome.started.id);
      expect(fresh.habit('water')!.target, 13);
      expect(fresh.habit('water')!.minimumTarget, 5);
      expect(fresh.habit('learning')!.enabled, isFalse);
      final old = await habitsOf(arc.id);
      expect(old.revisions, hasLength(5), reason: 'still in the old arc');
    });

    test('the new arc is tracked normally and earns its own XP and '
        'achievements, from zero', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(8));
      final xpOld = await xpRows(app.db);
      final unlocksOld = await app.achievementStore.unlocks(arc.id);
      expect(unlocksOld, isNotEmpty);
      at(app, d(9));
      final outcome = await restartChecked(arc.id, closedOn: d(8));
      // Achievement reconciliation right after the restart awards nothing.
      await app.achievements.sync();
      await app.achievements.backfillCatalog();
      expect(await app.achievementStore.unlocks(outcome.started.id), isEmpty);
      expect(
        _keys(await app.achievementStore.unlocks(arc.id)),
        _keys(unlocksOld),
      );
      expect(await xpRows(app.db), xpOld, reason: 'no XP for restarting');
      // Day 1 of the new arc.
      await liveDay(app, d(9));
      final newXp = (await xpRows(app.db))
          .where((x) => x.sessionId == outcome.started.id)
          .toList();
      expect(newXp, isNotEmpty);
      expect(
        (await xpRows(app.db)).where((x) => x.sessionId == arc.id).toList(),
        xpOld,
        reason: 'the old ledger is identical, row for row',
      );
      final fresh = await app.achievementStore.unlocks(outcome.started.id);
      expect(
        fresh.map((u) => u.key),
        contains(AchievementKey.firstRep),
        reason: 'earned again by the new arc, by the existing rules',
      );
    });

    test('the new arc can be paused, resumed and completed', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(2));
      at(app, d(3));
      final outcome = await restartChecked(arc.id, closedOn: d(2));
      final s = outcome.started;
      await liveDay(app, d(3));
      await pauseOn(s.id, d(3));
      await resumeOn(s.id, d(6));
      at(app, d(3).addDays(91 + 3 + 1));
      await app.lifecycle.reconcile();
      expect((await stored(app, s.id)).status, WinterArcStatus.completed);
      expect((await stored(app, arc.id)).status, WinterArcStatus.ended);
    });
  });

  group('refusals write nothing (T1, T5, T10, F2-4, F2-13, F2-14)', () {
    Future<void> expectRefused(
      Future<Object?> Function() action,
      DomainRule rule,
    ) async {
      final before = await snapshotAll(app.db);
      await expectLater(action(), throwsRule(rule));
      expect(await snapshotAll(app.db), before, reason: 'nothing written');
    }

    test('F2-4 / F2-5: activity dated 18 Oct, clock at 17 Oct: refused, '
        'naming 18 Oct; back at 18 Oct it works', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), LocalDate(2026, 10, 18));
      at(app, LocalDate(2026, 10, 17));
      final preview = await restartServiceOf(app).preview(arc.id);
      expect(preview.canRestart, isFalse);
      final behind = preview.guard as ClockGuardBehind;
      expect(behind.earliestSafe, LocalDate(2026, 10, 18));
      expect(behind.bound, ClockGuardBound.lastActivity);
      expect(preview.closedOn, isNull);
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: LocalDate(2026, 10, 16)),
        DomainRule.clockBehindHistory,
      );
      at(app, LocalDate(2026, 10, 18));
      final outcome = await restartChecked(
        arc.id,
        closedOn: LocalDate(2026, 10, 18),
      );
      final last = (await xpRows(app.db))
          .where((x) => x.sessionId == arc.id)
          .map((x) => x.date)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(last.isAfter(outcome.ended.closedOn!), isFalse);
    });

    test('T10: the clock behind the last resume, or the first day', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(1));
      await pauseOn(arc.id, d(1));
      await resumeOn(arc.id, d(5)); // nothing logged since
      at(app, d(4));
      final preview = await restartServiceOf(app).preview(arc.id);
      expect(
        (preview.guard as ClockGuardBehind).bound,
        ClockGuardBound.lastResume,
      );
      await expectRefused(
        () => restartAs(app, arc.id),
        DomainRule.clockBehindHistory,
      );

      final other = TestApp(memoryDatabase(), FakeClock(DateTime(2026)));
      addTearDown(other.db.close);
      final second = await startRolling(other, day1);
      at(other, day1.addDays(-1));
      final before = await snapshotAll(other.db);
      await expectLater(
        restartAs(other, second.id),
        throwsRule(DomainRule.clockBehindHistory),
      );
      expect(await snapshotAll(other.db), before);
    });

    test('T1: a date or last day not shown is refused', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(3));
      at(app, d(4));
      await expectRefused(
        () => restartAs(app, arc.id, shownOn: d(3), shownClosedOn: d(3)),
        DomainRule.restartDateChanged,
      );
      // The screen said Day 3 ends it, but a habit was logged since.
      final preview = await restartServiceOf(app).preview(arc.id);
      expect(preview.closedOn, d(3));
      await completeHabit(app, 'water');
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: preview.closedOn),
        DomainRule.restartDateChanged,
      );
    });

    test('F2-14: a completed arc is never restarted or changed', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(3));
      at(app, d(93));
      // Over but not yet closed out: refused, and not ended early.
      expect(
        (await restartServiceOf(app).preview(arc.id)).blocker,
        RestartBlocker.over,
      );
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: d(3)),
        DomainRule.arcCompleted,
      );
      await app.lifecycle.reconcile();
      expect((await stored(app, arc.id)).status, WinterArcStatus.completed);
      expect(
        (await restartServiceOf(app).preview(arc.id)).blocker,
        RestartBlocker.notActive,
      );
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: d(3)),
        DomainRule.arcCompleted,
      );
    });

    test('a setup, an ended arc, an unknown arc and a stale id are '
        'refused', () async {
      final setup = await app.winterArc.beginSetup();
      await expectRefused(
        () => restartAs(app, setup.id),
        DomainRule.restartUnavailable,
      );
      await expectRefused(() => restartAs(app, 99), DomainRule.sessionNotFound);
      final arc = await app.winterArc.startWinterArc();
      await liveDay(app, d(1));
      at(app, d(2));
      final outcome = await restartNow(app, arc.id);
      // The old arc again (a second tap, a stale screen): refused.
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: d(1)),
        DomainRule.restartUnavailable,
      );
      expect((await app.sessions.listSessions()), hasLength(2));
      expect((await app.sessions.currentSession())!.id, outcome.started.id);
    });

    test('two concurrent restarts start one arc', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(1));
      at(app, d(2));
      final preview = await restartServiceOf(app).preview(arc.id);
      final service = restartServiceOf(app);
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          service
              .restart(
                sessionId: arc.id,
                shownOn: preview.today,
                shownClosedOn: preview.closedOn!,
              )
              .then<Object>((o) => o, onError: (Object e) => e),
      ]);
      expect(results.whereType<RestartOutcome>(), hasLength(1));
      expect(
        results.whereType<DomainFailure>().single.rule,
        DomainRule.restartUnavailable,
      );
      expect(await app.sessions.listSessions(), hasLength(2));
    });

    test('every habit off at its latest configuration: refused '
        '(the start rule)', () async {
      final arc = await startRolling(app, day1);
      await liveDay(app, d(1));
      // Not possible through the app (the last habit can't be switched
      // off); stored directly as synthetic damaged data.
      for (final h in (await habitsOf(arc.id)).habits) {
        await app.db
            .into(app.db.habitRevisions)
            .insert(
              HabitRevisionsCompanion.insert(
                sessionId: arc.id,
                habitId: h.id,
                effectiveFrom: d(2),
                target: h.target,
                minimumTarget: h.minimumTarget,
                enabled: false,
                createdAt: DateTime(2026, 10, 7, 10),
              ),
            );
      }
      at(app, d(2));
      expect(
        (await restartServiceOf(app).preview(arc.id)).blocker,
        RestartBlocker.noHabitsOn,
      );
      await expectRefused(
        () => restartAs(app, arc.id, shownClosedOn: d(1)),
        DomainRule.noHabitsSelected,
      );
    });
  });

  group('F2-13 / T5: a storage error at each write rolls everything back', () {
    Future<void> failOn(String when, String table, {String where = ''}) =>
        app.db.customStatement(
          'CREATE TEMP TRIGGER injected_failure $when ON $table '
          '${where.isEmpty ? '' : 'WHEN $where '}'
          "BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
    Future<void> heal() =>
        app.db.customStatement('DROP TRIGGER injected_failure');

    Future<WinterArcSession> pausedArc() async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(5));
      at(app, d(6));
      await completeHabit(app, 'water');
      await app.reflections.save(
        sessionId: arc.id,
        date: d(6),
        draft: const ReflectionDraft(mood: Mood.okay, win: 'Kept'),
      );
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 11, minimumTarget: 3),
        date: d(6),
      );
      await pauseOn(arc.id, d(6)); // scheduled for d(7)
      return arc;
    }

    for (final (name, timing, table, where) in [
      ('deleting the open freeze', 'BEFORE DELETE', 'arc_freezes', ''),
      ('ending the old arc', 'BEFORE UPDATE', 'winter_arc_sessions', ''),
      ('inserting the new arc', 'BEFORE INSERT', 'winter_arc_sessions', ''),
      ('inserting the first habit', 'BEFORE INSERT', 'habits', ''),
      (
        'inserting the last habit',
        'BEFORE INSERT',
        'habits',
        "NEW.id = 'meditation'",
      ),
    ]) {
      test(name, () async {
        final arc = await pausedArc();
        final before = await snapshotAll(app.db);
        final preview = await restartServiceOf(app).preview(arc.id);
        await failOn(timing, table, where: where);
        await expectLater(
          restartServiceOf(app).restart(
            sessionId: arc.id,
            shownOn: preview.today,
            shownClosedOn: preview.closedOn!,
          ),
          throwsA(anything),
        );
        expect(await snapshotAll(app.db), before, reason: 'rolled back');
        expect((await app.sessions.currentSession())!.id, arc.id);
        expect(
          await app.sessions.listSessions(),
          hasLength(1),
          reason: 'one unfinished arc, as before',
        );
        // Retry after the failure: it works, exactly once.
        await heal();
        final outcome = await restartServiceOf(app).restart(
          sessionId: arc.id,
          shownOn: preview.today,
          shownClosedOn: preview.closedOn!,
        );
        expectOnlyRestart(
          before,
          await snapshotAll(app.db),
          oldId: arc.id,
          newId: outcome.started.id,
          closedOn: d(6),
          removedFreeze: d(7),
          newHabits: 7,
        );
      });
    }

    test('a stored result that differs from the plan is rolled back', () async {
      final arc = await pausedArc();
      final before = await snapshotAll(app.db);
      // Something rewrites the new habit behind the transaction's back.
      await app.db.customStatement(
        'CREATE TEMP TRIGGER injected_failure AFTER INSERT ON habits '
        "BEGIN UPDATE habits SET title = 'X' WHERE rowid = NEW.rowid; END",
      );
      await expectLater(
        restartNow(app, arc.id),
        throwsRule(DomainRule.invalidArc),
      );
      expect(await snapshotAll(app.db), before);
      await heal();
      await app.db.customStatement(
        'CREATE TEMP TRIGGER injected_failure AFTER UPDATE ON '
        'winter_arc_sessions BEGIN UPDATE winter_arc_sessions SET '
        "closed_on = '2026-10-08' WHERE id = NEW.id AND "
        "NEW.status = 'ended'; END",
      );
      await expectLater(
        restartNow(app, arc.id),
        throwsRule(DomainRule.invalidArc),
      );
      expect(await snapshotAll(app.db), before);
    });
  });

  group('history after a restart (§ 6.5, T4)', () {
    test('Journey: ended, read-only, no Summit; days after closedOn not '
        'reached; streaks miss an unachieved closedOn', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(91));
      at(app, d(92));
      await completeHabit(app, 'water'); // a partial last day
      await restartChecked(arc.id, closedOn: d(92));
      for (final t in [d(92), d(93), d(120)]) {
        at(app, t);
        final h = await app.tracking.historyFor(arc.id);
        final journey = h.journey();
        expect(journey, hasLength(92));
        expect(journey.any((day) => day.isToday), isFalse);
        expect(journey.last.state, isNot(JourneyDayState.today));
        expect(h.isTodayOpen, isFalse);
      }
    });

    test('an ended arc is no target for tracking, reflections or edits; '
        'every write lands on the new arc or is refused', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(4));
      at(app, d(5));
      final outcome = await restartChecked(arc.id, closedOn: d(4));
      final before = (await snapshotAll(
        app.db,
      ))['xp_transactions']!.where((r) => r['session_id'] == arc.id).toList();
      await expectLater(
        app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(title: 'Old'),
          date: d(5),
          sessionId: arc.id,
        ),
        throwsRule(DomainRule.arcCompleted),
      );
      await expectLater(
        app.reflections.save(
          sessionId: arc.id,
          date: d(5),
          draft: const ReflectionDraft(mood: Mood.good, win: 'x'),
        ),
        throwsA(isA<DomainFailure>()),
      );
      await completeHabit(app, 'water');
      expect((await app.tracking.today()).session.id, outcome.started.id);
      expect(
        (await snapshotAll(
          app.db,
        ))['xp_transactions']!.where((r) => r['session_id'] == arc.id).toList(),
        before,
      );
    });

    test('identities and the XP split (§ 12.5) for both arcs on every date '
        'around the restart; other = 0; today = 0 for the ended arc', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(6));
      await pauseOn(arc.id, d(6));
      await resumeOn(arc.id, d(9)); // d(9) is Day 7
      await liveDay(app, d(9));
      at(app, d(10));
      await completeHabit(app, 'water');
      final outcome = await restartChecked(arc.id, closedOn: d(10));
      await liveDays(app, d(10), d(12));
      for (var t = d(-2); !t.isAfter(d(140)); t = t.addDays(1)) {
        at(app, t);
        for (final id in [arc.id, outcome.started.id]) {
          final h = await app.tracking.historyFor(id);
          _expectXpSplit(h);
        }
      }
    });

    test('Insights keep the ended arc\'s days and do not count it as '
        'completed', () async {
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(5));
      at(app, d(6));
      final outcome = await restartChecked(arc.id, closedOn: d(5));
      await liveDays(app, d(6), d(7));
      final insights = await app.insights.snapshot();
      expect(insights.overall.arcCount, 2);
      expect(insights.overall.completedArcs, 0);
      expect(insights.overall.activeArc?.id, outcome.started.id);
      expect(insights.overall.elapsedDays, 7);
    });

    test('reminders are planned for the new arc from Day 1', () async {
      await app.reminderStore.save(
        (await app.reminderStore.load()).copyWith(dailyEnabled: true),
        at: DateTime(2026, 10, 7, 8),
      );
      final arc = await startRolling(app, day1);
      await liveDays(app, d(1), d(20));
      at(app, d(21));
      await restartChecked(arc.id, closedOn: d(20));
      await app.reminders.reconcile();
      final daily = app.scheduler.pending
          .where((p) => p.kind == ReminderKind.daily)
          .toList();
      expect(daily, isNotEmpty);
      // Today's 08:00 reminder has passed; tomorrow is the new Day 2, and
      // nothing counts on from the old arc's Day 21.
      expect(daily.first.title, 'Winter Arc · Day 2');
      expect(daily.first.at, DateTime(2026, 10, 28, 8));
      expect(daily.map((r) => r.title), isNot(contains('Winter Arc · Day 22')));
    });
  });

  group('T11 / F2-11: backups after a restart round-trip row for row', () {
    Future<void> roundTrip() async {
      final export = await app.backup.export();
      final fresh = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
      addTearDown(fresh.db.close);
      await fresh.backup.restore(await fresh.backup.inspect(export.bytes));
      final a = await dumpOf(app.db)
        ..remove('reminders');
      final b = await dumpOf(fresh.db)
        ..remove('reminders');
      expect(b, a);
      final all = await snapshotAll(app.db);
      final copy = await snapshotAll(fresh.db);
      for (final table in ['winter_arc_sessions', 'arc_freezes', 'habits']) {
        expect(copy[table], all[table], reason: table);
      }
      for (final s in await fresh.sessions.listSessions()) {
        if (s.closedOn case final c?) {
          expect(c.isAfter(app.clock.today()), isFalse);
        }
      }
    }

    test(
      'F2-1, F2-2, F2-6, F2-7, F2-8, F2-10 and a seasonal restart',
      () async {
        // One database collects several restarts in a row.
        final arc = await startRolling(app, day1);
        await liveDays(app, d(1), d(2));
        at(app, d(3));
        await app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 12, minimumTarget: 4),
          date: d(3),
        );
        final a = await restartNow(app, arc.id); // F2-1
        await roundTrip();
        at(app, d(4));
        await completeAll(app);
        await app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 14, minimumTarget: 4),
          date: d(4),
        );
        await pauseOn(a.started.id, d(4)); // scheduled (F2-6)
        final b = await restartNow(app, a.started.id); // F2-2
        await roundTrip();
        await liveDay(app, d(5));
        await pauseOn(b.started.id, d(5));
        at(app, d(9)); // paused (F2-7)
        final c = await restartNow(app, b.started.id);
        await roundTrip();
        final e = await restartNow(app, c.started.id); // F2-10
        await roundTrip();
        await liveDays(app, d(9), d(9).addDays(90));
        at(app, d(9).addDays(91)); // Day 92 (F2-8)
        await completeAll(app);
        await restartNow(app, e.started.id);
        await roundTrip();
        at(app, d(9).addDays(92));
        await roundTrip();
        final sessions = await app.sessions.listSessions();
        expect(
          sessions.where((s) => s.status == WinterArcStatus.ended),
          hasLength(5),
        );
      },
    );
  });

  group('process death between restart and deletion (D4, § L4 I)', () {
    test('a file database reopened after the restart keeps the old arc; '
        'no deletion intent exists', () async {
      final dir = await Directory.systemTemp.createTemp('nextrep_12f_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      var local = TestApp(db, FakeClock(DateTime(2026, 10, 7, 9)));
      final arc = await startRolling(local, day1);
      await liveDays(local, d(1), d(3));
      at(local, d(4));
      final outcome = await restartNow(local, arc.id);
      final before = await snapshotAll(db);
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      local = TestApp(db, FakeClock(DateTime(2026, 10, 7, 9)));
      at(local, d(4));
      addTearDown(db.close);
      await local.lifecycle.reconcile();
      expect(await snapshotAll(db), before);
      expect((await stored(local, arc.id)).status, WinterArcStatus.ended);
      expect((await local.sessions.currentSession())!.id, outcome.started.id);
    });
  });
}

/// Unlocks as comparable (key, date) pairs.
List<(AchievementKey, LocalDate)> _keys(List<AchievementUnlock> unlocks) => [
  for (final u in unlocks) (u.key, u.unlockedOn),
];

/// Spec § 12.5.1's four XP groups and § 12.5.2's day partition on one
/// arc's history: exhaustive, exclusive, `other = 0`; an ended arc has no
/// open day and no "today" XP.
void _expectXpSplit(ArcHistory h) {
  final s = h.session;
  final t = h.today;
  final ended = s.status == WinterArcStatus.ended;
  var settled = 0, today = 0, future = 0, other = 0;
  for (final MapEntry(key: day, value: amount) in h.records.xpByDate.entries) {
    if (day.isAfter(t)) {
      future += amount;
    } else if (!s.isParticipatingOn(day)) {
      other += amount;
    } else if (day.isBefore(t) || ended) {
      settled += amount;
    } else {
      today += amount;
    }
  }
  final at = '${s.status.name} ${s.id} on $t';
  expect(settled + today + future + other, h.records.totalXp, reason: at);
  expect(other, 0, reason: at);
  if (ended) {
    expect(today, 0, reason: at);
    expect(h.isTodayOpen, isFalse, reason: at);
  }
  final summary = ArcSummary.fromHistory(
    h,
    achievementsUnlocked: 0,
    achievementsTotal: 0,
  );
  expect(summary.daysElapsed, h.elapsedDates.length, reason: at);
  for (final day in h.elapsedDates) {
    expect(s.isFrozenOn(day), isFalse, reason: at);
    if (s.closedOn case final c?) expect(day.isAfter(c), isFalse, reason: at);
  }
}
