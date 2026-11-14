import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_rules.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/insights/insight_rules.dart';
import 'package:nextrep/domain/insights/insight_snapshot.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/streak_rules.dart';
import 'package:nextrep/domain/reminder/hydration_planner.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/builders.dart' as b;
import '../support/lifecycle_arcs.dart';

/// What a date's record holds in these synthetic histories.
enum _Day { perfect, minimumFull, partial, empty }

/// [session]'s history on [today] with two habits (target 8, minimum 3):
/// [days] gives each listed date's outcome, [xp] the ledger per date.
ArcHistory _history(
  WinterArcSession session,
  LocalDate today, {
  Map<LocalDate, _Day> days = const {},
  Map<LocalDate, int> xp = const {},
}) {
  final habits = [
    b.habit('water', target: 8, minimum: 3, sortOrder: 0),
    b.habit('junk', target: 8, minimum: 3, sortOrder: 1),
  ];
  return ArcHistory(
    session: session,
    today: today,
    records: ArcRecords(
      habits: HabitHistory(habits: habits),
      progress: <DailyHabitProgress>[
        for (final MapEntry(key: date, value: day) in days.entries)
          ...switch (day) {
            _Day.perfect => [
              b.progress('water', date, 8),
              b.progress('junk', date, 8),
            ],
            _Day.minimumFull => [
              b.progress('water', date, 3),
              b.progress('junk', date, 3),
            ],
            _Day.partial => [b.progress('water', date, 2, completed: false)],
            _Day.empty => <DailyHabitProgress>[],
          },
      ],
      modes: {
        for (final MapEntry(key: date, value: day) in days.entries)
          if (day == _Day.minimumFull) date: DayMode.minimum,
      },
      xpByDate: xp,
      totalXp: xp.values.fold(0, (a, b) => a + b),
    ),
  );
}

/// Spec § 12.5.2's partition of `h.elapsedDates` on `h.today`.
({List<LocalDate> settled, List<LocalDate> open}) _partition(ArcHistory h) {
  final open = h.isTodayOpen ? [h.today] : <LocalDate>[];
  return (
    settled: [
      for (final d in h.elapsedDates)
        if (!open.contains(d)) d,
    ],
    open: open,
  );
}

bool _full(ArcHistory h, LocalDate d) =>
    h.recordOn(d).isPerfect || h.recordOn(d).isMinimumComplete;

/// Spec § 12.5.1's four XP groups.
({int settled, int today, int future, int other}) _xpGroups(ArcHistory h) {
  final s = h.session;
  final t = h.today;
  final ended = s.status == WinterArcStatus.ended;
  var settled = 0, today = 0, future = 0, other = 0;
  for (final MapEntry(key: d, value: amount) in h.records.xpByDate.entries) {
    final part = s.isParticipatingOn(d);
    if (d.isAfter(t)) {
      future += amount;
    } else if (!part) {
      other += amount;
    } else if (d.isBefore(t) || ended) {
      settled += amount;
    } else {
      today += amount;
    }
  }
  return (settled: settled, today: today, future: future, other: other);
}

ArcSummary _summary(ArcHistory h) =>
    ArcSummary.fromHistory(h, achievementsUnlocked: 0, achievementsTotal: 0);

/// Checks identities 1–3 of spec § 12.5.2 and the XP split of § 12.5.1.
void _expectIdentities(ArcHistory h) {
  final at = '${h.session.status.name} ${h.session.freezes} on ${h.today}';
  final (:settled, :open) = _partition(h);
  final summary = _summary(h);
  final s = h.session;
  // The partition: disjoint, covers the elapsed dates, nothing else in it.
  expect(settled.toSet().intersection(open.toSet()), isEmpty, reason: at);
  expect({...settled, ...open}, h.elapsedDates.toSet(), reason: at);
  for (final d in h.elapsedDates) {
    expect(s.isFrozenOn(d), isFalse, reason: '$at: paused $d');
    expect(s.isBeforeJoining(d), isFalse, reason: '$at: neutral $d');
    expect(d.isAfter(h.today), isFalse, reason: '$at: future $d');
    if (s.closedOn case final c?) {
      expect(d.isAfter(c), isFalse, reason: '$at: not reached $d');
    }
  }
  if (s.status == WinterArcStatus.ended) expect(open, isEmpty, reason: at);
  // 1. Day count.
  expect(settled.length + open.length, h.elapsedDates.length, reason: at);
  expect(summary.daysElapsed, h.elapsedDates.length, reason: at);
  // 2. Full days and consistency, with no division by zero.
  final fs = settled.where((d) => _full(h, d)).length;
  final fo = open.where((d) => _full(h, d)).length;
  expect(fs + fo, summary.fullDays, reason: at);
  if (h.elapsedDates.isEmpty) {
    expect(summary.consistencyPercent, 0, reason: at);
  } else {
    expect(
      (100 * (fs + fo)) ~/ (settled.length + open.length),
      summary.consistencyPercent,
      reason: at,
    );
  }
  // 3. Perfect Days, each counted once.
  final ps = settled.where((d) => h.recordOn(d).isPerfect).length;
  final po = open.where((d) => h.recordOn(d).isPerfect).length;
  expect(ps + po, h.perfectDays.total, reason: at);
  // XP: four exhaustive, exclusive groups; group A over S, B over O.
  final xp = _xpGroups(h);
  expect(
    xp.settled + xp.today + xp.future + xp.other,
    h.records.totalXp,
    reason: at,
  );
  expect(xp.other, 0, reason: '$at: no XP on a non-participating date');
  int ledger(List<LocalDate> dates) =>
      dates.fold(0, (sum, d) => sum + (h.records.xpByDate[d] ?? 0));
  expect(xp.settled, ledger(settled), reason: at);
  expect(xp.today, ledger(open), reason: at);
}

void main() {
  group('status classes', () {
    test('unfinished, finished, completed and writable stay distinct', () {
      expect(
        {
          for (final s in WinterArcStatus.values)
            s: (s.isUnfinished, s.isFinished),
        },
        {
          WinterArcStatus.setup: (true, false),
          WinterArcStatus.active: (true, false),
          WinterArcStatus.completed: (false, true),
          WinterArcStatus.ended: (false, true),
        },
      );
      // Persisted by name: never renamed.
      expect(WinterArcStatus.values.map((s) => s.name), [
        'setup',
        'active',
        'completed',
        'ended',
      ]);
    });

    test('an ended arc opens its read-only summary', () {
      final ended = rollingArc(
        LocalDate(2026, 10, 7),
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 10, 8),
        id: 9,
      );
      expect(AppRoutes.forSession(ended), AppRoutes.arc(9));
    });
  });

  group('ended arcs: streaks and Journey (spec § 12.5.2, R23, F4-16)', () {
    final start = LocalDate(2026, 10, 7);
    final closed = LocalDate(2026, 10, 9); // Day 3
    final ended = rollingArc(
      start,
      status: WinterArcStatus.ended,
      closedOn: closed,
    );

    test('an unachieved closedOn is a miss, never pending', () {
      final h = _history(
        ended,
        closed,
        days: {start: _Day.perfect, start.addDays(1): _Day.perfect},
      );
      expect(h.isTodayOpen, isFalse);
      expect(h.habitMarks('water'), [
        StreakMark.hit,
        StreakMark.hit,
        StreakMark.miss,
      ]);
      expect(h.perfectMarks.last, StreakMark.miss);
      expect(h.habitStreak('water').current, 0);
      // The same day on an active arc is pending and keeps the streak.
      final active = _history(
        rollingArc(start),
        closed,
        days: {start: _Day.perfect, start.addDays(1): _Day.perfect},
      );
      expect(active.habitMarks('water').last, StreakMark.pending);
      expect(active.habitStreak('water').current, 2);
    });

    test('Journey: closedOn takes its final state; later days not reached', () {
      final h = _history(
        ended,
        closed,
        days: {start: _Day.perfect, closed: _Day.partial},
      );
      final days = h.journey();
      expect(days, hasLength(92));
      expect(days[0].state, JourneyDayState.perfect);
      expect(days[1].state, JourneyDayState.missed);
      expect(days[2].state, JourneyDayState.partial, reason: 'not "today"');
      expect(days[2].isToday, isTrue);
      expect(days.skip(3).map((d) => d.state).toSet(), {
        JourneyDayState.notReached,
      });
      expect(days.skip(3).every((d) => d.isFuture && d.record == null), isTrue);
      // Viewed on a not-reached date, no day is "today".
      final midway = _history(ended, start.addDays(20));
      expect(midway.journey().where((d) => d.isToday), isEmpty);
      // Long after its planned end, no not-reached day turns into a miss.
      final later = _history(ended, LocalDate(2027, 6, 1));
      expect(
        later.journey().where((d) => d.state == JourneyDayState.missed),
        hasLength(3),
      );
      expect(
        later.journey().where((d) => d.state == JourneyDayState.notReached),
        hasLength(89),
      );
    });

    test('a Perfect Day on closedOn is counted once', () {
      final h = _history(ended, closed, days: {closed: _Day.perfect});
      expect(h.perfectDays.total, 1);
      expect(_summary(h).fullDays, 1);
      _expectIdentities(h);
    });
  });

  group('paused arcs: streaks and Journey', () {
    final start = LocalDate(2027, 3, 1);
    final paused = rollingArc(
      start,
      freezes: [closedFreeze(LocalDate(2027, 3, 4), 9)], // after Day 3
    );

    test('a streak continues across a pause without growing or breaking', () {
      final h = _history(
        paused,
        paused.dateOfDay(5)!, // 14 March
        days: {
          for (final d in [1, 2, 3, 4, 5]) paused.dateOfDay(d)!: _Day.perfect,
        },
      );
      expect(h.elapsedDates, hasLength(5));
      expect(h.habitStreak('water'), const Streak(current: 5, best: 5));
      expect(h.perfectDays.streak, const Streak(current: 5, best: 5));
    });

    test('Journey lists 92 challenge days on their mapped dates', () {
      final h = _history(paused, LocalDate(2027, 3, 14)); // Day 4
      final days = h.journey();
      expect(days, hasLength(92));
      expect(days[3].date, LocalDate(2027, 3, 13));
      expect(days[3].isToday, isFalse);
      expect(days[4].date, LocalDate(2027, 3, 14));
      expect(days[4].state, JourneyDayState.today);
      expect(days.last.date, paused.endDate);
      expect(days.any((d) => paused.isFrozenOn(d.date!)), isFalse);
    });

    test('an open pause: undated days are upcoming, never invented', () {
      final open = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 4))],
      );
      final h = _history(open, LocalDate(2027, 5, 1));
      final days = h.journey();
      expect(days.take(3).map((d) => d.date), [
        start,
        start.addDays(1),
        start.addDays(2),
      ]);
      expect(days.skip(3).every((d) => d.date == null), isTrue);
      expect(
        days.skip(3).every((d) => d.state == JourneyDayState.future),
        isTrue,
      );
      expect(h.isOver, isFalse);
      expect(h.isTodayOpen, isFalse, reason: 'a paused date is not open');
    });
  });

  group('day partition and XP split for every status (spec § 12.5)', () {
    test('generated arcs and every date from before to after', () {
      final g = ArcGenerator(1252);
      final arcs = <WinterArcSession>[
        for (var i = 0; i < 25; i++) g.pausedRolling(),
        for (var i = 0; i < 15; i++) g.plainRolling(),
        for (var i = 0; i < 15; i++) g.plainSeasonal(),
      ];
      // Ended arcs: each closes on one of its challenge dates.
      for (var i = 0; i < 25; i++) {
        final WinterArcSession source;
        if (i.isEven) {
          source = g.pausedRolling(allowOpen: false);
        } else {
          final year = 2019 + g.nextInt(18);
          source = seasonalArc(
            year,
            joined: LocalDate(year, 10, 1).addDays(g.nextInt(60)),
          );
        }
        final dates = source.participatingDatesThrough(source.endDate);
        // Restart closes on a lived day, never before the last resume.
        final lastResume = source.freezes.lastOrNull?.resumedOn;
        final closable = [
          for (final d in dates)
            if (lastResume == null || !d.isBefore(lastResume)) d,
        ];
        final closed = closable[g.nextInt(closable.length)];
        arcs.add(
          WinterArcSession(
            id: 1,
            kind: source.kind,
            startDate: source.startDate,
            endDate: source.endDate,
            status: WinterArcStatus.ended,
            createdAt: source.createdAt,
            startedAt: source.startedAt,
            participationStartDate: source.participationStartDate,
            freezes: source.freezes,
            closedOn: closed,
          ),
        );
      }
      for (final s in arcs) {
        expect(WinterArcRules.problemWith(s), isNull, reason: '$s');
        if (s.status == WinterArcStatus.setup) continue;
        // Records and XP on every date the arc took part in.
        final lived = s.participatingDatesThrough(s.endDate);
        final days = {
          for (final d in lived) d: _Day.values[g.nextInt(_Day.values.length)],
        };
        final xp = {for (final d in lived) d: 15 * (1 + g.nextInt(5))};
        final last =
            s.closedOn ??
            (s.hasOpenFreeze ? lived.last.addDays(30) : s.endDate);
        for (
          var t = s.startDate.addDays(-3);
          !t.isAfter(last.addDays(3));
          t = t.addDays(g.nextInt(3) + 1)
        ) {
          _expectIdentities(_history(s, t, days: days, xp: xp));
        }
      }
    });

    final oct7 = LocalDate(2026, 10, 7);

    test('§ 12.5.2 examples E, F and G: an ended arc', () {
      final s = rollingArc(
        oct7,
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 10, 8),
      );
      final days = {oct7: _Day.partial, LocalDate(2026, 10, 8): _Day.perfect};
      for (final (t, elapsed, full, perfect, percent) in [
        (LocalDate(2026, 10, 8), 2, 1, 1, 50), // E
        (LocalDate(2026, 10, 20), 2, 1, 1, 50), // F
        (LocalDate(2026, 10, 7), 1, 0, 0, 0), // G
      ]) {
        final h = _history(s, t, days: days);
        final summary = _summary(h);
        expect(_partition(h).open, isEmpty);
        expect(summary.daysElapsed, elapsed, reason: '$t');
        expect(summary.fullDays, full, reason: '$t');
        expect(h.perfectDays.total, perfect, reason: '$t');
        expect(summary.consistencyPercent, percent, reason: '$t');
      }
    });

    test('§ 12.5.2 examples D′ and D: scheduled, then paused', () {
      final start = LocalDate(2027, 3, 1);
      final days = <LocalDate, _Day>{
        for (var d = 1; d <= 9; d++)
          start.addDays(d - 1): d <= 4
              ? _Day.perfect
              : d <= 6
              ? _Day.minimumFull
              : _Day.partial,
        LocalDate(2027, 3, 10): _Day.partial,
      };
      final scheduled = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      final dPrime = _history(scheduled, LocalDate(2027, 3, 10), days: days);
      expect(_partition(dPrime).settled, hasLength(9));
      expect(_partition(dPrime).open, [LocalDate(2027, 3, 10)]);
      expect(_summary(dPrime).fullDays, 6);
      expect(dPrime.perfectDays.total, 4);
      expect(_summary(dPrime).consistencyPercent, 60);
      for (final t in [15, 20, 31]) {
        final d = _history(scheduled, LocalDate(2027, 3, t), days: days);
        expect(_partition(d).settled, hasLength(10));
        expect(_partition(d).open, isEmpty);
        expect(_summary(d).fullDays, 6);
        expect(d.perfectDays.total, 4);
        expect(_summary(d).consistencyPercent, 60);
      }
    });

    test('§ 12.5.2 examples H and I: late join; no elapsed day', () {
      final season = seasonalArc(2026, joined: LocalDate(2026, 10, 18));
      final h = _history(
        season,
        LocalDate(2026, 10, 21),
        days: {
          LocalDate(2026, 10, 18): _Day.perfect,
          LocalDate(2026, 10, 19): _Day.partial,
          LocalDate(2026, 10, 20): _Day.perfect,
        },
      );
      expect(_partition(h).settled, hasLength(3));
      expect(_partition(h).open, hasLength(1));
      expect(_summary(h).consistencyPercent, 50);
      final none = _history(rollingArc(oct7), LocalDate(2026, 10, 6));
      expect(none.elapsedDates, isEmpty);
      expect(_summary(none).consistencyPercent, 0);
      _expectIdentities(none);
    });

    test('§ 12.5.1 examples D–H: the XP groups of ended and paused arcs', () {
      final ended = rollingArc(
        oct7,
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 11, 12),
      );
      final ledger = {
        LocalDate(2026, 11, 10): 2325,
        LocalDate(2026, 11, 11): 60,
        LocalDate(2026, 11, 12): 45,
      };
      for (final (t, a, c) in [
        (LocalDate(2026, 11, 12), 2430, 0), // D
        (LocalDate(2026, 11, 20), 2430, 0), // E
        (LocalDate(2026, 11, 11), 2385, 45), // F
        (LocalDate(2026, 11, 10), 2325, 105), // H
      ]) {
        final xp = _xpGroups(_history(ended, t, xp: ledger));
        expect(xp, (settled: a, today: 0, future: c, other: 0), reason: '$t');
      }
      final start = LocalDate(2027, 3, 1);
      final resumed = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)],
      );
      final g = {
        for (var d = 0; d < 10; d++) start.addDays(d): 90,
        LocalDate(2027, 3, 20): 105,
        LocalDate(2027, 3, 21): 60,
      };
      expect(_xpGroups(_history(resumed, LocalDate(2027, 3, 21), xp: g)), (
        settled: 1005,
        today: 60,
        future: 0,
        other: 0,
      ));
      final pausedNow = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      expect(
        _xpGroups(
          _history(
            pausedNow,
            LocalDate(2027, 3, 15),
            xp: {for (var d = 0; d < 10; d++) start.addDays(d): 90},
          ),
        ),
        (settled: 900, today: 0, future: 0, other: 0),
      );
    });
  });

  group('achievements', () {
    List<EarnedAchievement> earned(ArcHistory h) =>
        AchievementRules.evaluate(AchievementContext(history: h));
    LocalDate? on(List<EarnedAchievement> list, AchievementKey key) =>
        list.where((e) => e.key == key).firstOrNull?.earnedOn;

    test('an ended arc never earns Summit, even after its planned end', () {
      final start = LocalDate(2026, 7, 1);
      final ended = rollingArc(
        start,
        status: WinterArcStatus.ended,
        closedOn: start.addDays(80),
      );
      final h = _history(ended, LocalDate(2027, 6, 1));
      expect(h.isOver, isTrue);
      expect(on(earned(h), AchievementKey.summit), isNull);
      // Its milestones up to closedOn are earned on their own dates.
      expect(on(earned(h), AchievementKey.day75), start.addDays(74));
      // A completed arc of the same dates earns Summit on its last day.
      final completed = rollingArc(start, status: WinterArcStatus.completed);
      expect(
        on(
          earned(_history(completed, LocalDate(2027, 6, 1))),
          AchievementKey.summit,
        ),
        completed.endDate,
      );
    });

    test('a day milestone after a pause is earned on its mapped date', () {
      final start = LocalDate(2027, 3, 1);
      final resumed = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)],
      );
      final h = _history(resumed, LocalDate(2027, 3, 30));
      expect(on(earned(h), AchievementKey.day14), LocalDate(2027, 3, 23));
      final paused = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      expect(
        on(
          earned(_history(paused, LocalDate(2028, 3, 1))),
          AchievementKey.day14,
        ),
        isNull,
        reason: 'Day 14 has no date until the arc resumes',
      );
      expect(
        on(
          earned(_history(paused, LocalDate(2028, 3, 1))),
          AchievementKey.summit,
        ),
        isNull,
        reason: 'a paused arc is not over',
      );
    });

    test('an ended arc does not reach a later day milestone', () {
      final ended = rollingArc(
        LocalDate(2026, 7, 1),
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 7, 10),
      );
      final list = earned(_history(ended, LocalDate(2027, 1, 1)));
      expect(on(list, AchievementKey.day14), isNull);
    });
  });

  group('insights', () {
    test('an ended arc is neither completed nor active; its days count', () {
      final completed = rollingArc(
        LocalDate(2026, 1, 1),
        status: WinterArcStatus.completed,
        id: 1,
      );
      final ended = rollingArc(
        LocalDate(2026, 5, 1),
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 5, 10),
        id: 2,
      );
      final active = rollingArc(LocalDate(2026, 10, 1), id: 3);
      final today = LocalDate(2026, 10, 5);
      final snapshot = InsightRules.compute([
        for (final s in [completed, ended, active])
          InsightArc(history: _history(s, today)),
      ]);
      expect(snapshot.overall.arcCount, 3);
      expect(snapshot.overall.completedArcs, 1);
      expect(snapshot.overall.activeArc?.id, 3);
      expect(snapshot.overall.activeDay, 5);
      expect(snapshot.overall.elapsedDays, 92 + 10 + 5);
    });

    test('with only an ended arc, nothing is active', () {
      final ended = rollingArc(
        LocalDate(2026, 5, 1),
        status: WinterArcStatus.ended,
        closedOn: LocalDate(2026, 5, 10),
      );
      final snapshot = InsightRules.compute([
        InsightArc(history: _history(ended, LocalDate(2026, 10, 1))),
      ]);
      expect(snapshot.overall.activeArc, isNull);
      expect(snapshot.overall.completedArcs, 0);
    });
  });

  group('reminders and Hydration Coach skip paused dates', () {
    const prefs = ReminderPreferences(
      dailyEnabled: true,
      dailyTime: ReminderTime(20, 0),
      reflectionEnabled: true,
      reflectionTime: ReminderTime(21, 0),
    );

    test('with a freeze from tomorrow, only today is planned', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      final planned = ReminderPlanner.plan(
        preferences: prefs,
        active: s,
        now: DateTime(2027, 3, 10, 9),
      );
      expect(planned.map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
        LocalDate(2027, 3, 10),
      });
      expect(planned.first.title, 'Winter Arc · Day 10');
      expect(
        ReminderPlanner.plan(
          preferences: prefs,
          active: s,
          now: DateTime(2027, 3, 12, 9),
        ),
        isEmpty,
        reason: 'nothing while paused',
      );
    });

    test('after a resume, day numbers continue from the pause', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2027, 3, 11), 9)],
      );
      final planned = ReminderPlanner.plan(
        preferences: prefs,
        active: s,
        now: DateTime(2027, 3, 20, 9),
      );
      final daily = planned.where((r) => r.kind == ReminderKind.daily).toList();
      expect(daily.first.title, 'Winter Arc · Day 11');
      expect(daily, hasLength(ReminderPlanner.horizonDays));
    });

    test('Hydration Coach sees a paused date as not participating', () {
      final start = LocalDate(2027, 3, 1);
      final s = rollingArc(
        start,
        freezes: [openFreeze(LocalDate(2027, 3, 11))],
      );
      final records = _history(s, LocalDate(2027, 3, 10)).records;
      expect(
        HydrationDay.of(
          arc: s,
          records: records,
          date: LocalDate(2027, 3, 10),
        ).participating,
        isTrue,
      );
      expect(
        HydrationDay.of(
          arc: s,
          records: records,
          date: LocalDate(2027, 3, 11),
        ).participating,
        isFalse,
      );
    });
  });

  group('clock guard (addendum AD19), pure rule', () {
    final start = LocalDate(2026, 10, 7);
    final active = rollingArc(start);

    test('today at or after every recorded date is safe', () {
      final v = ArcClockGuard.check(
        session: active,
        lastActivityDate: LocalDate(2026, 10, 18),
        today: LocalDate(2026, 10, 18),
      );
      expect(v, isA<ClockGuardSafe>());
      expect(v.earliestSafe, LocalDate(2026, 10, 18));
    });

    test('activity after today refuses, naming the date (F1-6)', () {
      final v = ArcClockGuard.check(
        session: active,
        lastActivityDate: LocalDate(2026, 10, 18),
        today: LocalDate(2026, 10, 17),
      );
      expect(v, isA<ClockGuardBehind>());
      expect((v as ClockGuardBehind).bound, ClockGuardBound.lastActivity);
      expect(v.earliestSafe, LocalDate(2026, 10, 18));
    });

    test('a date before the participation start refuses', () {
      final v = ArcClockGuard.check(
        session: active,
        lastActivityDate: null,
        today: LocalDate(2026, 10, 6),
      );
      expect((v as ClockGuardBehind).bound, ClockGuardBound.participationStart);
    });

    test('a prior resume counts even with nothing logged since (F1-10)', () {
      final paused = rollingArc(
        start,
        freezes: [closedFreeze(LocalDate(2026, 10, 12), 6)], // resumed 18 Oct
      );
      final v = ArcClockGuard.check(
        session: paused,
        lastActivityDate: LocalDate(2026, 10, 11),
        today: LocalDate(2026, 10, 10),
      );
      expect((v as ClockGuardBehind).bound, ClockGuardBound.lastResume);
      expect(v.earliestSafe, LocalDate(2026, 10, 18));
    });

    test('a pause from the day after a safe date never overlaps', () {
      final g = ArcGenerator(19);
      var checked = 0;
      for (var i = 0; i < 400; i++) {
        final s = g.pausedRolling(allowOpen: false);
        final lived = s.participatingDatesThrough(s.endDate);
        final today = s.startDate.addDays(g.nextInt(s.calendarSpanInDays + 5));
        final lastActivity = lived.where((d) => !d.isAfter(today)).lastOrNull;
        final verdict = ArcClockGuard.check(
          session: s,
          lastActivityDate: lastActivity,
          today: today,
        );
        // Freeze needs a challenge day today and one left after it.
        if (!s.isParticipatingOn(today) ||
            !s.hasChallengeDayOnOrAfter(today.addDays(1))) {
          continue;
        }
        final withFreeze = s.copyWith(
          freezes: [...s.freezes, openFreeze(today.addDays(1))],
        );
        final valid = WinterArcRules.problemWith(withFreeze) == null;
        if (verdict.isSafe) {
          checked++;
          expect(valid, isTrue, reason: '${s.freezes} on $today');
        } else {
          // Refused exactly when a recorded resume is after today.
          expect(
            (verdict as ClockGuardBehind).bound,
            ClockGuardBound.lastResume,
          );
          expect(valid, isFalse, reason: 'it would overlap an earlier pause');
        }
      }
      expect(checked, greaterThan(50));
    });
  });
}
