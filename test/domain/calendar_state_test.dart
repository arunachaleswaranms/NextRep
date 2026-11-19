import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/theme/winter_tokens.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/arc_calendar.dart';
import 'package:nextrep/domain/journey/arc_milestones.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/journey/journey_overview.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/journey/calendar_labels.dart';
import 'package:nextrep/features/journey/widgets/calendar_day_cell.dart';
import 'package:nextrep/features/journey/widgets/journey_day_style.dart';
import 'package:nextrep/features/review/review_labels.dart';

import '../support/lifecycle_arcs.dart';
import '../support/review_arcs.dart';

/// Phase 12C: the Arc Consistency Calendar's model and wording
/// (ARC_MOMENTUM_SPEC §§ 7, 8.3, 12.2–12.4; K1, K2, K5, K7; PHASE_12A
/// § L2). Pure; all data synthetic.

ArcCalendar calendarOf(ArcHistory h) =>
    ArcCalendar.of(JourneyOverview.fromHistory(h));

WinterArcSession valid(WinterArcSession s) {
  expect(WinterArcRules.problemWith(s), isNull, reason: '$s');
  return s;
}

List<int> dayNumbers(CalendarWeek b) => [for (final d in b.days) d.dayNumber];

/// The block's entries as day numbers, with `0` for a pause row.
List<int> layout(CalendarWeek b) => [
  for (final e in b.entries)
    switch (e) {
      CalendarDayEntry(:final day) => day.dayNumber,
      CalendarPauseEntry() => 0,
    },
];

/// WCAG 2 contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final wed = LocalDate(2026, 10, 7);

  group('92 cells in 13 week blocks (K1)', () {
    test('Weeks 1–12 hold 7 days, Week 13 holds 8 with Day 92; no Week '
        '14; every day exactly once, in Arc order', () {
      final c = calendarOf(historyOf(valid(rollingArc(wed)), wed));
      expect(c.blocks, hasLength(13));
      for (var w = 1; w <= 12; w++) {
        expect(dayNumbers(c.block(w)), [
          for (var d = 7 * (w - 1) + 1; d <= 7 * w; d++) d,
        ]);
      }
      expect(dayNumbers(c.block(13)), [85, 86, 87, 88, 89, 90, 91, 92]);
      expect(c.days.map((d) => d.dayNumber), [for (var d = 1; d <= 92; d++) d]);
      expect(() => c.block(14), throwsRangeError);
      expect(() => c.block(0), throwsRangeError);
      expect(c.pauses, isEmpty);
    });

    test('a Journey that is not 92 days, or of another date, is refused', () {
      final h = historyOf(valid(rollingArc(wed)), wed);
      final j = JourneyOverview.fromHistory(h);
      expect(
        () => ArcCalendar.of(j, weeks: ArcWeeks.of(h.session, wed.addDays(1))),
        throwsArgumentError,
      );
    });

    test('Seasonal 2026: Day 1 is Thursday 1 Oct; weeks run Thursday to '
        'Wednesday; Week 13 is 24–31 Dec', () {
      final s = valid(seasonalArc(2026, joined: LocalDate(2026, 10, 1)));
      final c = calendarOf(historyOf(s, LocalDate(2026, 10, 20)));
      expect(c.days.first.date, LocalDate(2026, 10, 1));
      for (final b in c.blocks) {
        expect(b.week.firstDate!.toLocalDateTime().weekday, DateTime.thursday);
      }
      expect(calendarWeekRange(c.block(1).week), '1–7 Oct');
      expect(calendarWeekRange(c.block(5).week), '29 Oct – 4 Nov');
      expect(calendarWeekRange(c.block(13).week), '24–31 Dec');
    });

    test('a Rolling Arc keeps its own Day 1 and its headings cross the '
        'year with the year on both sides', () {
      final start = LocalDate(2026, 12, 1);
      final c = calendarOf(historyOf(valid(rollingArc(start)), start));
      expect(c.days.first.date, start);
      expect(calendarWeekRange(c.block(4).week), '22–28 Dec');
      expect(calendarWeekRange(c.block(5).week), '29 Dec 2026 – 4 Jan 2027');
      expect(calendarWeekRange(c.block(6).week), '5–11 Jan');
      expect(calendarWeekRange(c.block(9).week), '26 Jan – 1 Feb');
    });

    test('leap years and daylight saving: dates are consecutive local '
        'days', () {
      for (final start in [
        LocalDate(2028, 2, 24), // 29 Feb 2028 in Week 1
        LocalDate(2026, 3, 1), // US and EU clock changes in March
        LocalDate(2026, 10, 20), // EU and US changes in Oct / Nov
      ]) {
        final c = calendarOf(historyOf(valid(rollingArc(start)), start));
        final dates = [for (final d in c.days) d.date!];
        for (var i = 1; i < dates.length; i++) {
          expect(dates[i - 1].daysUntil(dates[i]), 1, reason: '$start #$i');
        }
      }
      final leap = calendarOf(
        historyOf(rollingArc(LocalDate(2028, 2, 24)), LocalDate(2028, 2, 24)),
      );
      expect(
        leap.block(1).days.map((d) => d.date),
        contains(LocalDate(2028, 2, 29)),
      );
      expect(calendarWeekRange(leap.block(1).week), '24 Feb – 1 Mar');
    });
  });

  group('the Journey\'s own states (K1, K2)', () {
    test('every cell is the Journey\'s JourneyDay, by identity', () {
      final s = valid(rollingArc(wed));
      final h = historyOf(
        s,
        wed.addDays(9),
        days: {
          wed: day(allFive, xp: 120),
          wed.addDays(1): day({
            'water',
            'workout',
            'reading',
            'sleep',
            'junk',
          }, mode: DayMode.minimum),
          wed.addDays(2): day({'water'}),
          wed.addDays(3): day({'water'}, mode: DayMode.minimum),
          wed.addDays(5): day(const {}, mode: DayMode.minimum),
          wed.addDays(9): day(allFive),
        },
      );
      final j = JourneyOverview.fromHistory(h);
      final c = ArcCalendar.of(j);
      final cells = c.days.toList();
      for (var i = 0; i < 92; i++) {
        expect(identical(cells[i].journeyDay, j.days[i]), isTrue);
      }
      JourneyDayState stateOf(int d) => cells[d - 1].state;
      expect(stateOf(1), JourneyDayState.perfect);
      expect(stateOf(2), JourneyDayState.minimumComplete);
      expect(stateOf(3), JourneyDayState.partial);
      expect(stateOf(4), JourneyDayState.minimumPartial);
      expect(stateOf(5), JourneyDayState.missed);
      // A Minimum Day with no progress shares the no-progress state and
      // keeps its stored Minimum mode.
      expect(stateOf(6), JourneyDayState.missed);
      expect(cells[5].record!.mode, DayMode.minimum);
      // Today is Perfect: it keeps its outcome and is also today.
      expect(stateOf(10), JourneyDayState.perfect);
      expect(cells[9].isToday, isTrue);
      expect(cells.where((d) => d.isToday), hasLength(1));
      expect(stateOf(11), JourneyDayState.future);
      expect(cells[10].isInteractive, isFalse);
      expect(cells[9].isInteractive, isTrue);
      expect(cells[4].isInteractive, isTrue);
    });

    test('a completed Minimum Day today keeps minimumComplete with the '
        'Today flag; a plain today is "today"', () {
      final s = valid(rollingArc(wed));
      final minimum = calendarOf(
        historyOf(s, wed, days: {wed: day(allFive, mode: DayMode.minimum)}),
      ).days.first;
      expect(minimum.state, JourneyDayState.minimumComplete);
      expect(minimum.isToday, isTrue);
      final plain = calendarOf(
        historyOf(
          s,
          wed,
          days: {
            wed: day({'water'}),
          },
        ),
      ).days.first;
      expect(plain.state, JourneyDayState.today);
      expect(plain.isToday, isTrue);
    });

    test('goal changes don\'t alter past cells', () {
      final s = valid(rollingArc(wed));
      final days = {
        wed: day({'water'}),
        wed.addDays(1): day(allFive),
      };
      final before = calendarOf(historyOf(s, wed.addDays(5), days: days));
      final after = calendarOf(
        historyOf(
          s,
          wed.addDays(5),
          days: days,
          revisions: [
            HabitRevision(
              habitId: 'water',
              effectiveFrom: wed.addDays(5),
              config: const HabitConfig(
                target: 20,
                minimumTarget: 10,
                enabled: true,
              ),
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );
      for (var d = 0; d < 5; d++) {
        expect(after.days.elementAt(d).state, before.days.elementAt(d).state);
      }
    });
  });

  group('weekly full-day counts: the Weekly Review\'s meaning', () {
    test('an in-progress week counts settled days only; today, upcoming '
        'and neutral days are not counted', () {
      final s = valid(seasonalArc(2026, joined: LocalDate(2026, 10, 18)));
      final today = LocalDate(2026, 10, 20);
      final c = calendarOf(
        historyOf(
          s,
          today,
          days: {
            LocalDate(2026, 10, 18): day(allFive),
            LocalDate(2026, 10, 19): day({'water'}),
            today: day(allFive),
          },
        ),
      );
      final week3 = c.block(3);
      expect(week3.status, ArcWeekStatus.inProgress);
      expect(week3.countedDays, 2);
      expect(week3.fullDays, 1);
      expect(
        calendarWeekHeading(week3),
        'Week 3 · 15–21 Oct · 1 of 2 days full · This week',
      );
      expect(
        calendarWeekHeadingLabel(week3),
        'Week 3 of 13, 15 to 21 October, 1 of 2 days full, this week. '
        'Opens the week review.',
      );
      expect(c.block(1).status, ArcWeekStatus.beforeJoining);
      expect(
        calendarWeekHeading(c.block(1)),
        'Week 1 · 1–7 Oct · Before you '
        'joined',
      );
      expect(
        calendarWeekHeadingLabel(c.block(2)),
        'Week 2 of 13, 8 to 14 October, before you joined.',
      );
      expect(calendarWeekHeading(c.block(4)), 'Week 4 · 22–28 Oct · Upcoming');
      expect(c.block(4).countedDays, 0);
    });

    test('a week starting today has no finished day yet', () {
      final s = valid(rollingArc(wed));
      final c = calendarOf(historyOf(s, wed.addDays(7)));
      expect(
        calendarWeekHeading(c.block(2)),
        'Week 2 · 14–20 Oct · No finished days yet · This week',
      );
      expect(c.block(1).status, ArcWeekStatus.complete);
      expect(
        calendarWeekHeading(c.block(1)),
        'Week 1 · 7–13 Oct · 0 of 7 days full',
      );
    });

    test('equals the Weekly Review\'s counted and full days for every week '
        'of generated Arcs', () {
      final generator = HistoryGenerator(1219);
      for (var i = 0; i < 60; i++) {
        final s = generator.session();
        for (final today in generator.todays(s)) {
          final h = generator.history(s, today);
          final c = calendarOf(h);
          for (final b in c.blocks) {
            final review = WeeklyReview.fromHistory(
              h,
              b.number,
              weeks: c.weeks,
            );
            expect(b.countedDays, review.countedDays, reason: '$s $today');
            expect(b.fullDays, review.fullDays, reason: '$s $today');
          }
        }
      }
    });
  });

  group('late Seasonal join', () {
    test('Days 1–17 neutral, Weeks 1–2 before joining, Week 3 mixed; '
        'neutral days open the note and never count', () {
      final s = valid(seasonalArc(2026, joined: LocalDate(2026, 10, 18)));
      final c = calendarOf(historyOf(s, LocalDate(2026, 10, 25)));
      for (final d in c.days.take(17)) {
        expect(
          d.state,
          JourneyDayState.notJoined,
          reason: 'Day ${d.dayNumber}',
        );
        expect(d.isInteractive, isTrue);
        expect(d.isSettled, isFalse);
      }
      expect(c.days.elementAt(17).state, isNot(JourneyDayState.notJoined));
      expect(c.block(3).days.map((d) => d.state).toSet(), {
        JourneyDayState.notJoined,
        JourneyDayState.missed,
      });
      expect(
        calendarDayLabel(c.days.elementAt(7).journeyDay),
        'Day 8, Thursday 8 October. Before you joined this Seasonal Winter '
        'Arc.',
      );
      expect(c.initialWeek, 4);
    });

    test('before the join date nothing is reviewable; the calendar opens on '
        'the join week', () {
      final s = valid(seasonalArc(2026, joined: LocalDate(2026, 10, 18)));
      final c = calendarOf(historyOf(s, LocalDate(2026, 10, 17)));
      expect(c.weeks.hasReviewableWeek, isFalse);
      expect(c.blocks.where((b) => b.isReviewable), isEmpty);
      expect(c.initialWeek, 3);
      final rolling = valid(rollingArc(wed));
      expect(calendarOf(historyOf(rolling, wed.addDays(-3))).initialWeek, 1);
    });
  });

  group('initial week', () {
    test('in progress, paused, completed (13) and ended (closedOn week)', () {
      final start = LocalDate(2027, 3, 1);
      expect(
        calendarOf(historyOf(rollingArc(start), start.addDays(30))).initialWeek,
        5,
      );
      final paused = valid(
        rollingArc(start, freezes: [openFreeze(LocalDate(2027, 3, 11))]),
      );
      expect(
        calendarOf(historyOf(paused, LocalDate(2027, 3, 15))).initialWeek,
        2,
      );
      final completed = valid(
        rollingArc(start, status: WinterArcStatus.completed),
      );
      expect(
        calendarOf(historyOf(completed, start.addDays(200))).initialWeek,
        13,
      );
      final ended = valid(
        rollingArc(
          start,
          status: WinterArcStatus.ended,
          closedOn: start.addDays(41), // Day 42, Week 6
        ),
      );
      expect(calendarOf(historyOf(ended, start.addDays(60))).initialWeek, 6);
    });
  });

  group('pauses (§ 12.4, K7)', () {
    final start = LocalDate(2027, 3, 1); // a Monday

    test('a resumed pause is one row after the last day before it; day '
        'numbers continue; no paused date is a cell', () {
      final s = valid(
        rollingArc(start, freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)]),
      );
      final c = calendarOf(historyOf(s, LocalDate(2027, 4, 1)));
      expect(layout(c.block(2)), [8, 9, 10, 0, 11, 12, 13, 14]);
      expect(c.pauses, hasLength(1));
      expect(calendarPauseText(c.pauses.single), 'Paused 11–19 Mar · 9 days');
      expect(c.pauses.single.lastDate, LocalDate(2027, 3, 19));
      expect(c.days.elementAt(9).date, LocalDate(2027, 3, 10));
      expect(c.days.elementAt(10).date, LocalDate(2027, 3, 20));
      for (final d in c.days) {
        expect(s.isFrozenOn(d.date!), isFalse, reason: 'Day ${d.dayNumber}');
      }
      expect(c.days, hasLength(92));
      expect(calendarWeekRange(c.block(2).week), '8–23 Mar');
    });

    test('a pause between two weeks ends the earlier block, once', () {
      // Day 7 is 7 Mar; paused 8–10 Mar; Day 8 is 11 Mar.
      final s = valid(
        rollingArc(start, freezes: [closedFreeze(LocalDate(2027, 3, 8), 3)]),
      );
      final c = calendarOf(historyOf(s, LocalDate(2027, 4, 1)));
      expect(layout(c.block(1)), [1, 2, 3, 4, 5, 6, 7, 0]);
      expect(layout(c.block(2)), [8, 9, 10, 11, 12, 13, 14]);
      expect(c.block(2).week.firstDate, LocalDate(2027, 3, 11));
      expect([for (final b in c.blocks) ...b.pauses], hasLength(1));
    });

    test('a pause inside Week 13 keeps its 8 days', () {
      final from = start.addDays(88); // the day after Day 88
      final s = valid(rollingArc(start, freezes: [closedFreeze(from, 5)]));
      final c = calendarOf(historyOf(s, start.addDays(120)));
      expect(layout(c.block(13)), [85, 86, 87, 88, 0, 89, 90, 91, 92]);
      expect(c.block(13).days, hasLength(8));
      expect(c.days.last.date, start.addDays(96));
    });

    test('several pauses: each row once, chronological, with its own '
        'count; the year is named when a pause crosses it', () {
      final s = valid(
        rollingArc(
          LocalDate(2026, 11, 1),
          freezes: [
            closedFreeze(LocalDate(2026, 11, 5), 1),
            closedFreeze(LocalDate(2026, 12, 30), 7),
            closedFreeze(LocalDate(2027, 1, 20), 14),
          ],
        ),
      );
      final c = calendarOf(historyOf(s, LocalDate(2027, 6, 1)));
      expect(c.pauses.map(calendarPauseText), [
        'Paused 5 Nov · 1 day',
        'Paused 30 Dec 2026 – 5 Jan 2027 · 7 days',
        'Paused 20 Jan – 2 Feb · 14 days',
      ]);
      final rows = [
        for (final b in c.blocks)
          for (final p in b.pauses) (b.number, p.afterDay),
      ];
      expect(rows, [(1, 4), (9, 58), (11, 72)]);
      expect(c.days, hasLength(92));
    });

    test('an open pause: "Paused since", no end date, undated days stay '
        'upcoming and not interactive; the paused week is current', () {
      final s = valid(
        rollingArc(start, freezes: [openFreeze(LocalDate(2027, 3, 11))]),
      );
      final c = calendarOf(historyOf(s, LocalDate(2027, 3, 15)));
      final pause = c.pauses.single;
      expect(calendarPauseText(pause), 'Paused since 11 Mar');
      expect(pause.lastDate, isNull);
      expect(layout(c.block(2)), [8, 9, 10, 0, 11, 12, 13, 14]);
      for (final d in c.days.skip(10)) {
        expect(d.date, isNull);
        expect(d.state, JourneyDayState.future);
        expect(d.isInteractive, isFalse);
      }
      expect(c.block(2).status, ArcWeekStatus.paused);
      expect(
        calendarWeekHeading(c.block(2)),
        'Week 2 · 8 Mar – paused · 0 of 3 days full · Paused',
      );
      expect(
        calendarWeekHeading(c.block(3)),
        'Week 3 · Dates are set when you resume · Upcoming',
      );
      expect(
        calendarDayLabel(c.days.elementAt(25).journeyDay),
        'Day 26. Upcoming. Its date is set when you resume.',
      );
      expect(c.days.where((d) => d.isToday), isEmpty);
    });

    test('a scheduled pause: today still counts; "Pause starts"', () {
      final s = valid(
        rollingArc(start, freezes: [openFreeze(LocalDate(2027, 3, 11))]),
      );
      final c = calendarOf(historyOf(s, LocalDate(2027, 3, 10)));
      expect(calendarPauseText(c.pauses.single), 'Pause starts 11 Mar');
      expect(c.pauses.single.scheduled, isTrue);
      expect(c.days.elementAt(9).isToday, isTrue);
      expect(c.block(2).status, ArcWeekStatus.inProgress);
    });
  });

  group('ended Arcs (§ 12.4)', () {
    final start = LocalDate(2027, 3, 1);
    final closedOn = start.addDays(41); // Day 42 (Week 6)
    final ended = rollingArc(
      start,
      status: WinterArcStatus.ended,
      closedOn: closedOn,
    );
    ArcHistory h(LocalDate today) => historyOf(
      valid(ended),
      today,
      days: {
        for (var i = 0; i <= 41; i++)
          start.addDays(i): i.isOdd ? day(allFive) : day(const {}),
      },
    );

    test('all 92 cells; later days not reached, never missed; no Today, '
        'on closedOn, after it, and behind it after a rollback', () {
      for (final today in [
        closedOn.addDays(-1),
        closedOn,
        closedOn.addDays(1),
        closedOn.addDays(70),
        closedOn.addDays(400),
      ]) {
        final c = calendarOf(h(today));
        expect(c.days, hasLength(92));
        expect(c.days.where((d) => d.isToday), isEmpty, reason: '$today');
        for (final d in c.days.skip(42)) {
          expect(d.state, JourneyDayState.notReached, reason: '$today');
          expect(d.isInteractive, isFalse);
          expect(d.record, isNull);
        }
        expect(
          calendarDayLabel(c.days.elementAt(42).journeyDay),
          'Day 43. Not reached.',
        );
        for (var w = 7; w <= 13; w++) {
          expect(c.block(w).status, ArcWeekStatus.notReached);
          expect(c.block(w).isReviewable, isFalse);
          expect(calendarWeekHeading(c.block(w)), endsWith('· Not reached'));
          expect(
            calendarWeekHeadingLabel(c.block(w)),
            isNot(contains('Opens')),
          );
        }
      }
      final onClosed = calendarOf(h(closedOn));
      expect(onClosed.block(6).status, ArcWeekStatus.complete);
      expect(onClosed.block(6).isReviewable, isTrue);
      expect(onClosed.days.elementAt(41).state, JourneyDayState.perfect);
      expect(onClosed.block(6).countedDays, 7);
      expect(onClosed.initialWeek, 6);
      // Behind closedOn after a rollback: closedOn is upcoming, not missed.
      final behind = calendarOf(h(closedOn.addDays(-1)));
      expect(behind.days.elementAt(41).state, JourneyDayState.future);
    });

    test('the same history on every later date', () {
      final reference = calendarOf(h(closedOn));
      for (final today in [closedOn.addDays(1), closedOn.addDays(365)]) {
        final c = calendarOf(h(today));
        expect(
          c.days.map((d) => (d.state, d.date, d.isToday)),
          reference.days.map((d) => (d.state, d.date, d.isToday)),
        );
        expect(
          c.blocks.map(calendarWeekHeading),
          reference.blocks.map(calendarWeekHeading),
        );
      }
    });
  });

  group('completed Arcs (K5)', () {
    final start = LocalDate(2026, 7, 1);
    final completed = rollingArc(
      start,
      status: WinterArcStatus.completed,
      freezes: [closedFreeze(LocalDate(2026, 7, 20), 4)],
    );
    ArcHistory h(LocalDate today) => historyOf(
      valid(completed),
      today,
      days: {
        for (var d = 1; d <= 92; d += 3)
          completed.dateOfDay(d)!: day(d.isEven ? allFive : {'water'}),
      },
    );

    test('identical at several dates after its end; nothing today', () {
      final end = completed.endDate;
      final reference = calendarOf(h(end.addDays(1)));
      expect(reference.days.where((d) => d.isToday), isEmpty);
      expect(reference.initialWeek, 13);
      for (final today in [end.addDays(2), end.addDays(90), end.addDays(800)]) {
        final c = calendarOf(h(today));
        expect(
          c.days.map((d) => (d.state, d.date, d.isToday, d.isSettled)),
          reference.days.map((d) => (d.state, d.date, d.isToday, d.isSettled)),
        );
        expect(
          c.blocks.map(calendarWeekHeading),
          reference.blocks.map(calendarWeekHeading),
        );
        expect(
          c.pauses.map(calendarPauseText),
          reference.pauses.map(calendarPauseText),
        );
      }
      for (final b in reference.blocks) {
        expect(b.status, ArcWeekStatus.complete);
        expect(calendarWeekHeading(b), contains('days full'));
      }
    });

    test('after a clock rollback into it: one open day (approved), still '
        'read-only', () {
      final rolledBack = calendarOf(h(completed.dateOfDay(60)!));
      final today = rolledBack.days.where((d) => d.isToday).toList();
      expect(today, hasLength(1));
      expect(today.single.dayNumber, 60);
      expect(rolledBack.days.elementAt(60).state, JourneyDayState.future);
    });
  });

  group('property: the calendar is the Journey, laid out in weeks', () {
    test('generated Arcs of every status and many dates', () {
      final generator = HistoryGenerator(20261119);
      var checked = 0;
      for (var i = 0; i < 150; i++) {
        final s = generator.session();
        for (final today in generator.todays(s)) {
          final h = generator.history(s, today);
          final j = JourneyOverview.fromHistory(h);
          final c = ArcCalendar.of(j);
          final why = '$s on $today';
          final cells = c.days.toList();
          expect(cells, hasLength(92), reason: why);
          for (var n = 1; n <= 92; n++) {
            final cell = cells[n - 1];
            final journey = j.days[n - 1];
            // A second, independent computation of the same day.
            final again = h.journeyDay(n);
            expect(cell.dayNumber, n, reason: why);
            expect(identical(cell.journeyDay, journey), isTrue, reason: why);
            expect(cell.date, again.date, reason: why);
            expect(cell.state, again.state, reason: why);
            expect(cell.isToday, again.isToday, reason: why);
            expect(
              cell.record?.completion.completed,
              again.record?.completion.completed,
              reason: why,
            );
            expect(cell.record?.mode, again.record?.mode, reason: why);
            expect(cell.date, s.dateOfDay(n), reason: 'no guessed date $why');
            if (cell.date case final date?) {
              expect(s.isFrozenOn(date), isFalse, reason: why);
            }
            expect(
              classMatchesJourney(cell.weekDay.dayClass, cell.journeyDay),
              isTrue,
              reason: '$why Day $n',
            );
            expect(
              c.block(ArcWeeks.weekOf(n)).days.where((d) => d.dayNumber == n),
              hasLength(1),
              reason: why,
            );
            if (s.status == WinterArcStatus.ended) {
              expect(cell.isToday, isFalse, reason: why);
            }
          }
          // Every pause exactly once, after a day of the block it is in.
          final rows = [
            for (final b in c.blocks)
              for (final p in b.pauses) (b, p),
          ];
          expect(rows, hasLength(s.freezes.length), reason: why);
          for (final (b, p) in rows) {
            expect(ArcWeeks.weekOf(p.afterDay), b.number, reason: why);
            expect(
              s.dateOfDay(p.afterDay)?.isBefore(p.firstDate) ?? true,
              isTrue,
              reason: why,
            );
            if (s.dateOfDay(p.afterDay + 1) case final next?) {
              expect(next.isAfter(p.firstDate), isTrue, reason: why);
              if (p.freeze.resumedOn case final resumed?) {
                expect(next, resumed, reason: why);
              }
            }
          }
          expect(c.blocks.map((b) => b.days.length), [
            ...List.filled(12, 7),
            8,
          ], reason: why);
          checked++;
        }
      }
      expect(checked, greaterThan(2000));
    });
  });

  group('wording', () {
    test('date ranges: same month, across months, across years, one day', () {
      expect(
        calendarDateRange(LocalDate(2026, 10, 15), LocalDate(2026, 10, 21)),
        '15–21 Oct',
      );
      expect(
        calendarDateRange(LocalDate(2026, 10, 29), LocalDate(2026, 11, 4)),
        '29 Oct – 4 Nov',
      );
      expect(
        calendarDateRange(LocalDate(2026, 12, 28), LocalDate(2027, 1, 3)),
        '28 Dec 2026 – 3 Jan 2027',
      );
      expect(
        calendarDateRange(LocalDate(2027, 3, 11), LocalDate(2027, 3, 11)),
        '11 Mar',
      );
    });

    test('chapter lines use the shared chapter titles and first days', () {
      final c = calendarOf(historyOf(rollingArc(wed), wed));
      final lines = {
        for (final b in c.blocks)
          if (b.chapters.isNotEmpty)
            b.number: b.chapters.map(calendarChapterLine).toList(),
      };
      expect(lines, {
        1: ['Frozen Forest begins on Day 1'],
        3: ['First Ascent begins on Day 15'],
        5: ['Ridge begins on Day 31'],
        7: ['Aurora Pass begins on Day 46'],
        9: ['High Mountain begins on Day 61'],
        11: ['Summit Approach begins on Day 76'],
      });
      expect([for (final b in c.blocks) ...b.chapters], JourneyChapter.values);
    });

    test('a cell\'s label is the Weekly Review strip\'s for the same day', () {
      final generator = HistoryGenerator(5);
      for (var i = 0; i < 30; i++) {
        final s = generator.session();
        for (final today in generator.todays(s).take(6)) {
          final h = generator.history(s, today);
          final c = calendarOf(h);
          for (final b in c.blocks) {
            final review = WeeklyReview.fromHistory(
              h,
              b.number,
              weeks: c.weeks,
            );
            for (final (k, d) in b.days.indexed) {
              if (d.state == JourneyDayState.notReached) continue;
              expect(
                calendarDayLabel(d.journeyDay),
                reviewDayLabel(review.days[k]),
              );
            }
          }
        }
      }
    });
  });

  group('Gate C copy: "No progress" (presentation only)', () {
    test('the shared label and announcement; the domain state is still '
        'missed', () {
      expect(JourneyDayState.missed.label, 'No progress');
      expect(JourneyDayState.missed.name, 'missed');
      final day = JourneyDay(
        dayNumber: 2,
        date: wed,
        state: JourneyDayState.missed,
        isToday: false,
        xpEarned: 0,
      );
      expect(journeyDayLabel(day), 'Day 2. No progress.');
      expect(calendarDayLabel(day), 'Day 2, Wednesday 7 October. No progress.');
      for (final state in JourneyDayState.values) {
        expect(state.label.toLowerCase(), isNot(contains('missed')));
      }
    });
  });

  group('visual distinction and contrast (A6, A12, § 8.3)', () {
    test('the nine states differ by glyph, or by label where the glyph is '
        'shared; Minimum never looks Perfect', () {
      expect(JourneyDayState.values, hasLength(9));
      final byGlyph = <Object, List<JourneyDayState>>{};
      for (final state in JourneyDayState.values) {
        (byGlyph[(state.square, state.fill, state.icon, state.dashed)] ??= [])
            .add(state);
      }
      for (final states in byGlyph.values) {
        expect(states.map((s) => s.label).toSet(), hasLength(states.length));
      }
      expect(JourneyDayState.values.map((s) => s.label).toSet(), hasLength(9));
      final perfect = JourneyDayState.perfect;
      final minimum = JourneyDayState.minimumComplete;
      expect(perfect.square, isFalse);
      expect(minimum.square, isTrue);
      expect(perfect.icon, isNot(minimum.icon));
      expect(perfect.label, isNot(minimum.label));
    });

    test('every glyph outline reaches 3:1 and all calendar text 4.5:1 '
        'against the calendar surface, from the tokens', () {
      const colors = WinterColors.night;
      final surface = colors.surface;
      // The Journey's own outline token falls short, which is why the
      // calendar doesn't use it.
      expect(contrast(colors.outline, surface), lessThan(3));
      for (final state in JourneyDayState.values) {
        final outline = calendarOutlineColor(state, colors);
        expect(outline.a, 1, reason: '$state outline is never dimmed');
        expect(
          contrast(outline, surface),
          greaterThanOrEqualTo(3),
          reason: '$state ${contrast(outline, surface)}',
        );
        // A full glyph's icon against its own (composited) fill.
        if (state.fill == MarkerFill.full) {
          final fill = Color.alphaBlend(
            state
                .color(colors)
                .withValues(
                  alpha: calendarFillOpacity(state, highContrast: false),
                ),
            surface,
          );
          expect(
            contrast(colors.background, fill),
            greaterThanOrEqualTo(3),
            reason: '$state icon',
          );
        }
      }
      // Today's 3 dp border.
      expect(contrast(colors.snow, surface), greaterThanOrEqualTo(3));
      // Text: day numbers, headings, chapter lines, pause rows.
      for (final text in [
        colors.textPrimary,
        colors.textSecondary,
        colors.snow,
        colors.accentSecondary,
      ]) {
        expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
      }
      // The pause icon (non-text).
      expect(contrast(colors.fog, surface), greaterThanOrEqualTo(3));
    });

    test('high contrast: fills are not dimmed; otherwise only the fill is', () {
      for (final state in JourneyDayState.values) {
        expect(calendarFillOpacity(state, highContrast: true), 1);
        expect(calendarFillOpacity(state, highContrast: false), state.opacity);
      }
    });
  });
}
