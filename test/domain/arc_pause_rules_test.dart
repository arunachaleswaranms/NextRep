import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/arc_pause.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/arc_pause/pause_labels.dart';

import '../support/lifecycle_arcs.dart';

/// Phase 12E2: the pure Freeze / Cancel / Resume rules (ARC_CONTROL_SPEC
/// § 5.2 F1–F13, addendum AD5–AD8, AD19), the previews, and generated
/// freeze/resume histories checked against an independent calendar walk.
/// All data synthetic.

Matcher _refused(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

final _now = DateTime(2027, 1, 1, 9);

WinterArcSession _pause(WinterArcSession s, LocalDate today) =>
    ArcPauseRules.pause(
      s,
      today: today,
      now: _now,
      lastActivityDate: null,
      shownFrozenFrom: today.addDays(1),
    ).applyTo(s);

WinterArcSession _resume(WinterArcSession s, LocalDate today) =>
    ArcPauseRules.resume(s, today: today, now: _now, shownOn: today).applyTo(s);

void main() {
  final start = LocalDate(2027, 3, 1);
  LocalDate d(int n) => start.addDays(n - 1);

  group('blockerOn (F1, F4)', () {
    test('every reason, in order', () {
      expect(ArcPauseRules.blockerOn(rollingArc(start), d(5)), isNull);
      expect(
        ArcPauseRules.blockerOn(
          rollingArc(start, status: WinterArcStatus.setup),
          d(5),
        ),
        PauseBlocker.notActive,
      );
      expect(
        ArcPauseRules.blockerOn(
          rollingArc(start, status: WinterArcStatus.completed),
          d(5),
        ),
        PauseBlocker.notActive,
      );
      expect(
        ArcPauseRules.blockerOn(
          seasonalArc(2027, joined: LocalDate(2027, 10, 1)),
          LocalDate(2027, 10, 5),
        ),
        PauseBlocker.seasonal,
      );
      final scheduled = rollingArc(start, freezes: [openFreeze(d(6))]);
      expect(ArcPauseRules.blockerOn(scheduled, d(5)), PauseBlocker.scheduled);
      expect(ArcPauseRules.blockerOn(scheduled, d(6)), PauseBlocker.paused);
      final closed = rollingArc(start, freezes: [closedFreeze(d(6), 3)]);
      expect(ArcPauseRules.blockerOn(closed, d(7)), PauseBlocker.paused);
      expect(ArcPauseRules.blockerOn(closed, d(9)), isNull);
      expect(
        ArcPauseRules.blockerOn(rollingArc(start), d(0)),
        PauseBlocker.notChallengeDay,
      );
      expect(
        ArcPauseRules.blockerOn(rollingArc(start), d(93)),
        PauseBlocker.notChallengeDay,
      );
      expect(
        ArcPauseRules.blockerOn(rollingArc(start), d(92)),
        PauseBlocker.lastDay,
      );
      expect(ArcPauseRules.blockerOn(rollingArc(start), d(91)), isNull);
      // Day 92 moved later by a pause.
      final moved = rollingArc(start, freezes: [closedFreeze(d(6), 10)]);
      expect(
        ArcPauseRules.blockerOn(moved, d(92).addDays(10)),
        PauseBlocker.lastDay,
      );
      expect(ArcPauseRules.blockerOn(moved, d(92)), isNull, reason: 'Day 82');
    });
  });

  group('pause (F2, F2a, AD19)', () {
    test('always tomorrow; never moved by activity or a revision', () {
      final change = ArcPauseRules.pause(
        rollingArc(start),
        today: d(10),
        now: _now,
        lastActivityDate: d(10),
        shownFrozenFrom: d(11),
      );
      expect((change as ScheduleFreeze).freeze.frozenFrom, d(11));
      expect(change.freeze.requestedAt, _now);
    });

    test('refusals', () {
      expect(
        () => ArcPauseRules.pause(
          rollingArc(start),
          today: d(10),
          now: _now,
          lastActivityDate: null,
          shownFrozenFrom: d(12),
        ),
        _refused(DomainRule.pauseDateChanged),
      );
      expect(
        () => ArcPauseRules.pause(
          rollingArc(start),
          today: d(10),
          now: _now,
          lastActivityDate: d(11),
          shownFrozenFrom: d(11),
        ),
        _refused(DomainRule.clockBehindHistory),
      );
      expect(
        () => ArcPauseRules.pause(
          rollingArc(start, freezes: [closedFreeze(d(12), 3)]),
          today: d(10),
          now: _now,
          lastActivityDate: null,
          shownFrozenFrom: d(11),
        ),
        _refused(DomainRule.clockBehindHistory),
        reason: 'before the last resume: intervals would overlap',
      );
      expect(
        () => ArcPauseRules.pause(
          rollingArc(start),
          today: d(92),
          now: _now,
          lastActivityDate: null,
          shownFrozenFrom: d(93),
        ),
        _refused(DomainRule.pauseUnavailable),
      );
    });

    test('a repeated request is unchanged', () {
      final s = rollingArc(start, freezes: [openFreeze(d(11))]);
      expect(
        ArcPauseRules.pause(
          s,
          today: d(10),
          now: _now,
          lastActivityDate: null,
          shownFrozenFrom: d(11),
        ),
        isA<FreezeUnchanged>(),
      );
    });
  });

  group('cancel and resume', () {
    FreezeChange cancel(
      WinterArcSession s,
      LocalDate today, {
      DateTime? now,
      LocalDate? lastActivity,
      DateTime? latest,
    }) => ArcPauseRules.cancel(
      s,
      today: today,
      now: now ?? DateTime(today.year, today.month, today.day, 9),
      lastActivityDate: lastActivity,
      latestRecordedAt: latest,
    );

    test('cancel before the start; refused after; nothing to cancel', () {
      final s = rollingArc(start, freezes: [openFreeze(d(11))]);
      expect((cancel(s, d(10)) as DeleteOpenFreeze).frozenFrom, d(11));
      expect(() => cancel(s, d(11)), _refused(DomainRule.pauseAlreadyStarted));
      expect(cancel(rollingArc(start), d(10)), isA<FreezeUnchanged>());
    });

    test('R1: cancel only on the scheduling day, with the clock not behind '
        'the request, the latest write, the activity or the last resume', () {
      final requested = DateTime(2027, 3, 10, 21); // Day 10, 21:00
      final s = rollingArc(
        start,
        freezes: [ArcFreeze(frozenFrom: d(11), requestedAt: requested)],
      );
      final unavailable = _refused(DomainRule.cancelPauseUnavailable);
      // Same day, later: allowed (also at the very same second).
      expect(cancel(s, d(10), now: requested), isA<DeleteOpenFreeze>());
      expect(
        cancel(s, d(10), now: DateTime(2027, 3, 10, 23, 59, 59)),
        isA<DeleteOpenFreeze>(),
      );
      // Midnight: the pause has begun.
      expect(
        () => cancel(s, d(11), now: DateTime(2027, 3, 11)),
        _refused(DomainRule.pauseAlreadyStarted),
      );
      // Rolled back before the scheduling day.
      expect(() => cancel(s, d(9)), unavailable);
      expect(() => cancel(s, d(4)), unavailable);
      // A later instant whose local date is before the scheduling day (a
      // time-zone move west): only the scheduling-day check refuses it.
      expect(
        () => cancel(s, d(9), now: requested.add(const Duration(hours: 1))),
        unavailable,
      );
      // Rolled back before the request instant on the same day.
      expect(
        () => cancel(s, d(10), now: DateTime(2027, 3, 10, 20, 59, 59)),
        unavailable,
      );
      // Instants compare absolutely: the same instant seen in UTC.
      expect(cancel(s, d(10), now: requested.toUtc()), isA<DeleteOpenFreeze>());
      // Behind a later write of this arc.
      expect(
        () => cancel(
          s,
          d(10),
          now: DateTime(2027, 3, 10, 22),
          latest: DateTime(2027, 3, 10, 22, 30),
        ),
        unavailable,
      );
      expect(
        cancel(
          s,
          d(10),
          now: DateTime(2027, 3, 10, 22, 31),
          latest: DateTime(2027, 3, 10, 22, 30),
        ),
        isA<DeleteOpenFreeze>(),
      );
      // Behind stored activity (only possible with damaged or restored data).
      expect(
        () => cancel(
          s,
          d(10),
          now: DateTime(2027, 3, 10, 22),
          lastActivity: d(11),
        ),
        unavailable,
      );
      // Behind the last resume (synthetic: the guard is checked anyway).
      final resumedLater =
          rollingArc(
            start,
            freezes: [ArcFreeze(frozenFrom: d(11), requestedAt: requested)],
          ).copyWith(
            freezes: [
              closedFreeze(
                d(3),
                9,
              ), // resumed on d(12), after the scheduling day
              ArcFreeze(frozenFrom: d(11), requestedAt: requested),
            ],
          );
      expect(
        () => cancel(resumedLater, d(10), now: DateTime(2027, 3, 10, 22)),
        unavailable,
      );
      // Offered only on the scheduling day.
      expect(ArcPauseRules.cancelOfferedOn(s, d(10)), isTrue);
      expect(ArcPauseRules.cancelOfferedOn(s, d(9)), isFalse);
      expect(ArcPauseRules.cancelOfferedOn(s, d(11)), isFalse);
      expect(ArcPauseRules.cancelOfferedOn(rollingArc(start), d(10)), isFalse);
    });

    test(
      'resume: empty interval deleted; k dates closed and the end moved',
      () {
        final s = rollingArc(start, freezes: [openFreeze(d(11))]);
        expect(
          ArcPauseRules.resume(s, today: d(11), now: _now, shownOn: d(11)),
          isA<DeleteOpenFreeze>(),
        );
        final close = ArcPauseRules.resume(
          s,
          today: d(20),
          now: _now,
          shownOn: d(20),
        ) as CloseFreeze;
        expect(close.resumedOn, d(20));
        expect(close.endDate, d(92).addDays(9));
        expect(close.resumedAt, _now);
        expect(
          () =>
              ArcPauseRules.resume(s, today: d(10), now: _now, shownOn: d(10)),
          _refused(DomainRule.notPaused),
        );
        expect(
          () =>
              ArcPauseRules.resume(s, today: d(20), now: _now, shownOn: d(19)),
          _refused(DomainRule.resumeDateChanged),
        );
        expect(
          ArcPauseRules.resume(
            rollingArc(start),
            today: d(20),
            now: _now,
            shownOn: d(20),
          ),
          isA<FreezeUnchanged>(),
        );
        expect(
          () => ArcPauseRules.resume(
            rollingArc(start, freezes: [closedFreeze(d(11), 5)]),
            today: d(13),
            now: _now,
            shownOn: d(13),
          ),
          _refused(DomainRule.notPaused),
          reason: 'a date moved back into a closed pause: no second Resume',
        );
      },
    );

    test('pausedDaysThrough and the previews', () {
      final s = rollingArc(
        start,
        freezes: [closedFreeze(d(5), 4), openFreeze(d(20))],
      );
      expect(s.pausedDaysThrough(d(19)), 4, reason: 'not started yet');
      expect(s.pausedDaysThrough(d(20)), 4, reason: 'first paused date');
      expect(s.pausedDaysThrough(d(26)), 10);
      final preview = ResumePreview(
        session: s,
        today: d(26),
        resumed: _resume(s, d(26)),
      );
      expect(preview.pausedDays, 6);
      expect(preview.totalPausedDays, 10);
      // Day 15 was lived on d(19); today becomes Day 16.
      expect(preview.dayNumber, 16);
      expect(preview.lastDay, d(92).addDays(10));
    });
  });

  group('generated freeze/resume histories', () {
    test('2,000 random histories: every step valid, lived days never move, '
        'end = start + 91 + paused days, nothing pending for a paused '
        'date', () {
      final random = Random(20261122);
      final prefs = ReminderPreferences.defaults.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
      );
      for (var run = 0; run < 2000; run++) {
        final day1 = LocalDate(2026, 1, 1).addDays(random.nextInt(4 * 365));
        var s = rollingArc(day1);
        var today = day1.addDays(random.nextInt(5));
        final lived = <LocalDate, int>{}; // date → its day number
        var paused = 0;
        for (var step = 0; step < 12; step++) {
          if (ArcPauseRules.blockerOn(s, today) == PauseBlocker.lastDay ||
              !s.isParticipatingOn(today)) {
            break;
          }
          final pauseDay = s.dayNumberOf(today)!;
          lived[today] = pauseDay;
          s = _pause(s, today);
          expect(s.freezes.last.frozenFrom, today.addDays(1));
          expect(WinterArcRules.problemWith(s), isNull);
          // Paused: no reminder for any paused date in the horizon.
          final inPause = today.addDays(1 + random.nextInt(3));
          final plan = ReminderPlanner.plan(
            preferences: prefs,
            active: s,
            now: DateTime(inPause.year, inPause.month, inPause.day, 6),
          );
          expect(plan, isEmpty, reason: 'an open pause plans nothing');
          final k = random.nextInt(random.nextBool() ? 6 : 450);
          today = today.addDays(1 + k);
          s = _resume(s, today);
          paused += k;
          expect(WinterArcRules.problemWith(s), isNull);
          expect(s.pausedDays, paused);
          expect(s.endDate, day1.addDays(91 + paused));
          expect(s.dateOfDay(92), s.endDate);
          final brute = bruteChallengeDates(s);
          expect(brute, hasLength(92));
          for (final MapEntry(key: date, value: n) in lived.entries) {
            expect(s.dayNumberOf(date), n, reason: 'lived days never move');
            expect(brute[n - 1], date);
          }
          // Today continues from the day before the pause (days skipped
          // without logging are ordinary challenge days, not pauses).
          expect(s.dayNumberOf(today), pauseDay + 1);
          for (var i = 1; i < s.freezes.length; i++) {
            expect(
              s.freezes[i].frozenFrom.isAfter(s.freezes[i - 1].resumedOn!),
              isTrue,
              reason: 'F13: a lived day between two pauses',
            );
          }
          today = today.addDays(random.nextInt(3));
        }
      }
    });
  });

  group('wording (spec §§ 9.6–9.8)', () {
    test('dates, counts and the clock-guard refusal', () {
      final today = LocalDate(2026, 11, 13);
      expect(
        PauseCopy.intro(LocalDate(2026, 11, 14), today),
        'From tomorrow, Sat 14 Nov, your Arc stops counting days until you '
        'resume.',
      );
      expect(
        ResumeCopy.lastDay(LocalDate(2027, 1, 25), LocalDate(2026, 11, 20)),
        'Your new last day is Mon 25 Jan 2027.',
      );
      expect(
        ResumeCopy.becomes(LocalDate(2026, 11, 20), 26, 92),
        'Today, Fri 20 Nov, becomes Day 26 of 92.',
      );
      expect(ResumeCopy.pausedFor(6), 'You paused for 6 days.');
      expect(ResumeCopy.pausedFor(1), 'You paused for 1 day.');
      expect(
        PausedCopy.since(LocalDate(2026, 11, 14), 6, LocalDate(2026, 11, 20)),
        'Paused since Sat 14 Nov · 6 days',
      );
      expect(pausedTotalLabel(0), isNull);
      expect(pausedTotalLabel(9), 'Paused 9 days');
      expect(
        PauseCopy.clockBehind(
          ClockGuardBehind(
            today: LocalDate(2027, 3, 9),
            earliestSafe: LocalDate(2027, 3, 10),
            bound: ClockGuardBound.lastActivity,
          ),
        ),
        "Your phone's date (9 Mar) is earlier than your latest logged day "
        '(10 Mar). You can pause from 10 Mar. Nothing was changed.',
      );
      // Never "missed" or "No progress" for a paused date.
      for (final copy in [
        PauseCopy.neverMissed,
        PausedCopy.noCount,
        PausedCopy.habitsReadOnly,
        PausedCopy.journalReadOnly,
        PauseCopy.bannerTomorrow,
      ]) {
        expect(copy.toLowerCase(), isNot(contains('no progress')));
      }
    });
  });
}
