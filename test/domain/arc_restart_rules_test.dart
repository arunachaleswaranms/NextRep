import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/arc_restart.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/arc_restart/restart_labels.dart';

/// Phase 12F pure rules (no database): the last lived day of spec § 6.2 /
/// addendum AD11 on synthetic arcs, the order of [ArcRestartRules.decide]'s
/// refusals, the new arc's baseline (AD11), the typed words (§ 6.6) and
/// the wording helpers. All data synthetic.

final start = LocalDate(2026, 10, 7);
LocalDate d(int n) => start.addDays(n - 1);

WinterArcSession rolling({
  List<ArcFreeze> freezes = const [],
  WinterArcStatus status = WinterArcStatus.active,
  LocalDate? closedOn,
  int id = 1,
}) => WinterArcSession(
  id: id,
  kind: ArcKind.rolling92,
  startDate: start,
  endDate: WinterArcRules.endDateFor(start)
      .addDays(ArcFreezeRules.closedPausedDays(freezes)),
  status: status,
  createdAt: DateTime(2026, 10, 7, 9),
  participationStartDate: start,
  startedAt: DateTime(2026, 10, 7, 9),
  freezes: freezes,
  closedOn: closedOn,
);

WinterArcSession seasonal({LocalDate? joined}) => WinterArcSession(
  id: 1,
  kind: ArcKind.seasonalWinter,
  startDate: LocalDate(2026, 10, 1),
  endDate: LocalDate(2026, 12, 31),
  status: WinterArcStatus.active,
  createdAt: DateTime(2026, 10, 1),
  participationStartDate: joined ?? LocalDate(2026, 10, 1),
  startedAt: DateTime(2026, 10, 1),
);

ArcFreeze freeze(LocalDate from, [LocalDate? resumed]) => ArcFreeze(
  frozenFrom: from,
  resumedOn: resumed,
  requestedAt: DateTime(2026, 10, 1),
  resumedAt: resumed == null ? null : DateTime(2026, 10, 2),
);

Habit habit(String id, int sort, {bool enabled = true, int target = 8}) =>
    Habit(
      id: id,
      title: 'Habit $id',
      type: HabitType.count,
      target: target,
      minimumTarget: 2,
      unit: 'glasses',
      iconKey: 'water',
      enabled: enabled,
      sortOrder: sort,
      createdAt: DateTime(2026, 10, 7),
    );

HabitHistory history({List<HabitRevision> revisions = const []}) =>
    HabitHistory(
      habits: [
        habit('b', 1),
        habit('a', 0),
        habit('custom_00ff', 2, enabled: false),
      ],
      revisions: revisions,
    );

RestartFacts facts(
  WinterArcSession session, {
  LocalDate? lastActivity,
  int? currentId = 1,
  HabitHistory? habits,
}) => RestartFacts(
  session: session,
  currentId: currentId,
  habits: habits ?? history(),
  lastActivityDate: lastActivity,
);

Matcher refused(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

void main() {
  group('lastLivedDay (§ 6.2, AD11)', () {
    LocalDate lived(
      WinterArcSession s,
      LocalDate today, [
      LocalDate? activity,
    ]) => ArcRestartRules.lastLivedDay(
      s,
      today: today,
      lastActivityDate: activity,
    );

    test('the table of § 6.2', () {
      final s = rolling();
      expect(lived(s, d(10), d(10)), d(10), reason: 'activity today');
      expect(lived(s, d(10), d(9)), d(9), reason: 'nothing today');
      expect(lived(s, d(10)), d(9), reason: 'no activity at all');
      expect(lived(s, d(1)), d(1), reason: 'Day 1, nothing logged');
      expect(lived(s, d(1), d(1)), d(1));
      expect(lived(s, d(92), d(92)), d(92), reason: 'Day 92 logged');
      expect(lived(s, d(92), d(91)), d(91), reason: 'Day 92 not logged');
      expect(lived(s, d(91)), d(90));
    });

    test('never a paused date: an open pause, a scheduled one, after '
        'earlier closed ones', () {
      final open = rolling(freezes: [freeze(d(14))]);
      for (final t in [d(14), d(15), d(40), d(400)]) {
        expect(lived(open, t, d(13)), d(13), reason: '$t');
      }
      final scheduled = rolling(freezes: [freeze(d(11))]);
      expect(lived(scheduled, d(10), d(10)), d(10));
      expect(lived(scheduled, d(10), d(9)), d(9));
      final both = rolling(freezes: [freeze(d(4), d(8)), freeze(d(12))]);
      expect(lived(both, d(20), d(11)), d(11));
      expect(both.dayNumberOf(d(11)), 7);
      expect(lived(both, d(9)), d(8), reason: 'first day after a pause');
      expect(lived(both, d(8)), d(3), reason: 'never the paused d(4)–d(7)');
    });

    test('Seasonal and a late join', () {
      final s = seasonal(joined: LocalDate(2026, 10, 20));
      expect(lived(s, LocalDate(2026, 10, 20)), LocalDate(2026, 10, 20));
      expect(lived(s, LocalDate(2026, 11, 14)), LocalDate(2026, 11, 13));
      expect(s.dayNumberOf(LocalDate(2026, 11, 13)), 44);
      expect(
        lived(s, LocalDate(2026, 12, 31), LocalDate(2026, 12, 31)),
        LocalDate(2026, 12, 31),
      );
    });

    test('a revision is never activity: only the activity date counts', () {
      // Revisions are not passed at all: lastActivityDate never holds one.
      expect(lived(rolling(), d(10), d(8)), d(9));
    });
  });

  group('decide: refusals, in order, write nothing (T1, T10, F2-14)', () {
    RestartPlan decide(
      RestartFacts f, {
      LocalDate? today,
      LocalDate? shownOn,
      LocalDate? shownClosedOn,
    }) {
      final t = today ?? d(10);
      return ArcRestartRules.decide(
        f,
        today: t,
        now: t.toLocalDateTime().add(const Duration(hours: 9)),
        shownOn: shownOn ?? t,
        shownClosedOn: shownClosedOn ?? d(9),
      );
    }

    test('a date not shown', () {
      expect(
        () => decide(facts(rolling()), shownOn: d(9)),
        refused(DomainRule.restartDateChanged),
      );
    });

    test('completed, or over today (Day 93 before the close-out)', () {
      expect(
        () => decide(facts(rolling(status: WinterArcStatus.completed))),
        refused(DomainRule.arcCompleted),
      );
      expect(
        () => decide(facts(rolling()), today: d(93), shownClosedOn: d(92)),
        refused(DomainRule.arcCompleted),
      );
    });

    test('not the active, unfinished arc', () {
      expect(
        () => decide(
          facts(
            rolling(status: WinterArcStatus.ended, closedOn: d(5)),
            currentId: 2,
          ),
        ),
        refused(DomainRule.restartUnavailable),
      );
      expect(
        () => decide(facts(rolling(), currentId: 2)),
        refused(DomainRule.restartUnavailable),
      );
      expect(
        () => decide(facts(rolling(), currentId: null)),
        refused(DomainRule.restartUnavailable),
      );
    });

    test('the clock guard: latest activity, latest resume, first day', () {
      expect(
        () => decide(facts(rolling(), lastActivity: d(11))),
        refused(DomainRule.clockBehindHistory),
      );
      expect(
        () => decide(
          facts(rolling(freezes: [freeze(d(4), d(12))])),
          shownClosedOn: d(3),
        ),
        refused(DomainRule.clockBehindHistory),
      );
      expect(
        () => decide(facts(rolling()), today: d(0), shownClosedOn: d(1)),
        refused(DomainRule.clockBehindHistory),
      );
    });

    test('a last day not shown (the arc changed while open)', () {
      expect(
        () => decide(facts(rolling(), lastActivity: d(10))),
        refused(DomainRule.restartDateChanged),
        reason: 'the screen said Day 9; a habit was logged today since',
      );
    });

    test('every habit off at its latest configuration', () {
      final off = HabitHistory(
        habits: [habit('a', 0)],
        revisions: [
          HabitRevision(
            habitId: 'a',
            effectiveFrom: d(11),
            config: const HabitConfig(
              target: 8,
              minimumTarget: 2,
              enabled: false,
            ),
            createdAt: DateTime(2026, 10, 16),
          ),
        ],
      );
      expect(
        () => decide(facts(rolling(), habits: off)),
        refused(DomainRule.noHabitsSelected),
      );
      expect(
        ArcRestartRules.blockerOn(rolling(), d(10), habits: off),
        RestartBlocker.noHabitsOn,
      );
    });

    test('activity on a non-lived date (damaged data) is refused rather '
        'than left after closedOn', () {
      // Activity dated on a paused date: impossible for the app to write.
      final s = rolling(freezes: [freeze(d(5))]);
      expect(
        () => decide(
          facts(s, lastActivity: d(7)),
          today: d(8),
          shownClosedOn: d(4),
        ),
        refused(DomainRule.invalidArc),
      );
    });
  });

  group('decide: the plan (§ 6.2, AD11)', () {
    test('the old arc: ended on the last lived day, open freeze removed, '
        'everything else as it was', () {
      final closed = freeze(d(3), d(5));
      final s = rolling(freezes: [closed, freeze(d(12))]);
      final plan = ArcRestartRules.decide(
        facts(s, lastActivity: d(11)),
        today: d(20),
        now: DateTime(2026, 10, 26, 9),
        shownOn: d(20),
        shownClosedOn: d(11),
      );
      expect(plan.ended.status, WinterArcStatus.ended);
      expect(plan.ended.closedOn, d(11));
      expect(plan.ended.freezes, [closed]);
      expect(plan.removedFreeze, d(12));
      expect(plan.ended.endDate, s.endDate, reason: 'planned end kept');
      expect(plan.ended.startDate, s.startDate);
      expect(plan.ended.participationStartDate, s.participationStartDate);
      expect(WinterArcRules.problemWith(plan.ended), isNull);
      final fresh = plan.startedAs(7);
      expect(fresh.id, 7);
      expect(fresh.kind, ArcKind.rolling92);
      expect(fresh.startDate, d(20));
      expect(fresh.endDate, d(20).addDays(91));
      expect(fresh.participationStartDate, d(20));
      expect(fresh.status, WinterArcStatus.active);
      expect(fresh.freezes, isEmpty);
      expect(fresh.closedOn, isNull);
      expect(WinterArcRules.problemWith(fresh), isNull);
    });

    test('Day 92: allowed, ended (never completed)', () {
      final plan = ArcRestartRules.decide(
        facts(rolling(), lastActivity: d(92)),
        today: d(92),
        now: DateTime(2027, 1, 6, 21),
        shownOn: d(92),
        shownClosedOn: d(92),
      );
      expect(plan.ended.status, WinterArcStatus.ended);
      expect(plan.ended.closedOn, d(92));
    });
  });

  group('baselineFrom (AD11): the latest configuration of every habit', () {
    test('ids, order, type, unit, icon, on/off; the latest revision, '
        'pending included; no revision copied', () {
      HabitRevision rev(String id, LocalDate from, int target, bool on) =>
          HabitRevision(
            habitId: id,
            effectiveFrom: from,
            config: HabitConfig(target: target, minimumTarget: 2, enabled: on),
            createdAt: DateTime(2026, 10, 7),
          );
      final h = history(
        revisions: [
          rev('a', d(3), 9, true),
          rev('a', d(11), 12, true), // waiting for tomorrow
          rev('a', d(6), 10, true),
          rev('custom_00ff', d(4), 5, true),
          rev('b', d(5), 8, false),
        ],
      );
      final at = DateTime(2026, 10, 16, 9);
      final baseline = ArcRestartRules.baselineFrom(h, createdAt: at);
      expect(baseline.map((x) => x.id), ['a', 'b', 'custom_00ff']);
      expect(baseline.map((x) => x.sortOrder), [0, 1, 2]);
      expect(baseline[0].target, 12, reason: 'the pending revision');
      expect(baseline[1].enabled, isFalse);
      expect(baseline[2].enabled, isTrue);
      expect(baseline[2].target, 5);
      for (final x in baseline) {
        final original = h.habit(x.id)!;
        expect(x.title, original.title);
        expect(x.type, original.type);
        expect(x.unit, original.unit);
        expect(x.iconKey, original.iconKey);
        expect(x.createdAt, at);
      }
      expect(h.latestConfig(h.habit('a')!).target, 12);
    });

    test('a habit with no revision keeps its baseline', () {
      final h = history();
      final baseline = ArcRestartRules.baselineFrom(h, createdAt: DateTime(1));
      expect(baseline[0].baseline, h.habit('a')!.baseline);
    });
  });

  group('preview', () {
    test('offers, closes, numbers the day; Day 92 and paused flags', () {
      RestartPreview preview(
        WinterArcSession s,
        LocalDate today, [
        LocalDate? activity,
      ]) => RestartPreview(
        session: s,
        today: today,
        blocker: ArcRestartRules.blockerOn(s, today),
        guard: ArcClockGuard.check(
          session: s,
          lastActivityDate: activity,
          today: today,
        ),
        habits: const [],
        lastActivityDate: activity,
      );
      final day37 = preview(rolling(), d(37), d(37));
      expect(day37.canRestart, isTrue);
      expect(day37.closedOn, d(37));
      expect(day37.closedDayNumber, 37);
      expect(day37.newLastDay, d(37).addDays(91));
      expect(day37.isLastDay, isFalse);
      expect(preview(rolling(), d(92)).isLastDay, isTrue);
      final paused = preview(rolling(freezes: [freeze(d(14))]), d(20), d(13));
      expect(paused.isPausedToday, isTrue);
      expect(paused.closedDayNumber, 13);
      final behind = preview(rolling(), d(9), d(10));
      expect(behind.canRestart, isFalse);
      expect(behind.closedOn, isNull);
      expect(
        preview(rolling(status: WinterArcStatus.completed), d(93)).blocker,
        RestartBlocker.notActive,
      );
    });
  });

  group('typed words (§ 6.6, § 9.11)', () {
    test('trimmed, then compared case-sensitively', () {
      for (final (input, ok) in [
        ('RESTART', true),
        (' RESTART ', true),
        ('\tRESTART\n', true),
        ('restart', false),
        ('Restart', false),
        ('RESTAR', false),
        ('RESTARTS', false),
        ('RE START', false),
        ('', false),
        ('   ', false),
      ]) {
        expect(typedWordMatches(input, RestartCopy.word), ok, reason: input);
      }
      expect(typedWordMatches(' DELETE ', DeleteArcCopy.word), isTrue);
      expect(typedWordMatches('delete', DeleteArcCopy.word), isFalse);
      expect(typedWordMatches('RESTART', DeleteArcCopy.word), isFalse);
    });
  });

  group('wording', () {
    test('ended early, counts with zero and one, XP with separators', () {
      final ended = rolling(status: WinterArcStatus.ended, closedOn: d(37));
      expect(endedEarlyLabel(ended), 'Ended early · Day 37 of 92');
      expect(endedEarlyLabel(rolling()), isNull);
      expect(DeleteArcCopy.status(ended), 'Ended early · Day 37 of 92');
      expect(
        DeleteArcCopy.status(rolling(status: WinterArcStatus.completed)),
        'Completed',
      );
      expect(
        DeleteArcCopy.progress(37, 2430),
        '37 days of progress and 2,430 XP',
      );
      expect(DeleteArcCopy.progress(1, 0), '1 day of progress and 0 XP');
      expect(DeleteArcCopy.achievements(0), '0 achievements');
      expect(DeleteArcCopy.achievements(1), '1 achievement');
      expect(DeleteArcCopy.reflections(0), '0 Journal reflections');
      expect(DeleteArcCopy.reflections(1), '1 Journal reflection');
      expect(
        RestartCopy.previous(37, 92, 2430),
        'Ended early · Day 37 of 92 · 2,430 XP',
      );
      expect(RestartCopy.intro(1), contains('your 1 habit,'));
      expect(
        RestartCopy.entry(seasonal()),
        'Start a Rolling Arc with this setup',
      );
      expect(RestartCopy.entry(rolling()), 'Restart with this setup');
      expect(RestartCopy.action(seasonal()), isNot(contains('Restart')));
      final behind = ArcClockGuard.check(
        session: rolling(),
        lastActivityDate: LocalDate(2026, 10, 18),
        today: LocalDate(2026, 10, 17),
      );
      expect(
        RestartCopy.clockBehind(behind as ClockGuardBehind),
        "Your phone's date (17 Oct) is earlier than your latest logged day "
        '(18 Oct). You can restart from 18 Oct. Nothing was changed.',
      );
    });
  });
}
