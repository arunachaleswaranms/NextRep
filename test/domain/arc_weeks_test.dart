import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/lifecycle_arcs.dart';
import '../support/review_arcs.dart';

/// Phase 12B: the 13 Arc weeks (ARC_MOMENTUM_SPEC §§ 3.2, 12.2, 12.3).
/// Pure; all data synthetic.

List<ArcDayClass> classes(ArcWeek w) => [for (final d in w.days) d.dayClass];
List<ArcWeekStatus> statuses(ArcWeeks w) => [
  for (final week in w.weeks) week.status,
];

void main() {
  final wed = LocalDate(2026, 10, 7); // a Wednesday

  group('week arithmetic', () {
    test('weekOf for the boundary days', () {
      const expected = {
        1: 1,
        7: 1,
        8: 2,
        14: 2,
        15: 3,
        84: 12,
        85: 13,
        91: 13,
        92: 13,
      };
      for (final MapEntry(key: day, value: week) in expected.entries) {
        expect(ArcWeeks.weekOf(day), week, reason: 'Day $day');
      }
    });

    test('exactly 13 weeks: 7 days each, 8 in Week 13 (Day 92 included); '
        'no Week 14', () {
      for (var w = 1; w <= 12; w++) {
        expect(ArcWeeks.firstDayOf(w), 7 * (w - 1) + 1);
        expect(ArcWeeks.lastDayOf(w), 7 * w);
      }
      expect(ArcWeeks.firstDayOf(13), 85);
      expect(ArcWeeks.lastDayOf(13), 92);
      expect(() => ArcWeeks.firstDayOf(14), throwsRangeError);
      expect(() => ArcWeeks.firstDayOf(0), throwsRangeError);
      expect(() => ArcWeeks.weekOf(93), throwsRangeError);
      expect(() => ArcWeeks.weekOf(0), throwsRangeError);

      final weeks = ArcWeeks.of(rollingArc(wed), wed);
      expect(weeks.weeks, hasLength(13));
      final days = [
        for (final w in weeks.weeks)
          for (final d in w.days) d.dayNumber,
      ];
      expect(days, [for (var d = 1; d <= 92; d++) d]);
      expect(weeks.week(13).length, 8);
      expect(weeks.week(13).days.last.dayNumber, 92);
      for (var day = 1; day <= 92; day++) {
        final w = weeks.week(ArcWeeks.weekOf(day));
        expect(w.days.map((d) => d.dayNumber), contains(day));
      }
    });

    test('a Rolling Arc started on a Wednesday runs Wednesday to Tuesday', () {
      final weeks = ArcWeeks.of(rollingArc(wed), wed);
      expect(weeks.week(1).firstDate, wed);
      expect(weeks.week(1).lastDate, LocalDate(2026, 10, 13));
      expect(weeks.week(2).firstDate, LocalDate(2026, 10, 14));
      for (final w in weeks.weeks) {
        expect(w.firstDate!.toLocalDateTime().weekday, DateTime.wednesday);
      }
      // Week 13: Wed 30 Dec 2026 – Wed 6 Jan 2027 (8 days).
      expect(weeks.week(13).firstDate, LocalDate(2026, 12, 30));
      expect(weeks.week(13).lastDate, LocalDate(2027, 1, 6));
    });

    test('Seasonal 2026: Thursday weeks; Week 13 is Thu 24 – Thu 31 Dec', () {
      final s = seasonalArc(2026, joined: LocalDate(2026, 10, 1));
      final weeks = ArcWeeks.of(s, LocalDate(2026, 10, 1));
      expect(weeks.week(1).firstDate, LocalDate(2026, 10, 1));
      expect(weeks.week(1).firstDate!.toLocalDateTime().weekday, 4);
      expect(weeks.week(13).firstDate, LocalDate(2026, 12, 24));
      expect(weeks.week(13).lastDate, LocalDate(2026, 12, 31));
    });

    test('dates come from dateOfDay: a closed pause moves later dates, never '
        'day numbers', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)],
      );
      final weeks = ArcWeeks.of(s, LocalDate(2027, 3, 21));
      for (final w in weeks.weeks) {
        for (final d in w.days) {
          expect(d.date, s.dateOfDay(d.dayNumber));
        }
      }
      // Week 2 = Days 8–14 = 8–10 Mar, then 20–23 Mar.
      final w2 = weeks.week(2);
      expect(w2.firstDate, LocalDate(2027, 3, 8));
      expect(w2.lastDate, LocalDate(2027, 3, 23));
      expect(w2.pausedDaysWithin, 9);
      expect(weeks.week(1).pausedDaysWithin, 0);
      expect(weeks.week(13).length, 8);
      expect(weeks.week(13).lastDate, s.endDate);
    });
  });

  group('day classes and week status (§ 12.3)', () {
    test(
      'Arc start: Day 1 is today; Week 1 in progress with nothing settled',
      () {
        final weeks = ArcWeeks.of(rollingArc(wed), wed);
        expect(classes(weeks.week(1)), [
          ArcDayClass.open,
          for (var i = 0; i < 6; i++) ArcDayClass.upcoming,
        ]);
        expect(weeks.week(1).status, ArcWeekStatus.inProgress);
        expect(statuses(weeks).skip(1), everyElement(ArcWeekStatus.upcoming));
        expect(weeks.reviewableWeeks, [1]);
        expect(weeks.defaultWeek, 1);
      },
    );

    test('mid-Arc: earlier weeks complete, the current in progress, later '
        'upcoming', () {
      final s = rollingArc(wed);
      final today = s.dateOfDay(18)!; // Week 3
      final weeks = ArcWeeks.of(s, today);
      expect(statuses(weeks).take(4), [
        ArcWeekStatus.complete,
        ArcWeekStatus.complete,
        ArcWeekStatus.inProgress,
        ArcWeekStatus.upcoming,
      ]);
      expect(classes(weeks.week(3)), [
        ArcDayClass.settled,
        ArcDayClass.settled,
        ArcDayClass.settled,
        ArcDayClass.open,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
      ]);
      expect(weeks.week(3).settledDates, hasLength(3));
      expect(weeks.week(3).openDay!.dayNumber, 18);
      expect(weeks.reviewableWeeks, [1, 2, 3]);
      expect(weeks.defaultWeek, 3);
      expect(weeks.previousReviewable(3), 2);
      expect(weeks.nextReviewable(3), isNull);
      expect(weeks.nextReviewable(1), 2);
      expect(weeks.previousReviewable(1), isNull);
    });

    test('Day 7 → Day 8: Week 1 becomes complete the moment Week 2 starts', () {
      final s = rollingArc(wed);
      final day7 = ArcWeeks.of(s, s.dateOfDay(7)!);
      expect(day7.week(1).status, ArcWeekStatus.inProgress);
      expect(day7.week(2).status, ArcWeekStatus.upcoming);
      final day8 = ArcWeeks.of(s, s.dateOfDay(8)!);
      expect(day8.week(1).status, ArcWeekStatus.complete);
      expect(day8.week(2).status, ArcWeekStatus.inProgress);
    });

    test('Day 92 open, then the Arc is over: every week complete, Week 13 '
        'final and the default', () {
      final s = rollingArc(wed);
      final d92 = ArcWeeks.of(s, s.dateOfDay(92)!);
      expect(d92.week(13).status, ArcWeekStatus.inProgress);
      expect(d92.week(13).days.last.dayClass, ArcDayClass.open);
      expect(d92.isFinalReview(13), isFalse);

      for (final status in [
        WinterArcStatus.active,
        WinterArcStatus.completed,
      ]) {
        final over = ArcWeeks.of(
          s.copyWith(status: status),
          s.endDate.addDays(1),
        );
        expect(statuses(over), everyElement(ArcWeekStatus.complete));
        expect(over.defaultWeek, 13);
        expect(over.finalWeek, 13);
        expect(over.isFinalReview(13), isTrue);
        expect(over.isFinalReview(12), isFalse);
        expect(over.week(13).settledDates, hasLength(8));
      }
    });

    test('late Seasonal join on Day 18: Weeks 1–2 before joining, Week 3 '
        'starts with 3 neutral days', () {
      final joined = LocalDate(2026, 10, 18);
      final s = seasonalArc(2026, joined: joined);
      final weeks = ArcWeeks.of(s, joined);
      expect(weeks.week(1).status, ArcWeekStatus.beforeJoining);
      expect(weeks.week(2).status, ArcWeekStatus.beforeJoining);
      expect(classes(weeks.week(3)), [
        ArcDayClass.neutral,
        ArcDayClass.neutral,
        ArcDayClass.neutral,
        ArcDayClass.open,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
      ]);
      expect(weeks.week(3).status, ArcWeekStatus.inProgress);
      expect(weeks.joinWeek, 3);
      expect(weeks.reviewableWeeks, [3]);
      // Asking for a week before joining shows the nearest reviewable one.
      expect(weeks.resolve(1), 3);
      expect(weeks.resolve(9), 3);

      final later = ArcWeeks.of(s, LocalDate(2026, 10, 22));
      expect(later.week(3).status, ArcWeekStatus.complete);
      expect(later.week(3).settledDates, hasLength(4));
      expect(later.week(4).status, ArcWeekStatus.inProgress);
    });

    test('before the participation start: no reviewable week; the join week '
        'is upcoming even when today is one of its neutral days', () {
      final rolling = rollingArc(wed);
      final before = ArcWeeks.of(rolling, wed.addDays(-1));
      expect(before.reviewableWeeks, isEmpty);
      expect(before.defaultWeek, isNull);
      expect(before.resolve(1), isNull);
      expect(before.resolve(null), isNull);
      expect(before.week(1).status, ArcWeekStatus.upcoming);

      final joined = LocalDate(2026, 10, 18);
      final seasonal = seasonalArc(2026, joined: joined);
      final rolledBack = ArcWeeks.of(seasonal, LocalDate(2026, 10, 17));
      expect(rolledBack.reviewableWeeks, isEmpty);
      expect(rolledBack.week(3).status, ArcWeekStatus.upcoming);
      expect(rolledBack.week(3).days[2].dayClass, ArcDayClass.neutral);
      expect(rolledBack.week(1).status, ArcWeekStatus.beforeJoining);
    });

    test('paused: the week holding the next challenge day is paused and '
        'reviewable; its unknown dates are upcoming', () {
      final start = LocalDate(2027, 3, 1);
      // Lived Days 1–10 (1–10 Mar), paused from 11 Mar, still open.
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      final weeks = ArcWeeks.of(s, LocalDate(2027, 3, 15));
      expect(weeks.week(1).status, ArcWeekStatus.complete);
      final w2 = weeks.week(2);
      expect(w2.status, ArcWeekStatus.paused);
      expect(classes(w2), [
        ArcDayClass.settled,
        ArcDayClass.settled,
        ArcDayClass.settled,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
      ]);
      expect(w2.days[3].date, isNull, reason: 'Day 11 has no date yet');
      expect(w2.lastDate, isNull);
      expect(w2.openDay, isNull);
      expect(weeks.pausedSince, LocalDate(2027, 3, 11));
      expect(weeks.reviewableWeeks, [1, 2]);
      expect(weeks.defaultWeek, 2);
      expect(statuses(weeks).skip(2), everyElement(ArcWeekStatus.upcoming));
    });

    test('paused at a week boundary: the paused week has no settled day and '
        'is still reviewable', () {
      final start = LocalDate(2027, 3, 1);
      // Lived Days 1–14, paused from 15 Mar.
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 15))],
      );
      final weeks = ArcWeeks.of(s, LocalDate(2027, 3, 20));
      expect(weeks.week(2).status, ArcWeekStatus.complete);
      expect(weeks.week(3).status, ArcWeekStatus.paused);
      expect(weeks.week(3).settledDates, isEmpty);
      expect(weeks.week(3).firstDate, isNull);
      expect(weeks.defaultWeek, 3);
    });

    test('a scheduled freeze changes nothing today; after Resume the week is '
        'in progress again and earlier weeks are identical', () {
      final start = LocalDate(2027, 3, 1);
      final scheduled = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      final plain = rollingArc(start);
      final day10 = LocalDate(2027, 3, 10);
      expect(
        statuses(ArcWeeks.of(scheduled, day10)),
        statuses(ArcWeeks.of(plain, day10)),
      );
      expect(
        classes(ArcWeeks.of(scheduled, day10).week(2)),
        classes(ArcWeeks.of(plain, day10).week(2)),
      );

      final resumed = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)], // resumed 20 Mar
      );
      final after = ArcWeeks.of(resumed, LocalDate(2027, 3, 21));
      expect(after.week(2).status, ArcWeekStatus.inProgress);
      expect(classes(after.week(2)), [
        ArcDayClass.settled, // 8 Mar
        ArcDayClass.settled, // 9 Mar
        ArcDayClass.settled, // 10 Mar
        ArcDayClass.settled, // Day 11 = 20 Mar
        ArcDayClass.open, // Day 12 = 21 Mar
        ArcDayClass.upcoming,
        ArcDayClass.upcoming,
      ]);
      // Week 1 was final before the pause and is identical after it.
      final w1Before = ArcWeeks.of(scheduled, LocalDate(2027, 3, 15)).week(1);
      final w1After = after.week(1);
      expect(w1After.status, w1Before.status);
      expect(
        [for (final d in w1After.days) (d.dayNumber, d.date, d.dayClass)],
        [for (final d in w1Before.days) (d.dayNumber, d.date, d.dayClass)],
      );
    });

    test('a pause inside Week 13 keeps 8 days and moves only later dates', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [closedFreeze(start.addDays(87), 5)], // after Day 87
      );
      final weeks = ArcWeeks.of(s, s.endDate.addDays(1));
      final w13 = weeks.week(13);
      expect(w13.length, 8);
      expect(w13.days.map((d) => d.dayNumber), [
        for (var d = 85; d <= 92; d++) d,
      ]);
      expect(w13.pausedDaysWithin, 5);
      expect(w13.days[2].date, start.addDays(86)); // Day 87, before
      expect(w13.days[3].date, start.addDays(92)); // Day 88, after the pause
      expect(w13.status, ArcWeekStatus.complete);
    });

    test('paused inside Week 13 with an open pause: Week 13 paused', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(start, freezes: [openFreeze(start.addDays(87))]);
      final weeks = ArcWeeks.of(s, start.addDays(100));
      expect(weeks.week(13).status, ArcWeekStatus.paused);
      expect(weeks.week(13).settledDates, hasLength(3)); // Days 85–87
      expect(weeks.defaultWeek, 13);
      expect(weeks.isFinalReview(13), isFalse);
    });

    test('several pauses: day numbers continuous, 92 days in 13 weeks', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [
          closedFreeze(start.addDays(5), 3),
          closedFreeze(start.addDays(20), 10),
          closedFreeze(start.addDays(60), 2),
        ],
      );
      final weeks = ArcWeeks.of(s, s.endDate.addDays(1));
      final dates = [
        for (final w in weeks.weeks)
          for (final d in w.days) d.date!,
      ];
      expect(dates, bruteChallengeDates(s));
      expect(statuses(weeks), everyElement(ArcWeekStatus.complete));
    });

    test('ended Arc: weeks after closedOn are not reached; the closedOn week '
        'is complete (its last day settled on closedOn) and final', () {
      final closed = wed.addDays(36); // Day 37, Week 6
      final s = rollingArc(
        wed,
        status: WinterArcStatus.ended,
        closedOn: closed,
      );
      final onClosedOn = ArcWeeks.of(s, closed);
      expect(onClosedOn.finalWeek, 6);
      expect(
        statuses(onClosedOn).take(6),
        everyElement(ArcWeekStatus.complete),
      );
      expect(
        statuses(onClosedOn).skip(6),
        everyElement(ArcWeekStatus.notReached),
      );
      final w6 = onClosedOn.week(6);
      expect(classes(w6), [
        ArcDayClass.settled, // Day 36
        ArcDayClass.settled, // Day 37 = closedOn = today: settled, not open
        for (var i = 0; i < 5; i++) ArcDayClass.notReached,
      ]);
      expect(w6.openDay, isNull);
      expect(onClosedOn.defaultWeek, 6);
      expect(onClosedOn.isFinalReview(6), isTrue);
      expect(onClosedOn.reviewableWeeks, [1, 2, 3, 4, 5, 6]);
      expect(onClosedOn.resolve(10), 6);

      // Later, before and after the planned last day: the same.
      for (final later in [closed.addDays(1), s.endDate.addDays(30)]) {
        final w = ArcWeeks.of(s, later);
        expect(statuses(w), statuses(onClosedOn));
        expect(classes(w.week(6)), classes(w6));
      }
    });

    test('ended Arc in Week 2, then the date rolls back before closedOn', () {
      final closed = wed.addDays(9); // Day 10
      final s = rollingArc(
        wed,
        status: WinterArcStatus.ended,
        closedOn: closed,
      );
      final back = ArcWeeks.of(s, closed.addDays(-1)); // Day 9
      expect(classes(back.week(2)), [
        ArcDayClass.settled, // Day 8
        ArcDayClass.settled, // Day 9 = today, settled (no open day)
        ArcDayClass.upcoming, // Day 10 = closedOn, after today
        for (var i = 0; i < 4; i++) ArcDayClass.notReached,
      ]);
      expect(back.week(2).status, ArcWeekStatus.complete);
      expect(back.defaultWeek, 2);

      // Rolled back before the closedOn week starts: Week 2 can't be opened.
      final further = ArcWeeks.of(s, wed.addDays(3));
      expect(further.week(2).status, ArcWeekStatus.upcoming);
      expect(further.week(1).status, ArcWeekStatus.complete);
      expect(further.reviewableWeeks, [1]);

      // Before the start: nothing.
      expect(ArcWeeks.of(s, wed.addDays(-1)).reviewableWeeks, isEmpty);
    });

    test('ended on Day 92: final Week 13, no not-reached week', () {
      final s = rollingArc(
        wed,
        status: WinterArcStatus.ended,
        closedOn: WinterArcRules.endDateFor(wed),
      );
      final weeks = ArcWeeks.of(s, s.endDate);
      expect(statuses(weeks), everyElement(ArcWeekStatus.complete));
      expect(weeks.week(13).days.last.dayClass, ArcDayClass.settled);
      expect(weeks.finalWeek, 13);
      expect(weeks.isFinalReview(13), isTrue);
    });

    test('completed Arc after a clock rollback into it: date-driven, one open '
        'day, status stays completed', () {
      final s = rollingArc(wed, status: WinterArcStatus.completed);
      final back = ArcWeeks.of(s, s.dateOfDay(90)!);
      expect(back.week(13).status, ArcWeekStatus.inProgress);
      expect(back.week(13).openDay!.dayNumber, 90);
      expect(back.defaultWeek, 13);
      expect(back.isFinalReview(13), isFalse);
      expect(back.session.status, WinterArcStatus.completed);
    });

    test('a session in setup has no weeks', () {
      expect(
        () => ArcWeeks.of(rollingArc(wed, status: WinterArcStatus.setup), wed),
        throwsArgumentError,
      );
    });
  });

  group('resolving a requested week', () {
    final s = rollingArc(wed);
    final weeks = ArcWeeks.of(s, s.dateOfDay(30)!); // Week 5

    test('missing or outside 1..13 → the default week', () {
      for (final bad in [null, 0, -1, 14, 99, -2147483648]) {
        expect(weeks.resolve(bad), 5, reason: '$bad');
      }
    });

    test('reviewable → itself; upcoming → the nearest reviewable', () {
      for (var w = 1; w <= 5; w++) {
        expect(weeks.resolve(w), w);
      }
      for (var w = 6; w <= 13; w++) {
        expect(weeks.resolve(w), 5);
      }
    });
  });

  test('property: every generated Arc has 13 weeks of challenge days in '
      'order, Week 13 with Day 92, dates from dateOfDay, and a contiguous '
      'reviewable range', () {
    final generator = HistoryGenerator(1203);
    for (var i = 0; i < 400; i++) {
      final s = generator.session();
      for (final today in generator.todays(s)) {
        final weeks = ArcWeeks.of(s, today);
        expect(weeks.weeks, hasLength(13));
        var expectedDay = 1;
        for (final w in weeks.weeks) {
          expect(w.length, w.number == 13 ? 8 : 7);
          for (final d in w.days) {
            expect(d.dayNumber, expectedDay++);
            expect(d.date, s.dateOfDay(d.dayNumber));
            if (d.dayClass == ArcDayClass.settled) {
              expect(w.isReviewable, isTrue, reason: '$s $today');
            }
          }
          if (w.status == ArcWeekStatus.paused) {
            expect(w.openDay, isNull);
          }
        }
        final r = weeks.reviewableWeeks;
        if (r.isNotEmpty) {
          expect(r, [for (var w = r.first; w <= r.last; w++) w]);
          expect(r, contains(weeks.defaultWeek));
          for (var q = -1; q <= 15; q++) {
            expect(r, contains(weeks.resolve(q)));
          }
        } else {
          expect(weeks.defaultWeek, isNull);
        }
        expect(
          weeks.weeks.where((w) => w.openDay != null).length,
          s.isOpenOn(today) ? 1 : 0,
        );
      }
    }
  });
}
