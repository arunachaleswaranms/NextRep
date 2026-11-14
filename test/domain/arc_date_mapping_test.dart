import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/lifecycle_arcs.dart';

/// Phase 12E1: the challenge day ↔ calendar date mapping
/// (ARC_CONTROL_SPEC § 5.1, addendum § F1, spec § 12.2). Deterministic
/// property tests over generated arcs; every arc is synthetic.
void main() {
  group('without a freeze, every answer is exactly v1.2.0\'s', () {
    void expectV12(WinterArcSession s, ArcGenerator g) {
      final v12 = V12Arithmetic(s);
      final reason = '${s.kind.name} ${s.status.name} ${s.startDate}';
      expect(s.lengthInDays, v12.lengthInDays, reason: reason);
      expect(s.calendarSpanInDays, v12.lengthInDays, reason: reason);
      expect(s.joinDayNumber, v12.joinDayNumber, reason: reason);
      if (s.participationStartDate != null) {
        expect(
          s.participationLengthInDays,
          v12.participationLengthInDays,
          reason: reason,
        );
      }
      // Days 1–92 and a few outside, both ways.
      for (var day = -3; day <= 95; day++) {
        expect(s.dateOfDay(day), v12.dateOfDay(day), reason: '$reason $day');
      }
      // Every date from before the start to after the end, plus far dates
      // (a clock moved back or forward by years).
      final dates = [
        for (
          var d = s.startDate.addDays(-12);
          !d.isAfter(s.endDate.addDays(12));
          d = d.addDays(1)
        )
          d,
        s.startDate.addDays(-4000),
        s.endDate.addDays(4000),
        g.date(),
      ];
      for (final date in dates) {
        final at = '$reason on $date';
        expect(s.dayNumberOf(date), v12.dayNumberOf(date), reason: at);
        expect(
          describe(s.positionOn(date)),
          describe(v12.positionOn(date)),
          reason: at,
        );
        expect(
          s.isParticipatingOn(date),
          v12.isParticipatingOn(date),
          reason: at,
        );
        expect(s.isOverOn(date), v12.isOverOn(date), reason: at);
        expect(s.isFrozenOn(date), isFalse, reason: at);
        expect(
          s.participatingDatesThrough(date),
          v12.participatingDatesThrough(date),
          reason: at,
        );
        final next = date.addDays(1);
        expect(
          s.hasChallengeDayOnOrAfter(next) ? next : null,
          v12.nextChallengeDay(date),
          reason: at,
        );
        // Without `ended`, the open day is the participating day.
        expect(s.isOpenOn(date), v12.isParticipatingOn(date), reason: at);
      }
    }

    test('generated rolling arcs (setup, active, completed)', () {
      final g = ArcGenerator(1215);
      for (var i = 0; i < 250; i++) {
        expectV12(g.plainRolling(), g);
      }
    });

    test('generated seasonal arcs, including setup and late joins', () {
      final g = ArcGenerator(2026);
      for (var i = 0; i < 250; i++) {
        expectV12(g.plainSeasonal(), g);
      }
    });

    test('a seasonal arc joined on its last day, and on Day 1', () {
      final g = ArcGenerator(7);
      expectV12(seasonalArc(2026, joined: LocalDate(2026, 12, 31)), g);
      expectV12(seasonalArc(2026, joined: LocalDate(2026, 10, 1)), g);
    });

    test('around leap days, month ends and year ends', () {
      final g = ArcGenerator(29);
      for (final start in [
        LocalDate(2028, 2, 28),
        LocalDate(2028, 2, 29),
        LocalDate(2027, 12, 31),
        LocalDate(2026, 10, 31),
        LocalDate(2027, 1, 31),
      ]) {
        expectV12(rollingArc(start), g);
        expectV12(rollingArc(start, status: WinterArcStatus.completed), g);
      }
    });
  });

  group('freeze-aware mapping (generated paused arcs)', () {
    test('92 challenge days; inverse mapping; paused dates have no day', () {
      final g = ArcGenerator(92);
      for (var i = 0; i < 400; i++) {
        final s = g.pausedRolling();
        expect(WinterArcRules.problemWith(s), isNull, reason: '${s.freezes}');
        final brute = bruteChallengeDates(s);
        final open = s.hasOpenFreeze;
        final reason = '${s.startDate} ${s.freezes}';
        expect(s.lengthInDays, WinterArcRules.lengthInDays, reason: reason);
        if (!open) {
          expect(brute, hasLength(92), reason: reason);
          expect(brute.last, s.endDate, reason: reason);
          expect(
            s.calendarSpanInDays,
            92 + s.pausedDays,
            reason: 'closed pauses lengthen the calendar span',
          );
        }
        for (var day = 1; day <= 92; day++) {
          final date = s.dateOfDay(day);
          if (day <= brute.length) {
            expect(date, brute[day - 1], reason: '$reason day $day');
            expect(s.dayNumberOf(date!), day, reason: '$reason day $day');
            expect(s.isParticipatingOn(date), isTrue);
          } else {
            // After the start of an open freeze: no invented date.
            expect(open, isTrue);
            expect(date, isNull, reason: '$reason day $day');
          }
        }
        expect(s.dateOfDay(93), open ? isNull : isNot(isIn(brute)));
        // Every calendar date of the span: a challenge day or paused.
        final last = s.endDate.addDays(open ? 500 : 3);
        final seen = <int>{};
        for (var d = s.startDate; !d.isAfter(last); d = d.addDays(1)) {
          final frozen = s.isFrozenOn(d);
          // Not a challenge date ⇔ paused: inside the span, or anywhere
          // after the start of an open pause.
          expect(
            frozen,
            !brute.contains(d) && (open || !d.isAfter(s.endDate)),
            reason: '$reason $d',
          );
          if (frozen) {
            expect(s.dayNumberOf(d), isNull, reason: '$reason $d');
            expect(s.positionOn(d), isA<ArcPaused>(), reason: '$reason $d');
            expect(s.isParticipatingOn(d), isFalse);
            expect(s.isOpenOn(d), isFalse);
          } else if (!d.isAfter(s.endDate)) {
            final n = s.dayNumberOf(d)!;
            expect(seen.add(n), isTrue, reason: 'no day mapped twice');
            expect(
              (s.positionOn(d) as ArcInProgress).dayNumber,
              n,
              reason: '$reason $d',
            );
          }
        }
        expect(seen.length, brute.length);
      }
    });

    test('elapsed dates leave out paused dates and never exceed 92', () {
      final g = ArcGenerator(1103);
      for (var i = 0; i < 200; i++) {
        final s = g.pausedRolling();
        final brute = bruteChallengeDates(s);
        for (final today in [
          s.startDate.addDays(-1),
          s.startDate,
          for (final f in s.freezes) ...[
            f.frozenFrom.addDays(-1),
            f.frozenFrom,
            if (f.resumedOn case final r?) ...[r.addDays(-1), r, r.addDays(1)],
          ],
          s.endDate,
          s.endDate.addDays(1),
          s.endDate.addDays(700),
        ]) {
          final elapsed = s.participatingDatesThrough(today);
          expect(elapsed, [
            for (final d in brute)
              if (!d.isAfter(today)) d,
          ], reason: '${s.freezes} on $today');
          expect(elapsed.length, lessThanOrEqualTo(92));
          expect(elapsed.any(s.isFrozenOn), isFalse);
        }
      }
    });

    test('a paused arc is never over; a resumed one is over after Day 92', () {
      final g = ArcGenerator(4);
      for (var i = 0; i < 200; i++) {
        final s = g.pausedRolling();
        final farFuture = s.endDate.addDays(5000);
        if (s.hasOpenFreeze) {
          expect(s.isOverOn(farFuture), isFalse);
          expect(s.positionOn(farFuture), isA<ArcPaused>());
        } else {
          expect(s.isOverOn(s.endDate), isFalse);
          expect(s.isOverOn(s.endDate.addDays(1)), isTrue);
          expect(s.positionOn(s.endDate.addDays(1)), isA<ArcFinished>());
          expect((s.positionOn(s.endDate) as ArcInProgress).dayNumber, 92);
        }
      }
    });

    test('a later freeze never changes the day of a date already lived', () {
      final g = ArcGenerator(77);
      for (var i = 0; i < 200; i++) {
        final before = g.pausedRolling(allowOpen: false);
        final brute = bruteChallengeDates(before);
        // Freeze after some lived day T (the day after it), as Freeze does.
        final lived = g.nextInt(91) + 1;
        final today = brute[lived - 1];
        if (before.freezes.any((f) => !f.resumedOn!.isBefore(today))) {
          continue; // the clock guard would refuse it (§ AD19)
        }
        final after = rollingArc(
          before.startDate,
          freezes: [
            ...before.freezes,
            closedFreeze(today.addDays(1), g.pauseLength()),
          ],
        );
        expect(WinterArcRules.problemWith(after), isNull);
        for (var d = before.startDate; !d.isAfter(today); d = d.addDays(1)) {
          expect(after.dayNumberOf(d), before.dayNumberOf(d), reason: '$d');
          expect(after.isParticipatingOn(d), before.isParticipatingOn(d));
        }
        for (var day = 1; day <= lived; day++) {
          expect(after.dateOfDay(day), before.dateOfDay(day));
        }
      }
    });

    test('no loop walks the paused dates of a long pause', () {
      // 92 challenge days around a 400 000-date pause: a date-by-date walk
      // would take visibly long; the mapping jumps over it.
      final start = LocalDate(2026, 1, 1);
      final s = rollingArc(
        start,
        freezes: [closedFreeze(start.addDays(10), 400000)],
      );
      final watch = Stopwatch()..start();
      final elapsed = s.participatingDatesThrough(s.endDate);
      expect(elapsed, hasLength(92));
      expect(s.dateOfDay(92), s.endDate);
      expect(s.dayNumberOf(s.endDate), 92);
      expect(s.dayNumberOf(start.addDays(200000)), isNull);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('worked cases', () {
    // ARC_CONTROL_SPEC § 5.3: from 1 March 2027, paused 11–19 March.
    final start = LocalDate(2027, 3, 1);

    test('one completed freeze (spec § 5.3)', () {
      final s = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)],
      );
      expect(WinterArcRules.problemWith(s), isNull);
      expect(s.endDate, LocalDate(2027, 6, 9));
      expect(s.dayNumberOf(LocalDate(2027, 3, 10)), 10);
      for (var d = 11; d <= 19; d++) {
        expect(s.dayNumberOf(LocalDate(2027, 3, d)), isNull);
        expect(s.isParticipatingOn(LocalDate(2027, 3, d)), isFalse);
      }
      expect(s.dayNumberOf(LocalDate(2027, 3, 20)), 11);
      expect(s.dateOfDay(11), LocalDate(2027, 3, 20));
      expect(s.dateOfDay(92), LocalDate(2027, 6, 9));
      expect(s.isOverOn(LocalDate(2027, 6, 9)), isFalse);
      expect(s.isOverOn(LocalDate(2027, 6, 10)), isTrue);
      final paused = s.positionOn(LocalDate(2027, 3, 15)) as ArcPaused;
      expect(paused.lastDayNumber, 10);
      expect(paused.pausedSince, LocalDate(2027, 3, 11));
      expect(paused.resumesOn, LocalDate(2027, 3, 20));
      expect(s.calendarSpanInDays, 101);
      expect(s.lengthInDays, 92);
      expect(s.pausedDays, 9);
    });

    test('a scheduled freeze: today is still a normal challenge day', () {
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      expect(WinterArcRules.problemWith(s), isNull);
      final today = LocalDate(2027, 3, 10);
      expect(s.isParticipatingOn(today), isTrue);
      expect(s.isOpenOn(today), isTrue);
      expect((s.positionOn(today) as ArcInProgress).dayNumber, 10);
      expect(s.participatingDatesThrough(today), hasLength(10));
      // A goal edit today is dated tomorrow, on the first paused date.
      expect(s.hasChallengeDayOnOrAfter(today.addDays(1)), isTrue);
    });

    test('an open freeze: later days have no date, the arc never ends', () {
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      expect(s.dateOfDay(10), LocalDate(2027, 3, 10));
      for (var day = 11; day <= 92; day++) {
        expect(s.dateOfDay(day), isNull);
      }
      final paused = s.positionOn(LocalDate(2028, 1, 1)) as ArcPaused;
      expect(paused.lastDayNumber, 10);
      expect(paused.resumesOn, isNull);
      expect(s.isOverOn(LocalDate(2030, 1, 1)), isFalse);
      expect(s.participatingDatesThrough(LocalDate(2030, 1, 1)), hasLength(10));
      // The stored end date is not a finish date while paused.
      expect(s.isOverOn(s.endDate.addDays(1)), isFalse);
    });

    test('several completed freezes accumulate', () {
      final s = rollingArc(
        start,
        freezes: [
          closedFreeze(LocalDate(2027, 3, 3), 2), // after Day 2
          closedFreeze(LocalDate(2027, 3, 8), 5), // after Day 5
          closedFreeze(LocalDate(2027, 3, 14), 1), // after Day 6
        ],
      );
      expect(WinterArcRules.problemWith(s), isNull);
      expect(s.pausedDays, 8);
      expect(s.endDate, WinterArcRules.endDateFor(start).addDays(8));
      expect(s.dateOfDay(3), LocalDate(2027, 3, 5));
      expect(s.dateOfDay(6), LocalDate(2027, 3, 13));
      expect(s.dateOfDay(7), LocalDate(2027, 3, 15));
      expect(s.dateOfDay(8), LocalDate(2027, 3, 16));
      expect(s.dayNumberOf(LocalDate(2027, 3, 14)), isNull);
      expect(s.dayNumberOf(LocalDate(2027, 3, 15)), 7);
    });

    test('a freeze on Day 91 pauses the planned last date (spec § 5.3)', () {
      final rolling = rollingArc(start);
      final day91 = rolling.dateOfDay(91)!;
      final s = rollingArc(start, freezes: [closedFreeze(day91.addDays(1), 5)]);
      expect(WinterArcRules.problemWith(s), isNull);
      expect(day91.addDays(1), LocalDate(2027, 5, 31));
      expect(s.dateOfDay(92), LocalDate(2027, 6, 5));
      expect(s.endDate, LocalDate(2027, 6, 5));
      expect(s.isOverOn(LocalDate(2027, 6, 6)), isTrue);
      // A freeze after Day 92 is not possible.
      final late = rollingArc(
        start,
        freezes: [openFreeze(rolling.endDate.addDays(1))],
      );
      expect(
        WinterArcRules.problemWith(late),
        'a pause after the last challenge day',
      );
    });

    test('daylight saving and time zones: LocalDate arithmetic only', () {
      // 28 March 2027 is a DST change in Europe; the mapping is pure dates.
      final s = rollingArc(LocalDate(2027, 3, 27));
      expect(s.dayNumberOf(LocalDate(2027, 3, 28)), 2);
      expect(s.dayNumberOf(LocalDate(2027, 3, 29)), 3);
      final lateNight = LocalDate.fromDateTime(DateTime(2027, 3, 28, 23, 59));
      expect(s.dayNumberOf(lateNight), 2);
    });

    test('a date rolled back before a pause is a challenge date again', () {
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      expect(s.isParticipatingOn(LocalDate(2027, 3, 9)), isTrue);
      expect(s.isOpenOn(LocalDate(2027, 3, 9)), isTrue);
    });
  });

  group('ended arcs', () {
    final start = LocalDate(2026, 10, 7);

    test('participation stops at closedOn; no open day; not reached after', () {
      final closed = LocalDate(2026, 10, 16); // Day 10
      final s = rollingArc(
        start,
        status: WinterArcStatus.ended,
        closedOn: closed,
      );
      expect(WinterArcRules.problemWith(s), isNull);
      expect(s.isParticipatingOn(closed), isTrue);
      expect(
        s.isOpenOn(closed),
        isFalse,
        reason: 'an ended arc has no open day',
      );
      expect(s.isParticipatingOn(closed.addDays(1)), isFalse);
      expect(s.participatingDatesThrough(LocalDate(2027, 5, 1)), hasLength(10));
      expect(s.participatingDatesThrough(closed.addDays(-1)), hasLength(9));
      final after = s.positionOn(closed.addDays(1)) as ArcEnded;
      expect(after.lastDayNumber, 10);
      expect(after.closedOn, closed);
      expect(s.positionOn(s.endDate.addDays(9)), isA<ArcEnded>());
      expect((s.positionOn(closed) as ArcInProgress).dayNumber, 10);
      // Planned dates of days not reached are kept, not invented.
      expect(s.dateOfDay(11), closed.addDays(1));
      expect(s.hasChallengeDayOnOrAfter(closed.addDays(1)), isFalse);
      expect(s.status.isFinished, isTrue);
      expect(s.status.isUnfinished, isFalse);
    });

    test('an ended paused arc closes on its last lived day', () {
      final s = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2026, 10, 20), 3)],
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 10, 25),
      );
      expect(WinterArcRules.problemWith(s), isNull);
      expect(s.dayNumberOf(LocalDate(2026, 10, 25)), 16);
      expect(s.participatingDatesThrough(LocalDate(2027, 1, 1)), hasLength(16));
    });

    test('an ended seasonal arc keeps its season day numbers', () {
      final s = seasonalArc(
        2026,
        joined: LocalDate(2026, 10, 18),
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 11, 2),
      );
      expect(WinterArcRules.problemWith(s), isNull);
      expect(s.dayNumberOf(LocalDate(2026, 11, 2)), 33);
      expect(s.joinDayNumber, 18);
      expect(s.participationLengthInDays, 16, reason: '18 Oct – 2 Nov');
      expect(
        seasonalArc(
          2026,
          joined: LocalDate(2026, 10, 18),
        ).participationLengthInDays,
        75,
        reason: 'unchanged without a closing date',
      );
      expect(
        s.participatingDatesThrough(LocalDate(2026, 12, 31)),
        hasLength(16),
      );
    });
  });

  group('validation (WinterArcRules.problemWith)', () {
    final start = LocalDate(2027, 3, 1);
    String? problem(WinterArcSession s) => WinterArcRules.problemWith(s);

    test('generated valid arcs pass', () {
      final g = ArcGenerator(3);
      for (var i = 0; i < 300; i++) {
        expect(problem(g.pausedRolling()), isNull);
        expect(problem(g.plainRolling()), isNull);
        expect(problem(g.plainSeasonal()), isNull);
      }
    });

    test('a seasonal arc or a setup is never paused', () {
      final seasonal = WinterArcSession(
        id: 1,
        kind: ArcKind.seasonalWinter,
        startDate: LocalDate(2026, 10, 1),
        endDate: LocalDate(2026, 12, 31),
        status: WinterArcStatus.active,
        createdAt: DateTime(2026, 9, 1),
        participationStartDate: LocalDate(2026, 10, 1),
        freezes: [openFreeze(LocalDate(2026, 10, 5))],
      );
      expect(problem(seasonal), 'a seasonal arc is not paused');
      final setup = rollingArc(
        start,
        status: WinterArcStatus.setup,
      ).copyWith(freezes: [openFreeze(start.addDays(2))]);
      expect(problem(setup), 'an arc in setup is not paused');
    });

    test('intervals: ordered, apart, non-empty, one open and last', () {
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              closedFreeze(start.addDays(10), 3),
              closedFreeze(start.addDays(5), 2),
            ],
          ),
        ),
        'pauses overlap or are out of order',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              closedFreeze(start.addDays(5), 5),
              closedFreeze(start.addDays(8), 2),
            ],
          ),
        ),
        'pauses overlap or are out of order',
      );
      // Touching: no challenge day between them.
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              closedFreeze(start.addDays(5), 5),
              closedFreeze(start.addDays(10), 2),
            ],
          ),
        ),
        'pauses overlap or are out of order',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              openFreeze(start.addDays(5)),
              openFreeze(start.addDays(20)),
            ],
          ),
        ),
        'only the last pause is open',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              ArcFreeze(
                frozenFrom: start.addDays(5),
                resumedOn: start.addDays(5),
                requestedAt: requestedAt,
                resumedAt: resumedAt,
              ),
            ],
          ),
        ),
        'a pause ends after it starts',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [
              ArcFreeze(
                frozenFrom: start.addDays(5),
                resumedOn: start.addDays(7),
                requestedAt: requestedAt,
              ),
            ],
          ),
        ),
        'a resumed pause has a resume time',
      );
      expect(
        problem(rollingArc(start, freezes: [openFreeze(start)])),
        'a pause starts after the first day',
      );
    });

    test('only an active arc is open-paused; the end date follows', () {
      expect(
        problem(
          rollingArc(
            start,
            freezes: [openFreeze(start.addDays(5))],
            status: WinterArcStatus.completed,
          ),
        ),
        'only an active arc is paused',
      );
      final wrongEnd = rollingArc(
        start,
        freezes: [closedFreeze(start.addDays(5), 4)],
      ).copyWith(endDate: WinterArcRules.endDateFor(start));
      expect(problem(wrongEnd), 'not a 92-day arc');
    });

    test('closedOn: exactly for ended arcs, on a challenge date', () {
      expect(
        problem(rollingArc(start, status: WinterArcStatus.ended)),
        'an ended arc has a closing date',
      );
      expect(
        problem(rollingArc(start, closedOn: start.addDays(3))),
        'only an ended arc has a closing date',
      );
      expect(
        problem(
          rollingArc(
            start,
            status: WinterArcStatus.completed,
            closedOn: start.addDays(3),
          ),
        ),
        'only an ended arc has a closing date',
      );
      expect(
        problem(
          rollingArc(
            start,
            status: WinterArcStatus.ended,
            closedOn: WinterArcRules.endDateFor(start).addDays(1),
          ),
        ),
        'an ended arc closes on one of its challenge days',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [closedFreeze(start.addDays(5), 4)],
            status: WinterArcStatus.ended,
            closedOn: start.addDays(6),
          ),
        ),
        'an ended arc closes on one of its challenge days',
        reason: 'a paused date',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [openFreeze(start.addDays(3))],
            status: WinterArcStatus.ended,
            closedOn: start.addDays(4),
          ),
        ),
        'only an active arc is paused',
      );
      expect(
        problem(
          rollingArc(
            start,
            freezes: [closedFreeze(start.addDays(10), 4)],
            status: WinterArcStatus.ended,
            closedOn: start.addDays(4),
          ),
        ),
        'a pause after the arc closed',
      );
      expect(
        problem(
          seasonalArc(
            2026,
            status: WinterArcStatus.ended,
            joined: LocalDate(2026, 10, 20),
            closedOn: LocalDate(2026, 10, 19),
          ),
        ),
        'an ended arc closes on one of its challenge days',
        reason: 'before joining',
      );
    });
  });
}
