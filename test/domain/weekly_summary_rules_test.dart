import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/review/weekly_summary_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/review/weekly_summary_text.dart';

import '../support/lifecycle_arcs.dart';
import '../support/review_arcs.dart';

/// Phase 12B: the Weekly Review summary (ARC_MOMENTUM_SPEC § 6): the nine
/// kinds in priority order, tense and final-week variants, habit lines,
/// determinism, wording safety and no contradictions. Pure; all synthetic.

final wed = LocalDate(2026, 10, 7);
LocalDate dOf(int day) => wed.addDays(day - 1);

final four = [
  for (final (i, id) in ['a', 'b', 'c', 'd'].indexed)
    namedHabit(id, id.toUpperCase(), order: i),
];

/// Day data with the first [n] of the four habits done.
DayData done(int n, {DayMode mode = DayMode.normal}) =>
    day({for (final h in four.take(n)) h.id}, mode: mode);

/// The review of week [week] of a Rolling Arc from [wed] viewed on Day
/// [today], with [days] by day number (four habits).
WeeklyReview review(
  int today,
  Map<int, DayData> days, {
  int week = 1,
  WinterArcSession? session,
}) => WeeklyReview.fromHistory(
  historyOf(
    session ?? rollingArc(wed),
    dOf(today),
    habits: four,
    days: {for (final MapEntry(:key, :value) in days.entries) dOf(key): value},
  ),
  week,
);

WeeklySummary sum(WeeklyReview r) => WeeklySummaryRules.summarize(r);
String text(WeeklyReview r) => WeeklySummaryText.paragraph(sum(r));

/// Words the review's own copy never uses (spec § 6.1, brief § 14).
final forbidden = RegExp(
  r'\b(fail|failed|failure|failing|missed|miss|lazy|weak|bad|only|poor|'
  r'worst|shame|shameful|disappoint\w*|should have|behind)\b',
  caseSensitive: false,
);

void main() {
  group('the nine kinds, first match wins (§ 6.3)', () {
    test('START: N = 0, first week and a later week', () {
      final first = review(1, {});
      expect(sum(first).kind, WeeklySummaryKind.start);
      expect(
        text(first),
        'Your Arc is just getting started. More days will reveal your '
        'rhythm.',
      );
      final later = review(8, {
        for (var d = 1; d <= 7; d++) d: done(4),
      }, week: 2);
      expect(later.countedDays, 0);
      expect(sum(later).kind, WeeklySummaryKind.start);
      expect(text(later), 'A new week begins today. One habit at a time.');
    });

    test('LOW_DATA: N = 1 and N = 2, in progress', () {
      for (final today in [2, 3]) {
        final r = review(today, {1: done(4), 2: done(4)});
        expect(r.countedDays, today - 1);
        expect(sum(r).kind, WeeklySummaryKind.lowData);
        expect(
          text(r),
          'Just a few days in. Your rhythm will show as the week goes on.',
        );
      }
    });

    test('LOW_DATA complete: a late join\'s short first week', () {
      final joined = LocalDate(2026, 10, 20); // Day 20, Week 3 ends Day 21
      final r = WeeklyReview.fromHistory(
        historyOf(
          seasonalArc(2026, joined: joined),
          LocalDate(2026, 10, 22),
          habits: four,
          days: {joined: done(4), LocalDate(2026, 10, 21): done(4)},
        ),
        3,
      );
      expect(r.status, ArcWeekStatus.complete);
      expect(r.countedDays, 2);
      expect(sum(r).kind, WeeklySummaryKind.lowData);
      expect(text(r), 'A short first week. More days will reveal your rhythm.');
    });

    test('N = 3 with every day full: ALL_FULL (highlights may appear)', () {
      final r = review(4, {1: done(4), 2: done(4), 3: done(4)});
      expect(sum(r).kind, WeeklySummaryKind.allFull);
      expect(
        text(r),
        'Every day so far this week has been a full day. A has been steady so '
        'far: 3 of 3 days.',
      );
    });

    test('ALL_FULL complete, with and without Minimum Days', () {
      final plain = review(8, {for (var d = 1; d <= 7; d++) d: done(4)});
      expect(
        WeeklySummaryText.headline(sum(plain)),
        "Every day this week was a full day. That's real momentum.",
      );
      final withMinimum = review(8, {
        for (var d = 1; d <= 7; d++)
          d: done(4, mode: d == 3 ? DayMode.minimum : DayMode.normal),
      });
      expect(sum(withMinimum).kind, WeeklySummaryKind.allFull);
      expect(
        WeeklySummaryText.headline(sum(withMinimum)),
        'Every day this week was a full day, Minimum Days included. '
        "That's real momentum.",
      );
    });

    test('HIGH at exactly 80%; 79% (floored) is not HIGH', () {
      // 16 of 20 = 80%.
      final eighty = review(6, {
        1: done(4),
        2: done(3),
        3: done(3),
        4: done(3),
        5: done(3),
      });
      expect(eighty.completionPercent, 80);
      expect(sum(eighty).kind, WeeklySummaryKind.high);
      expect(
        WeeklySummaryText.headline(sum(eighty)),
        "You've kept showing up so far this week. Keep that momentum going.",
      );
      // 19 of 24 = 79.17% → 79: STEADY.
      final below = review(7, {
        1: done(4),
        for (var d = 2; d <= 6; d++) d: done(3),
      });
      expect(below.completionPercent, 79);
      expect(sum(below).kind, WeeklySummaryKind.steady);
    });

    test('HIGH complete', () {
      final r = review(8, {
        1: done(4),
        for (var d = 2; d <= 7; d++) d: done(3),
      });
      expect(r.completionPercent, 78);
      final high = review(8, {
        1: done(4),
        2: done(4),
        for (var d = 3; d <= 7; d++) d: done(3),
      });
      expect(high.completionPercent, 82);
      expect(sum(high).kind, WeeklySummaryKind.high);
      expect(
        WeeklySummaryText.headline(sum(high)),
        'You kept showing up this week. Keep that momentum going.',
      );
    });

    test('RECOVERY: a day under half, then a full day; before MINIMUM', () {
      final r = review(8, {
        1: done(0),
        2: done(4, mode: DayMode.minimum),
        3: done(2),
        4: done(2),
        5: done(2),
        6: done(2),
        7: done(2),
      });
      expect(r.minimumDaysCompleted, 1);
      expect(sum(r).kind, WeeklySummaryKind.recovery);
      expect(
        WeeklySummaryText.headline(sum(r)),
        'You found your way back this week. Every return matters.',
      );
      // A full day before the hard day is not a recovery.
      final notAfter = review(8, {
        1: done(4),
        2: done(0),
        for (var d = 3; d <= 7; d++) d: done(2),
      });
      expect(sum(notAfter).kind, isNot(WeeklySummaryKind.recovery));
    });

    test('MINIMUM: a completed Minimum Day without a recovery', () {
      final r = review(5, {
        1: done(4, mode: DayMode.minimum),
        2: done(1),
        3: done(1),
        4: done(1),
      });
      expect(r.completionPercent, 43);
      expect(sum(r).kind, WeeklySummaryKind.minimum);
      expect(
        WeeklySummaryText.headline(sum(r)),
        'On harder days you chose a Minimum Day and still showed up.',
      );
      // A partial Minimum Day is chosen, not completed: not MINIMUM.
      final partial = review(5, {
        1: done(3, mode: DayMode.minimum),
        2: done(1),
        3: done(1),
        4: done(1),
      });
      expect(partial.minimumDaysChosen, 1);
      expect(partial.minimumDaysCompleted, 0);
      expect(sum(partial).kind, WeeklySummaryKind.some);
    });

    test('STEADY at exactly 50%; SOME below', () {
      final half = review(5, {1: done(2), 2: done(2), 3: done(2), 4: done(2)});
      expect(half.completionPercent, 50);
      expect(sum(half).kind, WeeklySummaryKind.steady);
      expect(
        WeeklySummaryText.headline(sum(half)),
        'You completed at least half of your habits so far this week. Small '
        'steps add up.',
      );
      final under = review(5, {1: done(2), 2: done(2), 3: done(2), 4: done(1)});
      expect(under.completionPercent, 43);
      expect(sum(under).kind, WeeklySummaryKind.some);
      expect(
        WeeklySummaryText.headline(sum(under)),
        "This week has had its challenges, and you're still making progress.",
      );
    });

    test('STEADY and SOME complete', () {
      final steady = review(8, {for (var d = 1; d <= 7; d++) d: done(2)});
      expect(
        WeeklySummaryText.headline(sum(steady)),
        'You completed at least half of your habits this week. Small steps '
        'add up.',
      );
      final some = review(8, {for (var d = 1; d <= 7; d++) d: done(1)});
      expect(sum(some).kind, WeeklySummaryKind.some);
      expect(
        WeeklySummaryText.headline(sum(some)),
        'This week had its challenges, and you still made progress. Next '
        'week is a fresh start.',
      );
    });

    test('QUIET, complete and in progress', () {
      final complete = review(8, {});
      expect(sum(complete).kind, WeeklySummaryKind.quiet);
      expect(
        text(complete),
        "This week was quiet. Whenever you're ready, one habit is a good "
        'place to start.',
      );
      final running = review(5, {});
      expect(
        text(running),
        'A quiet start to the week. One habit is a good place to begin.',
      );
    });

    test('with no opportunity there is no percentage: HIGH and STEADY never '
        'match', () {
      final r = WeeklyReview.fromHistory(
        historyOf(
          rollingArc(wed),
          dOf(8),
          habits: [namedHabit('a', 'A', order: 0)],
          revisions: [
            HabitRevision(
              habitId: 'a',
              effectiveFrom: wed,
              config: const HabitConfig(
                target: 1,
                minimumTarget: 1,
                enabled: false,
              ),
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
        1,
      );
      expect(r.completionPercent, isNull);
      expect(sum(r).kind, WeeklySummaryKind.quiet);
    });
  });

  group('spec worked examples', () {
    test('example 1 (complete): RECOVERY with both habit lines', () {
      final r = WeeklyReview.fromHistory(
        historyOf(
          rollingArc(wed),
          dOf(8),
          days: {
            dOf(1): day(allFive),
            dOf(2): day({'water', 'workout', 'sleep', 'junk'}),
            dOf(3): day(allFive, mode: DayMode.minimum),
            dOf(4): day({}),
            dOf(5): day({'water', 'workout', 'junk'}),
            dOf(6): day(allFive),
            dOf(7): day({'water', 'junk'}, mode: DayMode.minimum),
          },
        ),
        1,
      );
      expect(
        text(r),
        'You found your way back this week. Every return matters. Water was a '
        'steady part of your week: 6 of 7 days. Reading could use a little '
        'more attention next week.',
      );
    });

    test('example 2 (in progress): HIGH with Most consistent', () {
      final s = seasonalArc(2026, joined: LocalDate(2026, 10, 1));
      LocalDate o(int d) => LocalDate(2026, 10, d);
      final r = WeeklyReview.fromHistory(
        historyOf(
          s,
          o(18),
          days: {
            o(15): day(allFive),
            o(16): day({'water', 'workout', 'sleep', 'junk'}),
            o(17): day(allFive),
            o(18): day({'water', 'workout'}),
          },
        ),
        3,
      );
      expect(
        text(r),
        "You've kept showing up so far this week. Keep that momentum going. "
        'Water has been steady so far: 3 of 3 days.',
      );
    });

    test('example 3: late join START (first week), then LOW_DATA', () {
      final joined = LocalDate(2026, 10, 18);
      final s = seasonalArc(2026, joined: joined);
      WeeklyReview on(LocalDate t) => WeeklyReview.fromHistory(
        historyOf(s, t, days: {joined: day(allFive)}),
        3,
      );
      expect(
        text(on(joined)),
        'Your Arc is just getting started. More days will reveal your '
        'rhythm.',
      );
      expect(sum(on(LocalDate(2026, 10, 19))).kind, WeeklySummaryKind.lowData);
    });
  });

  group('final weeks (§ 6.3 final variants, § 12.3)', () {
    final completed = rollingArc(wed, status: WinterArcStatus.completed);
    final over = completed.endDate.addDays(1);

    WeeklyReview week13(
      WinterArcSession s,
      LocalDate today,
      Map<int, DayData> days,
    ) => WeeklyReview.fromHistory(
      historyOf(
        s,
        today,
        habits: four,
        days: {
          for (final MapEntry(:key, :value) in days.entries) dOf(key): value,
        },
      ),
      13,
    );

    test('completed Week 13: HIGH, SOME and QUIET final wording', () {
      final high = week13(completed, over, {
        85: done(4),
        86: done(4),
        for (var d = 87; d <= 92; d++) d: done(3),
      });
      expect(high.isFinalReview, isTrue);
      expect(
        WeeklySummaryText.headline(sum(high)),
        'You kept showing up all the way to the summit.',
      );
      final some = week13(completed, over, {
        for (var d = 85; d <= 92; d++) d: done(1),
      });
      expect(
        WeeklySummaryText.headline(sum(some)),
        'This week had its challenges, and you still made progress.',
      );
      final quiet = week13(completed, over, {});
      expect(
        WeeklySummaryText.headline(sum(quiet)),
        'The final week was quiet. Reaching the end of an Arc still matters.',
      );
    });

    test('final Room to grow wording; Most consistent as complete', () {
      final r = week13(completed, over, {
        for (var d = 85; d <= 92; d++)
          d: day({'a', 'b', 'c', if (d == 85) 'd'}),
      });
      expect(WeeklySummaryText.habitLines(sum(r)), [
        'A was a steady part of your week: 8 of 8 days.',
        'D had the most room to grow this week.',
      ]);
    });

    test('an in-progress Week 13 keeps the in-progress wording', () {
      final active = rollingArc(wed);
      final r = week13(active, dOf(90), {
        85: done(4),
        86: done(4),
        87: done(3),
        88: done(3),
        89: done(3),
        90: done(1),
      });
      expect(r.status, ArcWeekStatus.inProgress);
      expect(r.isFinalReview, isFalse);
      final s = sum(r);
      expect(s.kind, WeeklySummaryKind.high);
      expect(
        WeeklySummaryText.headline(s),
        "You've kept showing up so far this week. Keep that momentum going.",
      );
    });

    test('an ended Arc\'s last week (Week 2) is final; HIGH never claims the '
        'summit; LOW_DATA uses the final wording', () {
      final ended = rollingArc(
        wed,
        status: WinterArcStatus.ended,
        closedOn: dOf(12),
      );
      final r = WeeklyReview.fromHistory(
        historyOf(
          ended,
          dOf(20),
          habits: four,
          days: {
            for (var d = 8; d <= 12; d++) dOf(d): d <= 9 ? done(4) : done(3),
          },
        ),
        2,
      );
      expect(r.isFinalReview, isTrue);
      final s = sum(r);
      expect(s.finalWeek, isTrue);
      expect(s.arcEnded, isTrue);
      expect(s.kind, WeeklySummaryKind.high);
      expect(
        WeeklySummaryText.headline(s),
        'You kept showing up this week. Keep that momentum going.',
      );
      expect(text(r), isNot(contains('summit')));

      final short = WeeklyReview.fromHistory(
        historyOf(
          rollingArc(wed, status: WinterArcStatus.ended, closedOn: dOf(9)),
          dOf(9),
          habits: four,
          days: {dOf(8): done(4), dOf(9): done(4)},
        ),
        2,
      );
      expect(short.countedDays, 2);
      expect(short.today, isNull);
      expect(
        text(short),
        'A short final week. Every day you showed up counts.',
      );
    });

    test('a paused week with nothing settled says so, not "begins today"', () {
      final mar1 = LocalDate(2027, 3, 1);
      final s = rollingArc(mar1, freezes: [openFreeze(LocalDate(2027, 3, 15))]);
      final r = WeeklyReview.fromHistory(
        historyOf(s, LocalDate(2027, 3, 18), habits: four),
        3,
      );
      expect(sum(r).kind, WeeklySummaryKind.start);
      expect(sum(r).tense, WeeklySummaryTense.inProgress);
      expect(text(r), 'This week begins when you resume.');
    });

    test('a paused week with settled days uses the in-progress wording', () {
      final mar1 = LocalDate(2027, 3, 1);
      final s = rollingArc(mar1, freezes: [openFreeze(LocalDate(2027, 3, 12))]);
      final r = WeeklyReview.fromHistory(
        historyOf(
          s,
          LocalDate(2027, 3, 18),
          habits: four,
          days: {for (var d = 1; d <= 11; d++) LocalDate(2027, 3, d): done(1)},
        ),
        2,
      );
      expect(r.countedDays, 4);
      expect(
        WeeklySummaryText.headline(sum(r)),
        "This week has had its challenges, and you're still making progress.",
      );
      expect(WeeklySummaryText.habitLines(sum(r)), [
        'A has been steady so far: 4 of 4 days.',
        'B could use a little attention in the days ahead.',
      ]);
    });
  });

  group('determinism and wording safety (§ 6.1)', () {
    test('the same review gives the same summary, 100 times', () {
      final generator = HistoryGenerator(4242);
      for (var i = 0; i < 20; i++) {
        final s = generator.session();
        final today = generator.todays(s).last;
        final h = generator.history(s, today);
        for (final r in allReviews(h)) {
          final first = WeeklySummaryRules.summarize(r);
          final firstText = WeeklySummaryText.paragraph(first);
          for (var run = 0; run < 100; run++) {
            final again = WeeklySummaryRules.summarize(r);
            expect(again, first);
            expect(WeeklySummaryText.paragraph(again), firstText);
          }
        }
      }
    });

    test('no authored sentence uses a judgemental word, and only a '
        'completed (not ended) Arc mentions the summit', () {
      final tally = HabitWeekTally(
        habit: namedHabit('h', 'Habit', order: 0),
        displayIndex: 0,
        applicableDays: 7,
        completedDays: 3,
      );
      var checked = 0;
      for (final kind in WeeklySummaryKind.values) {
        for (final tense in WeeklySummaryTense.values) {
          for (final flags in Iterable.generate(32)) {
            final s = WeeklySummary(
              kind: kind,
              tense: tense,
              finalWeek: flags & 1 != 0,
              firstWeek: flags & 2 != 0,
              paused: flags & 4 != 0,
              arcEnded: flags & 8 != 0,
              minimumIncluded: flags & 16 != 0,
              mostConsistent: tally,
              roomToGrow: tally,
            );
            final words = WeeklySummaryText.paragraph(s);
            // The user's habit title is not authored copy.
            final authored = words.replaceAll('Habit', '');
            expect(forbidden.hasMatch(authored), isFalse, reason: words);
            if (s.arcEnded) {
              expect(words.toLowerCase(), isNot(contains('summit')));
            }
            checked++;
          }
        }
      }
      expect(checked, 9 * 2 * 32);
    });
  });

  group('no contradictions (§ 6.4)', () {
    /// The kind from the spec's table, written independently.
    WeeklySummaryKind oracle(WeeklyReview r) {
      final n = r.countedDays;
      final h = r.habitOpportunities;
      final c = r.completedHabitDays;
      final pct = h == 0 ? null : 100 * c ~/ h;
      if (n == 0) return WeeklySummaryKind.start;
      if (n <= 2) return WeeklySummaryKind.lowData;
      if (r.fullDays == n) return WeeklySummaryKind.allFull;
      if (pct != null && pct >= 80) return WeeklySummaryKind.high;
      final days = r.dailyCompletion;
      for (var i = 0; i < days.length; i++) {
        for (var j = i + 1; j < days.length; j++) {
          if (2 * days[i].$1 < days[i].$2 &&
              days[j].$2 > 0 &&
              days[j].$1 == days[j].$2) {
            return WeeklySummaryKind.recovery;
          }
        }
      }
      if (r.minimumDaysCompleted >= 1) return WeeklySummaryKind.minimum;
      if (pct != null && pct >= 50) return WeeklySummaryKind.steady;
      if (c >= 1) return WeeklySummaryKind.some;
      return WeeklySummaryKind.quiet;
    }

    void check(WeeklyReview r) {
      final s = WeeklySummaryRules.summarize(r);
      expect(s.kind, oracle(r));
      switch (s.kind) {
        case WeeklySummaryKind.allFull:
          expect(s.roomToGrow, isNull);
        case WeeklySummaryKind.quiet ||
            WeeklySummaryKind.start ||
            WeeklySummaryKind.lowData:
          expect(s.mostConsistent, isNull);
          expect(s.roomToGrow, isNull);
        case WeeklySummaryKind.high:
          expect(r.completionPercent, greaterThanOrEqualTo(80));
        case WeeklySummaryKind.steady:
          expect(r.completionPercent, inInclusiveRange(50, 79));
        case WeeklySummaryKind.minimum:
          expect(r.minimumDaysCompleted, greaterThanOrEqualTo(1));
        case WeeklySummaryKind.some:
          expect(r.completedHabitDays, greaterThanOrEqualTo(1));
        case WeeklySummaryKind.recovery:
          break;
      }
      if (s.mostConsistent case final best?) {
        expect(best.habit.id, isNot(s.roomToGrow?.habit.id));
      }
    }

    test('exhaustive over every 3-day, 3-habit week (in progress)', () {
      final three = four.take(3).toList();
      // 2^3 completion patterns × 2 modes per day = 16; 16^3 weeks.
      DayData option(int o) => day({
        for (final (i, h) in three.indexed)
          if (o & (1 << i) != 0) h.id,
      }, mode: o & 8 != 0 ? DayMode.minimum : DayMode.normal);
      var count = 0;
      for (var a = 0; a < 16; a++) {
        for (var b = 0; b < 16; b++) {
          for (var c = 0; c < 16; c++) {
            final r = WeeklyReview.fromHistory(
              historyOf(
                rollingArc(wed),
                dOf(4),
                habits: three,
                days: {dOf(1): option(a), dOf(2): option(b), dOf(3): option(c)},
              ),
              1,
            );
            expect(r.countedDays, 3);
            check(r);
            count++;
          }
        }
      }
      expect(count, 4096);
    });

    test('generated weeks of every status and length', () {
      final generator = HistoryGenerator(606);
      for (var i = 0; i < 150; i++) {
        final s = generator.session();
        for (final today in generator.todays(s)) {
          for (final r in allReviews(generator.history(s, today))) {
            if (r.week.isReviewable) check(r);
          }
        }
      }
    });
  });
}
