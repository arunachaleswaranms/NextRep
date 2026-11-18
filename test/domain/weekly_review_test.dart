import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/lifecycle_arcs.dart';
import '../support/review_arcs.dart';

/// Phase 12B: the Weekly Review's metrics, highlights and reconciliation
/// (ARC_MOMENTUM_SPEC §§ 4, 12.5). Pure; all data synthetic.

final wed = LocalDate(2026, 10, 7); // Rolling Arcs below start here
LocalDate dOf(int day) => wed.addDays(day - 1);

/// Spec § 4.6, example 1: Week 1 of a Rolling Arc started Wed 7 Oct 2026.
final example1Days = <LocalDate, DayData>{
  dOf(1): day(allFive, xp: 105),
  dOf(2): day({'water', 'workout', 'sleep', 'junk'}, xp: 60),
  dOf(3): day(allFive, mode: DayMode.minimum, xp: 75),
  dOf(4): day({}),
  dOf(5): day({'water', 'workout', 'junk'}, xp: 45),
  dOf(6): day(allFive, xp: 105),
  dOf(7): day({'water', 'junk'}, mode: DayMode.minimum, xp: 30),
};

/// Week 1 of a Rolling Arc from [wed] viewed on Day 8 (complete), with
/// [days] and [habits].
WeeklyReview week1(
  Map<LocalDate, DayData> days, {
  List<HabitRevision> revisions = const [],
  List<String>? habitIds,
}) => WeeklyReview.fromHistory(
  historyOf(
    rollingArc(wed),
    dOf(8),
    days: days,
    revisions: revisions,
    habits: habitIds == null
        ? null
        : [
            for (final (i, id) in habitIds.indexed)
              namedHabit(id, id.toUpperCase(), order: i),
          ],
  ),
  1,
);

HabitConfig off() =>
    const HabitConfig(target: 1, minimumTarget: 1, enabled: false);

HabitRevision disable(String id, LocalDate from) => HabitRevision(
  habitId: id,
  effectiveFrom: from,
  config: off(),
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('metrics (§ 4.2)', () {
    test('spec example 1: a completed Rolling week, exact numbers', () {
      final r = week1(example1Days);
      expect(r.status, ArcWeekStatus.complete);
      expect(r.countedDays, 7);
      expect(r.habitOpportunities, 35);
      expect(r.completedHabitDays, 24);
      expect(r.completionPercent, 68);
      expect(r.fullDays, 3);
      expect(r.consistencyPercent, 42);
      expect(r.perfectDays, 2);
      expect(r.minimumDaysChosen, 2);
      expect(r.minimumDaysCompleted, 1);
      expect(r.xpEarned, 420);
      expect(r.xpEarned, 15 * r.completedHabitDays + 30 * r.perfectDays);
      expect(
        {
          for (final t in r.habits)
            t.habit.title: (t.completedDays, t.applicableDays),
        },
        {
          'Water': (6, 7),
          'Workout': (5, 7),
          'Reading': (3, 7),
          'Sleep Before': (4, 7),
          'No Junk Food': (6, 7),
        },
      );
      expect(r.mostConsistent!.habit.title, 'Water');
      expect(r.roomToGrow!.habit.title, 'Reading');
      expect(r.today, isNull);
      expect(r.isFirstWeek, isTrue);
      expect(r.isFinalReview, isFalse);
    });

    test('spec example 2: the current week with today open, Seasonal Arc', () {
      final s = seasonalArc(2026, joined: LocalDate(2026, 10, 1));
      LocalDate sd(int d) => LocalDate(2026, 10, d);
      final h = historyOf(
        s,
        sd(18),
        days: {
          sd(15): day(allFive, xp: 105),
          sd(16): day({'water', 'workout', 'sleep', 'junk'}, xp: 60),
          sd(17): day(allFive, xp: 105),
          sd(18): day({'water', 'workout'}, xp: 30),
        },
      );
      final r = WeeklyReview.fromHistory(h, 3);
      expect(r.status, ArcWeekStatus.inProgress);
      expect(r.countedDays, 3);
      expect(r.habitOpportunities, 15);
      expect(r.completedHabitDays, 14);
      expect(r.completionPercent, 93);
      expect(r.fullDays, 2);
      expect(r.consistencyPercent, 66);
      expect(r.perfectDays, 2);
      expect(r.minimumDaysChosen, 0);
      expect(r.minimumDaysCompleted, 0);
      expect(r.xpEarned, 270);
      final today = r.today!;
      expect(today.dayNumber, 18);
      expect(today.date, sd(18));
      expect((today.completed, today.total, today.xp), (2, 5, 30));
      expect(today.mode, DayMode.normal);
      expect(r.mostConsistent!.habit.title, 'Water');
      expect(r.roomToGrow, isNull);
      // Upcoming days 19–21 are not in any total.
      expect(r.week.settledDates, [sd(15), sd(16), sd(17)]);
    });

    test('spec example 3: late join; pre-join days never in a denominator', () {
      final s = seasonalArc(2026, joined: LocalDate(2026, 10, 18));
      LocalDate sd(int d) => LocalDate(2026, 10, d);
      final data = {
        for (var d = 18; d <= 21; d++) sd(d): day(allFive, xp: 105),
      };
      WeeklyReview on(int date) =>
          WeeklyReview.fromHistory(historyOf(s, sd(date), days: data), 3);
      expect(on(18).countedDays, 0);
      expect(on(18).today!.dayNumber, 18);
      expect(on(19).countedDays, 1);
      expect(on(21).countedDays, 3);
      final done = on(22);
      expect(done.status, ArcWeekStatus.complete);
      expect(done.countedDays, 4);
      expect(done.habitOpportunities, 20);
      expect(done.today, isNull);
      expect(done.isFirstWeek, isTrue);
      for (final t in done.habits) {
        expect(t.applicableDays, 4);
      }
    });

    test('spec example 4: a goal revision and a disabled habit mid-week; '
        'stored flags are never re-scored', () {
      final s = rollingArc(wed);
      final revisions = [
        HabitRevision(
          habitId: 'water',
          effectiveFrom: dOf(10),
          config: const HabitConfig(
            target: 10,
            minimumTarget: 4,
            enabled: true,
          ),
          createdAt: DateTime(2026, 10, 15),
        ),
        disable('workout', dOf(12)),
      ];
      final h = historyOf(
        s,
        dOf(15),
        revisions: revisions,
        days: {
          dOf(8): day({'water', 'workout'}),
          dOf(9): day({'water', 'workout'}), // 8 of 8: completed that day
          // 9 of 10: stored incomplete although 9 ≥ the old target 8.
          dOf(10): day({'workout'}, partial: {'water': 9}),
          dOf(11): day({'water'}),
          dOf(12): day({'water'}),
          dOf(13): day({'water'}),
          dOf(14): day({'water'}),
        },
      );
      final r = WeeklyReview.fromHistory(h, 2);
      final water = r.habits.firstWhere((t) => t.habit.id == 'water');
      final workout = r.habits.firstWhere((t) => t.habit.id == 'workout');
      expect((water.completedDays, water.applicableDays), (6, 7));
      expect((workout.completedDays, workout.applicableDays), (3, 4));
      expect(r.habitOpportunities, 35 - 3);
    });

    test('spec example 5: a Minimum Day returned to full is stored normal: '
        'Perfect when done, never in M', () {
      final r = week1({
        for (var d = 1; d <= 7; d++) dOf(d): day(allFive, xp: 105),
      });
      expect(r.minimumDaysChosen, 0);
      expect(r.perfectDays, 7);
      expect(r.fullDays, 7);
    });

    test('Minimum Days: counted at their minimum, full when complete, never '
        'Perfect; a partial one is chosen but not completed', () {
      final r = week1({
        dOf(1): day(allFive, mode: DayMode.minimum),
        dOf(2): day({'water'}, mode: DayMode.minimum),
        dOf(3): day(allFive),
      });
      expect(r.minimumDaysChosen, 2);
      expect(r.minimumDaysCompleted, 1);
      expect(r.perfectDays, 1);
      expect(r.fullDays, 2);
    });

    test('partial progress (count 5/8, duration 20/30) is not completed', () {
      final r = week1({
        dOf(1): day(
          {'reading', 'sleep', 'junk'},
          partial: {'water': 5, 'workout': 20},
        ),
      });
      expect(r.completedHabitDays, 3);
      expect(r.habitOpportunities, 35);
      expect(r.fullDays, 0);
    });

    test('a quiet week (example 7): no XP, no highlights', () {
      final r = week1({});
      expect(r.countedDays, 7);
      expect(r.completedHabitDays, 0);
      expect(r.xpEarned, 0);
      expect(r.completionPercent, 0);
      expect(r.consistencyPercent, 0);
      expect(r.mostConsistent, isNull);
      expect(r.roomToGrow, isNull);
    });

    test('zero opportunities (no enabled habit, only via a hand-made '
        'restore): the day counts, no division by zero', () {
      final r = week1(
        {dOf(1): day({})},
        habitIds: ['a'],
        revisions: [disable('a', dOf(1))],
      );
      expect(r.countedDays, 7);
      expect(r.habitOpportunities, 0);
      expect(r.completionPercent, isNull);
      expect(r.consistencyPercent, 0);
      expect(r.habits, isEmpty);
    });

    test('XP comes from the ledger only, never from completions', () {
      final h = historyOf(
        rollingArc(wed),
        dOf(8),
        days: {dOf(1): day(allFive, xp: 7)}, // not 15·5 + 30
      );
      expect(WeeklyReview.fromHistory(h, 1).xpEarned, 7);
    });

    test('the summit week of a completed Arc: 8 settled days, final', () {
      final s = rollingArc(wed, status: WinterArcStatus.completed);
      final h = historyOf(
        s,
        s.endDate.addDays(3),
        days: {for (var d = 85; d <= 92; d++) dOf(d): day(allFive, xp: 105)},
      );
      final r = WeeklyReview.fromHistory(h, 13);
      expect(r.countedDays, 8);
      expect(r.habitOpportunities, 40);
      expect(r.xpEarned, 840);
      expect(r.isFinalReview, isTrue);
      expect(r.today, isNull);
      expect(r.nextWeek, isNull);
      expect(r.previousWeek, 12);
    });

    test('a historic completed Arc: the same review for any later today', () {
      final s = rollingArc(wed, status: WinterArcStatus.completed);
      final days = {
        for (var d = 1; d <= 92; d++)
          dOf(d): day(d.isEven ? allFive : {'water'}, xp: d),
      };
      String snapshot(LocalDate today) {
        final h = historyOf(s, today, days: days);
        return [
          for (final r in allReviews(h))
            '${r.number}:${r.status}:${r.countedDays}:${r.completedHabitDays}'
                ':${r.fullDays}:${r.perfectDays}:${r.xpEarned}'
                ':${r.mostConsistent?.habit.id}:${r.roomToGrow?.habit.id}',
        ].join('|');
      }

      final first = snapshot(s.endDate.addDays(1));
      for (final later in [10, 100, 1000]) {
        expect(snapshot(s.endDate.addDays(later)), first);
      }
    });

    test(
      'the strip is the Journey: same day, date and state for every day',
      () {
        final s = seasonalArc(2026, joined: LocalDate(2026, 10, 18));
        final h = historyOf(
          s,
          LocalDate(2026, 10, 20),
          days: {LocalDate(2026, 10, 18): day(allFive)},
        );
        final journey = h.journey();
        for (final r in allReviews(h)) {
          for (final d in r.days) {
            final j = journey[d.dayNumber - 1];
            expect(d.journeyDay.dayNumber, j.dayNumber);
            expect(d.journeyDay.date, j.date);
            expect(d.journeyDay.state, j.state);
            expect(d.journeyDay.isToday, j.isToday);
            expect(classMatchesJourney(d.weekDay.dayClass, j), isTrue);
          }
        }
      },
    );
  });

  group('highlights (§ 4.4)', () {
    test('ties on ratio go to more completed days, then display order', () {
      // A done every applicable day of 3 (disabled from Day 4); B done all
      // 7 days: both 100%, B has more completed days.
      final r = week1(
        {
          for (var d = 1; d <= 7; d++) dOf(d): day({'a', 'b'}),
        },
        habitIds: ['a', 'b'],
        revisions: [disable('a', dOf(4))],
      );
      expect(r.mostConsistent!.habit.id, 'b');
      // Equal ratio and days: the earlier habit (example 1: Water before
      // No Junk Food).
      expect(week1(example1Days).mostConsistent!.habit.id, 'water');
    });

    test('ranking compares exact ratios, not rounded percentages', () {
      // a: 4 of 7 (57.1%); b: 3 of 5 (60%): b ranks higher.
      final r = week1(
        {
          for (var d = 1; d <= 7; d++)
            dOf(d): day({if (d <= 4) 'a', if (d <= 3) 'b'}),
        },
        habitIds: ['a', 'b'],
        revisions: [disable('b', dOf(6))],
      );
      expect(r.mostConsistent!.habit.id, 'b');
      expect(r.mostConsistent!.applicableDays, 5);
    });

    test('Most consistent needs at least half of its days', () {
      final r = week1(
        {
          for (var d = 1; d <= 7; d++) dOf(d): day({if (d <= 3) 'a'}),
        },
        habitIds: ['a', 'b'],
      );
      expect(r.mostConsistent, isNull); // 3 of 7 is under half
      final half = week1(
        {
          for (var d = 1; d <= 6; d++) dOf(d): day({if (d <= 3) 'a'}),
        },
        habitIds: ['a'],
        revisions: [disable('a', dOf(7))],
      );
      expect(half.mostConsistent!.habit.id, 'a'); // 3 of 6 is half
    });

    test('Room to grow: lowest ratio; ties to more applicable days, then '
        'display order', () {
      // top 7/7; a 1/7 and b 1/7 tie: earlier order (a).
      final byOrder = week1(
        {
          for (var d = 1; d <= 7; d++)
            dOf(d): day({'top', if (d == 1) 'a', if (d == 1) 'b'}),
        },
        habitIds: ['top', 'a', 'b'],
      );
      expect(byOrder.roomToGrow!.habit.id, 'a');

      // a 1/3 (disabled from Day 4) and b 2/6 (disabled on Day 7): equal
      // ratio, b has more applicable days.
      final byDays = week1(
        {
          for (var d = 1; d <= 7; d++)
            dOf(d): day({'top', if (d == 1) 'a', if (d <= 2) 'b'}),
        },
        habitIds: ['top', 'a', 'b'],
        revisions: [disable('a', dOf(4)), disable('b', dOf(7))],
      );
      expect(byDays.roomToGrow!.habit.id, 'b');

      // The lowest ratio wins over more days.
      final lowest = week1(
        {
          for (var d = 1; d <= 7; d++)
            dOf(d): day({'top', if (d <= 2) 'a', if (d == 1) 'b'}),
        },
        habitIds: ['top', 'a', 'b'],
      );
      expect(lowest.roomToGrow!.habit.id, 'b');
    });

    test('no Room to grow with one eligible habit, with every ratio equal, '
        'with nothing completed, or below the sample sizes', () {
      // One eligible habit (b has fewer than 3 applicable days).
      expect(
        week1(
          {
            for (var d = 1; d <= 7; d++) dOf(d): day({if (d == 1) 'a', 'b'}),
          },
          habitIds: ['a', 'b'],
          revisions: [disable('b', dOf(3))],
        ).roomToGrow,
        isNull,
      );
      // Every ratio equal (1 of 7 each).
      final tied = week1(
        {
          dOf(1): day({'a', 'b', 'c'}),
        },
        habitIds: ['a', 'b', 'c'],
      );
      expect(tied.roomToGrow, isNull);
      expect(tied.mostConsistent, isNull);
      // Nothing completed.
      expect(week1({}, habitIds: ['a', 'b']).roomToGrow, isNull);
      // N < 3: two settled days only (Day 3 of a new Arc).
      final early = WeeklyReview.fromHistory(
        historyOf(
          rollingArc(wed),
          dOf(3),
          habits: [
            namedHabit('a', 'A', order: 0),
            namedHabit('b', 'B', order: 1),
          ],
          days: {
            dOf(1): day({'a'}),
            dOf(2): day({'a'}),
          },
        ),
        1,
      );
      expect(early.countedDays, 2);
      expect(early.mostConsistent, isNull);
      expect(early.roomToGrow, isNull);
    });

    test('the two highlights are never the same habit', () {
      final generator = HistoryGenerator(77);
      var both = 0;
      for (var i = 0; i < 150; i++) {
        final s = generator.session();
        for (final today in generator.todays(s)) {
          for (final r in allReviews(generator.history(s, today))) {
            final best = r.mostConsistent;
            final grow = r.roomToGrow;
            if (best != null && grow != null) {
              both++;
              expect(best.habit.id, isNot(grow.habit.id));
              expect(
                2 * best.completedDays,
                greaterThanOrEqualTo(best.applicableDays),
              );
              expect(2 * grow.completedDays, lessThan(grow.applicableDays));
            }
            if (r.countedDays < 3 || r.completedHabitDays == 0) {
              expect(grow, isNull);
            }
            if (r.countedDays < 3) expect(best, isNull);
            for (final t in [?best, ?grow]) {
              expect(t.applicableDays, greaterThanOrEqualTo(3));
            }
          }
        }
      }
      expect(both, greaterThan(0), reason: 'the property was exercised');
    });
  });

  group('freeze, ended and rollback reviews (§ 12.3)', () {
    final mar1 = LocalDate(2027, 3, 1);
    LocalDate m(int d) => LocalDate(2027, 3, d);

    test('a paused week: totals so far, no Today so far, paused since', () {
      final s = rollingArc(mar1, freezes: [openFreeze(m(11))]);
      final h = historyOf(
        s,
        m(15),
        days: {for (var d = 1; d <= 10; d++) m(d): day(allFive, xp: 90)},
      );
      final r = WeeklyReview.fromHistory(h, 2);
      expect(r.status, ArcWeekStatus.paused);
      expect(r.countedDays, 3); // 8–10 Mar
      expect(r.xpEarned, 270);
      expect(r.today, isNull);
      expect(r.pausedSince, m(11));
      expect(r.nextWeek, isNull);
      expect(r.previousWeek, 1);
      checkIdentities(h);
    });

    test('a paused week with nothing settled is still reviewable', () {
      final s = rollingArc(mar1, freezes: [openFreeze(m(15))]);
      final h = historyOf(s, m(20));
      final r = WeeklyReview.fromHistory(h, 3);
      expect(r.status, ArcWeekStatus.paused);
      expect(r.week.isReviewable, isTrue);
      expect(r.countedDays, 0);
      expect(r.today, isNull);
    });

    test('after Resume the week continues from the right day; a final week '
        'is unchanged', () {
      final paused = rollingArc(mar1, freezes: [openFreeze(m(11))]);
      final resumed = rollingArc(mar1, freezes: [closedFreeze(m(11), 9)]);
      final days = {
        for (var d = 1; d <= 10; d++) m(d): day(allFive, xp: 90),
        m(20): day(allFive, xp: 105),
        m(21): day({'water'}, xp: 60),
      };
      final before = WeeklyReview.fromHistory(
        historyOf(paused, m(15), days: days),
        1,
      );
      final after = historyOf(resumed, m(21), days: days);
      final w1 = WeeklyReview.fromHistory(after, 1);
      expect(
        (w1.countedDays, w1.completedHabitDays, w1.xpEarned, w1.fullDays),
        (
          before.countedDays,
          before.completedHabitDays,
          before.xpEarned,
          before.fullDays,
        ),
      );
      final w2 = WeeklyReview.fromHistory(after, 2);
      expect(w2.status, ArcWeekStatus.inProgress);
      expect(w2.countedDays, 4); // 8, 9, 10, 20 Mar
      expect(w2.today!.dayNumber, 12);
      expect(w2.today!.xp, 60);
      expect(w2.week.days[3].date, m(20)); // Day 11
      expect(w2.week.days.last.date, m(23)); // Day 14
    });

    test(
      'an ended Arc: no Today so far; closedOn settled once; final week',
      () {
        final closed = dOf(37);
        final s = rollingArc(
          wed,
          status: WinterArcStatus.ended,
          closedOn: closed,
        );
        final days = {
          for (var d = 1; d <= 37; d++) dOf(d): day(allFive, xp: 105),
        };
        final h = historyOf(s, closed, days: days);
        final r = WeeklyReview.fromHistory(h, 6);
        expect(r.status, ArcWeekStatus.complete);
        expect(r.countedDays, 2); // Days 36–37
        expect(r.xpEarned, 210);
        expect(r.today, isNull);
        expect(r.isFinalReview, isTrue);
        expect(r.nextWeek, isNull);
        checkIdentities(h);

        // Rolled back before closedOn: closedOn is not counted.
        final back = historyOf(s, dOf(36), days: days);
        final rb = WeeklyReview.fromHistory(back, 6);
        expect(rb.countedDays, 1);
        expect(rb.xpEarned, 105);
        expect(rb.today, isNull);
        checkIdentities(back);
      },
    );

    test('a completed Arc after a rollback into it: Today so far shown', () {
      final s = rollingArc(wed, status: WinterArcStatus.completed);
      final days = {for (var d = 1; d <= 92; d++) dOf(d): day(allFive, xp: 45)};
      final h = historyOf(s, dOf(90), days: days);
      final r = WeeklyReview.fromHistory(h, 13);
      expect(r.status, ArcWeekStatus.inProgress);
      expect(r.today!.dayNumber, 90);
      expect(r.countedDays, 5); // 85–89
      expect(r.session.status, WinterArcStatus.completed);
      checkIdentities(h);
    });
  });

  group('XP split worked examples (§ 12.5.1, R15)', () {
    Map<LocalDate, DayData> spread(LocalDate from, int count, int total) {
      final each = total ~/ count;
      return {
        for (var i = 0; i < count; i++)
          from.addDays(i): day(
            {},
            xp: each + (i == 0 ? total - each * count : 0),
          ),
      };
    }

    void expectSplit(ArcHistory h, (int, int, int, int, int) abcdt) {
      final ref = checkIdentities(h);
      final x = allReviews(h).fold(0, (s, r) => s + r.xpEarned);
      final today = allReviews(h).fold(0, (s, r) => s + (r.today?.xp ?? 0));
      expect((x, today, ref.futureXp, ref.otherXp, h.records.totalXp), abcdt);
    }

    final ledgerA = {
      LocalDate(2026, 10, 7): day({}, xp: 105),
      LocalDate(2026, 10, 8): day({}, xp: 60),
      LocalDate(2026, 10, 9): day({}, xp: 30),
    };
    final closedD = LocalDate(2026, 11, 12);
    final ledgerD = {
      ...spread(wed, 35, 2325), // 7 Oct – 10 Nov
      LocalDate(2026, 11, 11): day({}, xp: 60),
      closedD: day({}, xp: 45),
    };
    final endedD = rollingArc(
      wed,
      status: WinterArcStatus.ended,
      closedOn: closedD,
    );

    test('A: active, normal date', () {
      expectSplit(
        historyOf(rollingArc(wed), LocalDate(2026, 10, 9), days: ledgerA),
        (165, 30, 0, 0, 195),
      );
    });

    test('B: active, the date rolled back a day', () {
      expectSplit(
        historyOf(rollingArc(wed), LocalDate(2026, 10, 8), days: ledgerA),
        (105, 60, 30, 0, 195),
      );
    });

    test('C: completed, after Day 92', () {
      final s = rollingArc(wed, status: WinterArcStatus.completed);
      expectSplit(
        historyOf(s, LocalDate(2027, 1, 10), days: spread(wed, 92, 4200)),
        (4200, 0, 0, 0, 4200),
      );
    });

    test('D, E, F, H: ended on closedOn, after it, rolled back, restored '
        'behind', () {
      expectSplit(historyOf(endedD, closedD, days: ledgerD), (
        2430,
        0,
        0,
        0,
        2430,
      ));
      expectSplit(historyOf(endedD, LocalDate(2026, 11, 20), days: ledgerD), (
        2430,
        0,
        0,
        0,
        2430,
      ));
      expectSplit(historyOf(endedD, LocalDate(2026, 11, 11), days: ledgerD), (
        2385,
        0,
        45,
        0,
        2430,
      ));
      expectSplit(historyOf(endedD, LocalDate(2026, 11, 10), days: ledgerD), (
        2325,
        0,
        105,
        0,
        2430,
      ));
    });

    test('G, G′: paused 11–19 Mar 2027, resumed 20 Mar; and while paused', () {
      final mar1 = LocalDate(2027, 3, 1);
      final before = spread(mar1, 10, 900);
      expectSplit(
        historyOf(
          rollingArc(mar1, freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)]),
          LocalDate(2027, 3, 21),
          days: {
            ...before,
            LocalDate(2027, 3, 20): day({}, xp: 105),
            LocalDate(2027, 3, 21): day({}, xp: 60),
          },
        ),
        (1005, 60, 0, 0, 1065),
      );
      expectSplit(
        historyOf(
          rollingArc(mar1, freezes: [openFreeze(LocalDate(2027, 3, 11))]),
          LocalDate(2027, 3, 15),
          days: before,
        ),
        (900, 0, 0, 0, 900),
      );
    });

    test(
      'the week-boundary example (§ 4.5.1): 525 XP across Day 7 / Day 8',
      () {
        final days = {
          ...spread(wed, 6, 360),
          dOf(7): day({}, xp: 105),
          dOf(8): day({}, xp: 60),
        };
        final on8 = historyOf(rollingArc(wed), dOf(8), days: days);
        expect(WeeklyReview.fromHistory(on8, 1).xpEarned, 465);
        expectSplit(on8, (465, 60, 0, 0, 525));
        final on7 = historyOf(rollingArc(wed), dOf(7), days: days);
        final w1 = WeeklyReview.fromHistory(on7, 1);
        expect(w1.status, ArcWeekStatus.inProgress);
        expect(w1.xpEarned, 360);
        expect(WeeklyReview.fromHistory(on7, 2).status, ArcWeekStatus.upcoming);
        expectSplit(on7, (360, 105, 60, 0, 525));
      },
    );

    test('before the participation start: everything future-dated', () {
      final joined = LocalDate(2026, 10, 18);
      final s = seasonalArc(2026, joined: joined);
      final days = {joined: day({}, xp: 15)};
      expectSplit(historyOf(s, LocalDate(2026, 10, 17), days: days), (
        0,
        0,
        15,
        0,
        15,
      ));
      expectSplit(
        historyOf(rollingArc(joined), LocalDate(2026, 10, 17), days: days),
        (0, 0, 15, 0, 15),
      );
    });
  });

  group('day-count, consistency and Perfect Day examples (§ 12.5.2, R21)', () {
    /// (Σ N, |O|, |E|, Fs, Fo, Ps, Po, consistency)
    void expectDays(
      ArcHistory h,
      (int, int, int, int, int, int, int, int) expected,
    ) {
      final ref = checkIdentities(h);
      final reviews = allReviews(h);
      expect((
        reviews.fold(0, (s, r) => s + r.countedDays),
        ref.open.length,
        ref.elapsed.length,
        reviews.fold(0, (s, r) => s + r.fullDays),
        ref.openFull,
        reviews.fold(0, (s, r) => s + r.perfectDays),
        ref.openPerfect,
        ref.summary.consistencyPercent,
      ), expected);
    }

    final partial = day({'water'});
    final perfect = day(allFive);
    final minimum = day(allFive, mode: DayMode.minimum);

    test('A: active, today open and Perfect so far', () {
      expectDays(
        historyOf(
          rollingArc(wed),
          dOf(3),
          days: {dOf(1): perfect, dOf(2): partial, dOf(3): perfect},
        ),
        (2, 1, 3, 1, 1, 1, 1, 66),
      );
    });

    // Days 1–39 and 91 Perfect, 40–59 completed Minimum Days, the rest
    // partial: 60 full days, 40 of them Perfect.
    final arcB = {
      for (var d = 1; d <= 92; d++)
        dOf(d): (d <= 39 || d == 91)
            ? perfect
            : d <= 59
            ? minimum
            : partial,
    };
    final completed = rollingArc(wed, status: WinterArcStatus.completed);

    test('B: completed, after the end', () {
      expectDays(historyOf(completed, LocalDate(2027, 1, 10), days: arcB), (
        92,
        0,
        92,
        60,
        0,
        40,
        0,
        65,
      ));
    });

    test('C: completed, the date moved back into it', () {
      expectDays(historyOf(completed, LocalDate(2027, 1, 5), days: arcB), (
        90,
        1,
        91,
        59,
        1,
        39,
        1,
        65,
      ));
    });

    final mar1 = LocalDate(2027, 3, 1);
    LocalDate m(int d) => LocalDate(2027, 3, d);
    // Days 1–9: 6 full, 4 of them Perfect; Day 10 not full.
    final arcD = {
      for (var d = 1; d <= 4; d++) m(d): perfect,
      m(5): minimum,
      m(6): minimum,
      for (var d = 7; d <= 10; d++) m(d): partial,
    };

    test('D′: freeze scheduled for tomorrow; D: paused', () {
      expectDays(
        historyOf(
          rollingArc(mar1, freezes: [openFreeze(m(11))]),
          m(10),
          days: arcD,
        ),
        (9, 1, 10, 6, 0, 4, 0, 60),
      );
      expectDays(
        historyOf(
          rollingArc(mar1, freezes: [openFreeze(m(11))]),
          m(15),
          days: arcD,
        ),
        (10, 0, 10, 6, 0, 4, 0, 60),
      );
    });

    final endedE = rollingArc(
      wed,
      status: WinterArcStatus.ended,
      closedOn: dOf(2),
    );
    final arcE = {dOf(1): partial, dOf(2): perfect};

    test('E, F, G: ended on closedOn, later, and rolled back', () {
      expectDays(historyOf(endedE, dOf(2), days: arcE), (
        2,
        0,
        2,
        1,
        0,
        1,
        0,
        50,
      ));
      expectDays(historyOf(endedE, LocalDate(2026, 10, 20), days: arcE), (
        2,
        0,
        2,
        1,
        0,
        1,
        0,
        50,
      ));
      expectDays(historyOf(endedE, dOf(1), days: arcE), (
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
      ));
    });

    test('H: late Seasonal join', () {
      LocalDate o(int d) => LocalDate(2026, 10, d);
      expectDays(
        historyOf(
          seasonalArc(2026, joined: o(18)),
          o(21),
          days: {
            o(18): perfect,
            o(19): partial,
            o(20): perfect,
            o(21): partial,
          },
        ),
        (3, 1, 4, 2, 0, 2, 0, 50),
      );
    });

    test('I: no elapsed day: nothing divided, the review shows none', () {
      final h = historyOf(rollingArc(wed), wed.addDays(-1));
      expectDays(h, (0, 0, 0, 0, 0, 0, 0, 0));
      expect(ArcWeeks.of(h.session, h.today).hasReviewableWeek, isFalse);
    });

    test('J: ended on Day 37 with its Perfect Day counted once (Week 6)', () {
      final closed = dOf(37);
      final s = rollingArc(
        wed,
        status: WinterArcStatus.ended,
        closedOn: closed,
      );
      // 20 full days: Days 18–31 and 37 Perfect would be 15; use Days
      // 24–36 Perfect (13) + 37 Perfect = 14, Days 11–16 Minimum = 6.
      final days = {
        for (var d = 1; d <= 37; d++)
          dOf(d): (d >= 24)
              ? perfect
              : (d >= 11 && d <= 16)
              ? minimum
              : partial,
      };
      final h = historyOf(s, closed, days: days);
      expectDays(h, (37, 0, 37, 20, 0, 14, 0, 54));
      expect(WeeklyReview.fromHistory(h, 6).perfectDays, 2); // 36, 37
    });
  });

  test('property (R3, R9, R13, R17, R18): generated Arcs of every status, '
      'every date: partitions, identities and the strip/Journey agreement', () {
    final generator = HistoryGenerator(20261118);
    final seen = <WinterArcStatus>{};
    var paused = 0;
    var cases = 0;
    for (var i = 0; i < 300; i++) {
      final s = generator.session();
      seen.add(s.status);
      if (s.freezes.isNotEmpty) paused++;
      for (final today in generator.todays(s)) {
        final h = generator.history(s, today);
        checkIdentities(h);
        cases++;
        final journey = h.journey();
        final weeks = ArcWeeks.of(s, today);
        for (final w in weeks.weeks) {
          for (final d in w.days) {
            expect(
              classMatchesJourney(d.dayClass, journey[d.dayNumber - 1]),
              isTrue,
              reason: '$s $today Day ${d.dayNumber} ${d.dayClass}',
            );
          }
        }
      }
    }
    expect(seen, containsAll(WinterArcStatus.values.skip(1)));
    expect(paused, greaterThan(30));
    expect(cases, greaterThan(5000));
  });
}
