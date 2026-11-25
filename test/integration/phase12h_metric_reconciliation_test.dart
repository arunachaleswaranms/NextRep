import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/reconciliation.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';

/// Phase 12H cross-screen metric reconciliation (brief § 5;
/// ARC_MOMENTUM_SPEC §§ 4.5, 12.5; addendum § L7 F3, F4).
///
/// 1. The spec's worked examples, reproduced **exactly** on a real Drift
///    database through the app's own services (the starter habits: five
///    switched on, so a Perfect Day is 5 × 15 + 30 = 105 XP and four habits
///    are 60 XP): § 12.5.1 A, B, D, E, F, G, G′ and H (a restored ended
///    Arc on a device whose date is behind), and § 12.5.2 A, D′, D, E, F,
///    G and I. Each is then checked against every screen's read model with
///    `expectArcReconciles` (Today, Journey, Calendar, all 13 Weekly
///    Reviews, Summary / Arc History, Insights, the raw ledger).
/// 2. Generated histories on real Drift: random logging, Minimum Days,
///    goal edits, pauses, resumes, clock rollbacks and restarts, with every
///    started Arc reconciled on every date visited.
///
/// Every reconciliation also asserts it wrote nothing. All data synthetic.

/// Starts a Rolling Arc on [day1] with five habits switched on (the four
/// starters on by default plus English), so a Perfect Day is
/// 5 × 15 + 30 = 105 XP and four habits 60 XP, as in the spec's examples.
Future<WinterArcSession> _startFive(TestApp app, LocalDate day1) async {
  at(app, day1);
  await app.winterArc.beginSetup();
  await app.winterArc.setHabitEnabled('english', enabled: true);
  final enabled = [
    for (final h in await app.winterArc.setupHabits())
      if (h.enabled) h.id,
  ];
  expect(enabled, hasLength(5), reason: 'five habits, as in the examples');
  return app.winterArc.startWinterArc();
}

/// Completes the first [n] habits shown on Today, in Today's order.
Future<void> _logFirst(TestApp app, int n) async {
  final today = await app.tracking.today();
  for (final entry in today.entries.take(n)) {
    await completeHabit(app, entry.habit.id);
  }
}

/// Lives [date] (19:00) logging [habits] habits (5 = a Perfect Day).
Future<void> _liveDate(TestApp app, LocalDate date, int habits) async {
  at(app, date, hour: 19);
  await app.lifecycle.reconcile();
  await _logFirst(app, habits);
  await app.achievements.reconcile();
}

void _expectXp(ArcFigures f, (int, int, int, int, int) groups, String why) =>
    expect(
      (f.settledXp, f.todayXp, f.futureXp, f.otherXp, f.ledgerXp),
      groups,
      reason: '$why: XP groups A, B, C, D and the total',
    );

void _expectDays(
  ArcFigures f,
  (int, int, int, int, int, int) days,
  String why,
) => expect(
  (
    f.settled,
    f.open,
    f.elapsed,
    f.fullDays,
    f.perfectDays,
    f.consistencyPercent,
  ),
  days,
  reason: '$why: S, O, E, full, Perfect, consistency',
);

void main() {
  group('§ 12.5.1 worked examples on real Drift, every screen agreeing', () {
    test('A and B: an active Arc, then the date rolled back a day', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
      addTearDown(app.db.close);
      final arc = await _startFive(app, LocalDate(2026, 10, 7));
      await _liveDate(app, LocalDate(2026, 10, 7), 5); // 105
      await _liveDate(app, LocalDate(2026, 10, 8), 4); // 60
      await _liveDate(app, LocalDate(2026, 10, 9), 2); // 30
      var f = await expectArcReconciles(app, arc.id, context: 'A');
      _expectXp(f, (165, 30, 0, 0, 195), 'A');
      // 9 Oct is open with 2 of 5: full 1, Perfect 1, 100 ~/ 3 = 33%.
      _expectDays(f, (2, 1, 3, 1, 1, 33), '§ 12.5.2-style A');
      at(app, LocalDate(2026, 10, 8));
      f = await expectArcReconciles(app, arc.id, context: 'B');
      _expectXp(f, (105, 60, 30, 0, 195), 'B');
    });

    test(
      '§ 12.5.2 A: 7 Oct Perfect, 8 Oct partial, 9 Oct Perfect so far',
      () async {
        final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
        addTearDown(app.db.close);
        final arc = await _startFive(app, LocalDate(2026, 10, 7));
        await _liveDate(app, LocalDate(2026, 10, 7), 5);
        await _liveDate(app, LocalDate(2026, 10, 8), 4);
        await _liveDate(app, LocalDate(2026, 10, 9), 5);
        final f = await expectArcReconciles(app, arc.id, context: '12.5.2 A');
        _expectDays(f, (2, 1, 3, 2, 2, 66), '§ 12.5.2 A');
      },
    );

    test(
      'D, E, F and H: ended on 12 Nov after logging (2,430 XP), viewed '
      'on closedOn, later, rolled back, and restored on a device behind',
      () async {
        final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
        addTearDown(app.db.close);
        final arc = await _startFive(app, LocalDate(2026, 10, 7));
        // Days 1–35 (7 Oct – 10 Nov): 22 Perfect Days, one day with one
        // habit, the rest empty = 2,325 XP.
        for (var n = 1; n <= 35; n++) {
          final habits = n <= 22 ? 5 : (n == 35 ? 1 : 0);
          await _liveDate(app, LocalDate(2026, 10, 7).addDays(n - 1), habits);
        }
        await _liveDate(app, LocalDate(2026, 11, 11), 4); // 60
        await _liveDate(app, LocalDate(2026, 11, 12), 3); // 45
        at(app, LocalDate(2026, 11, 12), hour: 20);
        final restart = await restartNow(app, arc.id);
        expect(restart.ended.closedOn, LocalDate(2026, 11, 12));

        var f = await expectArcReconciles(app, arc.id, context: 'D');
        _expectXp(f, (2430, 0, 0, 0, 2430), 'D (closedOn = T)');
        at(app, LocalDate(2026, 11, 20));
        f = await expectArcReconciles(app, arc.id, context: 'E');
        _expectXp(f, (2430, 0, 0, 0, 2430), 'E (closedOn < T)');
        at(app, LocalDate(2026, 11, 11));
        f = await expectArcReconciles(app, arc.id, context: 'F');
        _expectXp(f, (2385, 0, 45, 0, 2430), 'F (rolled back)');

        // H: exported on 12 Nov, restored on a device whose date is 10 Nov.
        at(app, LocalDate(2026, 11, 12), hour: 21);
        final bytes = (await app.backup.export()).bytes;
        final device = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, 11, 10, 9)),
        );
        addTearDown(device.db.close);
        final validated = await device.backup.inspect(bytes);
        await device.backup.restore(validated);
        final restored = [
          for (final s in await device.sessions.listSessions())
            if (s.status == WinterArcStatus.ended) s,
        ].single;
        final ledgerBefore = await xpRows(device.db);
        f = await expectArcReconciles(device, restored.id, context: 'H');
        _expectXp(f, (2325, 0, 105, 0, 2430), 'H (restored, device behind)');
        await device.lifecycle.reconcile();
        await device.achievements.reconcile();
        expect(
          await xpRows(device.db),
          ledgerBefore,
          reason: 'the restored ledger is never re-derived or re-awarded',
        );
      },
    );

    test('G and G′: paused 11–19 Mar, resumed 20 Mar', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
      addTearDown(app.db.close);
      final arc = await _startFive(app, LocalDate(2027, 3, 1));
      // 1–10 Mar: eight Perfect Days and one of four habits = 900 XP.
      for (var n = 1; n <= 10; n++) {
        await _liveDate(
          app,
          LocalDate(2027, 3, n),
          n == 9 ? 4 : (n == 10 ? 0 : 5),
        );
      }
      at(app, LocalDate(2027, 3, 10), hour: 21);
      await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: LocalDate(2027, 3, 11));
      at(app, LocalDate(2027, 3, 15));
      var f = await expectArcReconciles(app, arc.id, context: 'G′');
      _expectXp(f, (900, 0, 0, 0, 900), 'G′ (paused)');
      at(app, LocalDate(2027, 3, 20), hour: 8);
      await pauseServiceOf(app)
          .resume(sessionId: arc.id, on: LocalDate(2027, 3, 20));
      await _liveDate(app, LocalDate(2027, 3, 20), 5);
      await _liveDate(app, LocalDate(2027, 3, 21), 4);
      f = await expectArcReconciles(app, arc.id, context: 'G');
      _expectXp(f, (1005, 60, 0, 0, 1065), 'G (resumed)');
    });
  });

  group('§ 12.5.2 worked examples on real Drift', () {
    test("D′ and D: freeze scheduled for 11 Mar, then paused; Days 1–9 "
        '6 full, 4 Perfect; today not full', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
      addTearDown(app.db.close);
      final arc = await _startFive(app, LocalDate(2027, 3, 1));
      // Days 1–4 Perfect, 5–6 completed Minimum Days, 7–9 partial.
      for (var n = 1; n <= 9; n++) {
        final date = LocalDate(2027, 3, n);
        at(app, date, hour: 19);
        await app.lifecycle.reconcile();
        if (n == 5 || n == 6) {
          await app.tracking.activateMinimumDay(date: date);
          await completeAll(app);
        } else {
          await _logFirst(app, n <= 4 ? 5 : 2);
        }
      }
      at(app, LocalDate(2027, 3, 10), hour: 19);
      await _logFirst(app, 1);
      await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: LocalDate(2027, 3, 11));
      var f = await expectArcReconciles(app, arc.id, context: 'D′');
      _expectDays(f, (9, 1, 10, 6, 4, 60), "D'");
      at(app, LocalDate(2027, 3, 15));
      f = await expectArcReconciles(app, arc.id, context: 'D');
      _expectDays(f, (10, 0, 10, 6, 4, 60), 'D');
    });

    test('E, F, G: 7 Oct partial, 8 Oct Perfect, restarted on 8 Oct; viewed '
        'on closedOn, later, and rolled back before it', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
      addTearDown(app.db.close);
      final arc = await _startFive(app, LocalDate(2026, 10, 7));
      await _liveDate(app, LocalDate(2026, 10, 7), 3);
      await _liveDate(app, LocalDate(2026, 10, 8), 5);
      await restartNow(app, arc.id);
      var f = await expectArcReconciles(app, arc.id, context: 'E');
      _expectDays(f, (2, 0, 2, 1, 1, 50), 'E');
      at(app, LocalDate(2026, 10, 20));
      f = await expectArcReconciles(app, arc.id, context: 'F');
      _expectDays(f, (2, 0, 2, 1, 1, 50), 'F');
      at(app, LocalDate(2026, 10, 7));
      f = await expectArcReconciles(app, arc.id, context: 'G');
      _expectDays(f, (1, 0, 1, 0, 0, 0), 'G');
      at(app, LocalDate(2026, 10, 8));
      f = await expectArcReconciles(app, arc.id, context: 'E again');
      _expectDays(f, (2, 0, 2, 1, 1, 50), 'E again');
    });

    test('I and zero activity: before Day 1 nothing is divided; a week of '
        'nothing logged is counted, never full', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
      addTearDown(app.db.close);
      final arc = await _startFive(app, LocalDate(2026, 10, 7));
      var f = await expectArcReconciles(app, arc.id, context: 'first day');
      _expectDays(f, (0, 1, 1, 0, 0, 0), 'first day, nothing logged');
      at(app, LocalDate(2026, 10, 6));
      f = await expectArcReconciles(app, arc.id, context: 'I');
      _expectDays(f, (0, 0, 0, 0, 0, 0), 'I: before Day 1');
      at(app, LocalDate(2026, 10, 14));
      await app.lifecycle.reconcile();
      f = await expectArcReconciles(app, arc.id, context: 'zero activity');
      _expectDays(f, (7, 1, 8, 0, 0, 0), 'a quiet week');
      _expectXp(f, (0, 0, 0, 0, 0), 'no XP');
    });
  });

  group('generated histories on real Drift (every date reconciled)', () {
    final covered = <String, int>{};
    void saw(String what) =>
        covered.update(what, (n) => n + 1, ifAbsent: () => 1);
    for (var seed = 1; seed <= 16; seed++) {
      test('seed $seed', () async {
        final random = Random(seed * 7919);
        final start = LocalDate(2026, 10, 1).addDays(random.nextInt(60));
        final app = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(start.year, start.month, start.day, 9)),
        );
        addTearDown(app.db.close);
        var arc = seed.isEven
            ? await joinSeason(app, DateTime(2026, 10, 1 + random.nextInt(25)))
            : await _startFive(app, start);
        var date = app.clock.today();
        var restarted = false;
        for (var step = 0; step < 36; step++) {
          at(app, date, hour: 19);
          await app.lifecycle.reconcile();
          final s = await stored(app, arc.id);
          if (s.status != WinterArcStatus.active) break;
          if (s.isParticipatingOn(date)) {
            switch (random.nextInt(10)) {
              case 0:
                break; // nothing logged
              case 1:
                await app.tracking.activateMinimumDay(date: date);
                await _logFirst(app, 1 + random.nextInt(5));
              case 2:
                await app.tracking.editHabit(
                  habitId: 'water',
                  edit: HabitEdit(target: 6 + random.nextInt(6)),
                  date: date,
                );
                await _logFirst(app, random.nextInt(6));
              default:
                await _logFirst(app, random.nextInt(6));
            }
            await app.achievements.reconcile();
          }
          final pauses = pauseServiceOf(app);
          final roll = random.nextInt(14);
          if (roll == 0 && !s.isSeasonal && !s.hasOpenFreeze) {
            final preview = await pauses.pausePreview(arc.id);
            if (preview.blocker == null && preview.guard is ClockGuardSafe) {
              await pauses.pause(
                sessionId: arc.id,
                frozenFrom: preview.frozenFrom,
              );
              saw('pause');
            }
          } else if (roll == 1 && s.hasOpenFreeze) {
            final preview = await pauses.resumePreview(arc.id);
            if (preview.resumed != null) {
              await pauses.resume(sessionId: arc.id, on: date);
              saw('resume');
            }
          } else if (roll == 2 && !restarted) {
            final preview = await restartServiceOf(app).preview(arc.id);
            if (preview.canRestart) {
              final outcome = await restartNow(app, arc.id);
              arc = outcome.started;
              restarted = true;
              saw(s.isSeasonal ? 'seasonal restart' : 'rolling restart');
            }
          }
          for (final x in await expectAllArcsReconcile(
            app,
            context: 'seed $seed $date',
          )) {
            saw(x.status.name);
            if (x.open == 0 && x.status == WinterArcStatus.active) {
              saw('active, not open');
            }
          }
          if (random.nextInt(9) == 0) {
            // The local date moves back 1–3 days, is reconciled there,
            // then returns.
            at(app, date.addDays(-1 - random.nextInt(3)));
            saw('rollback');
            await expectAllArcsReconcile(
              app,
              context: 'seed $seed rolled back from $date',
            );
          }
          date = date.addDays(1 + (random.nextInt(8) == 0 ? 2 : 0));
        }
      });
    }

    test('the generated histories cover every lifecycle case', () {
      for (final what in [
        'pause',
        'resume',
        'rolling restart',
        'seasonal restart',
        'rollback',
        'active',
        'ended',
        'active, not open',
      ]) {
        expect(covered[what] ?? 0, greaterThan(0), reason: '$what: $covered');
      }
    });
  });
}
