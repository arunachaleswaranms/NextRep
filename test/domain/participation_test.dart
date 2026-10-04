import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_rules.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/insights/insight_rules.dart';
import 'package:nextrep/domain/insights/insight_snapshot.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/journey/journey_overview.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/builders.dart' as b;
import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

final _oct1 = LocalDate(2026, 10, 1);
LocalDate _day(int n) => _oct1.addDays(n - 1);

WinterArcSession _seasonal({
  required int joinDay,
  int id = 1,
  WinterArcStatus status = WinterArcStatus.active,
}) => WinterArcSession(
  id: id,
  kind: ArcKind.seasonalWinter,
  startDate: _oct1,
  endDate: LocalDate(2026, 12, 31),
  status: status,
  createdAt: DateTime(2026, 10, 1),
  participationStartDate: _day(joinDay),
);

/// A seasonal arc joined on Day [joinDay], seen on Day [today], with two
/// habits (target 8, minimum 3). [done] lists, per day, the habits
/// completed; [modes] day modes; [xp] the ledger per day. Rows dated
/// before joining can be given to check that they're ignored.
ArcHistory _history({
  required int joinDay,
  required int today,
  WinterArcStatus status = WinterArcStatus.active,
  List<Habit>? habits,
  Map<int, List<String>> done = const {},
  Map<int, DayMode> modes = const {},
  Map<int, int> xp = const {},
}) {
  final list =
      habits ??
      [
        b.habit('water', target: 8, minimum: 3, sortOrder: 0),
        b.habit('junk', target: 8, minimum: 3, sortOrder: 1),
      ];
  final byId = {for (final h in list) h.id: h};
  return ArcHistory(
    session: _seasonal(joinDay: joinDay, status: status),
    today: _day(today),
    records: ArcRecords(
      habits: HabitHistory(habits: list),
      progress: [
        for (final MapEntry(key: n, value: ids) in done.entries)
          for (final id in ids)
            DailyHabitProgress(
              habitId: id,
              date: _day(n),
              currentValue: byId[id]!.target,
              completed: true,
              completedAt: _day(n).toLocalDateTime(),
            ),
      ],
      modes: {
        for (final MapEntry(key: n, value: m) in modes.entries) _day(n): m,
      },
      xpByDate: {
        for (final MapEntry(key: n, value: v) in xp.entries) _day(n): v,
      },
      totalXp: xp.values.fold(0, (a, v) => a + v),
    ),
  );
}

Map<int, List<String>> _allDone(Iterable<int> days) => {
  for (final d in days) d: const ['water', 'junk'],
};

Iterable<int> _range(int from, int to) =>
    Iterable.generate(to - from + 1, (i) => from + i);

void main() {
  group('participating dates', () {
    test(
      'pre-join dates are not elapsed; the join date is; the future is not',
      () {
        final history = _history(joinDay: 15, today: 20);
        expect(history.elapsedDates.first, _day(15));
        expect(history.elapsedDates.last, _day(20));
        expect(history.elapsedDates, hasLength(6));
        expect(history.elapsedDates.any((d) => d.isBefore(_day(15))), isFalse);
        expect(history.elapsedDates.any((d) => d.isAfter(_day(20))), isFalse);
        expect(_seasonal(joinDay: 15).isParticipatingOn(_day(14)), isFalse);
        expect(_seasonal(joinDay: 15).isBeforeJoining(_day(14)), isTrue);
        expect(_seasonal(joinDay: 15).isParticipatingOn(_day(15)), isTrue);
      },
    );

    test('a rolling arc participates from Day 1, exactly as before', () {
      final history = b.arcOf(today: 10);
      expect(history.elapsedDates.first, b.day1);
      expect(history.elapsedDates, hasLength(10));
    });

    test('pre-join days never break a habit streak', () {
      final history = _history(
        joinDay: 15,
        today: 17,
        done: _allDone(_range(15, 17)),
      );
      expect(history.habitStreak('water').current, 3);
      expect(history.habitStreak('water').best, 3);
    });

    test('pre-join days never lower consistency', () {
      final history = _history(
        joinDay: 15,
        today: 100,
        status: WinterArcStatus.completed,
        done: _allDone(_range(15, 92)),
      );
      final summary = ArcSummary.fromHistory(
        history,
        achievementsUnlocked: 0,
        achievementsTotal: 15,
      );
      expect(summary.totalDays, 92);
      expect(summary.daysElapsed, 78);
      expect(summary.fullDays, 78);
      expect(summary.consistencyPercent, 100);
    });

    test('rows dated before joining never become Perfect or Minimum Days', () {
      // Such rows can't be written by the app; even if present they are
      // outside the arc's participation.
      final history = _history(
        joinDay: 15,
        today: 16,
        done: _allDone([3, 4, 16]),
        modes: {4: DayMode.minimum},
      );
      expect(history.perfectDays.total, 1);
      final summary = ArcSummary.fromHistory(
        history,
        achievementsUnlocked: 0,
        achievementsTotal: 15,
      );
      expect(summary.minimumDaysCompleted, 0);
      expect(summary.habitsCompleted, 2);
    });

    test('pre-join reflections and XP earn nothing', () {
      final history = _history(joinDay: 50, today: 52, xp: {3: 5000, 50: 15});
      final earned = AchievementRules.evaluate(
        AchievementContext(
          history: history,
          reflectionDates: [_day(2), _day(3)],
        ),
      ).map((e) => e.key);
      expect(earned, isNot(contains(AchievementKey.firstReflection)));
      expect(earned, isNot(contains(AchievementKey.level5)));
      expect(earned, isNot(contains(AchievementKey.halfway)));
    });
  });

  group('Midwinter and Summit', () {
    test('Midwinter is never awarded for a Day 46 before joining', () {
      final history = _history(
        joinDay: 47,
        today: 100,
        status: WinterArcStatus.completed,
        done: _allDone(_range(47, 92)),
      );
      final earned = {
        for (final e in AchievementRules.evaluate(
          AchievementContext(history: history),
        ))
          e.key: e.earnedOn,
      };
      expect(earned, isNot(contains(AchievementKey.halfway)));
      // A late joiner who stays to the close still reaches the Summit.
      expect(earned[AchievementKey.summit], LocalDate(2026, 12, 31));
    });

    test('Midwinter unlocks on Day 46 when it is a participated date', () {
      for (final join in [1, 30, 46]) {
        final history = _history(joinDay: join, today: 50);
        final earned = {
          for (final e in AchievementRules.evaluate(
            AchievementContext(history: history),
          ))
            e.key: e.earnedOn,
        };
        expect(earned[AchievementKey.halfway], _day(46), reason: 'join $join');
      }
      final early = _history(joinDay: 30, today: 45);
      expect(
        AchievementRules.evaluate(AchievementContext(history: early))
            .map((e) => e.key),
        isNot(contains(AchievementKey.halfway)),
      );
    });
  });

  group('Journey', () {
    test('a seasonal Journey has 92 days; pre-join days are notJoined', () {
      final journey = JourneyOverview.fromHistory(
        _history(joinDay: 15, today: 20, done: _allDone([15, 16])),
      );
      final days = journey.days;
      expect(days, hasLength(92));
      expect(days.first.date, _oct1);
      expect(days.last.date, LocalDate(2026, 12, 31));
      for (final day in days.take(14)) {
        expect(day.state, JourneyDayState.notJoined, reason: '${day.date}');
        expect(day.record, isNull);
        expect(day.xpEarned, 0);
        expect(day.state.isFinal, isFalse);
      }
      expect(days[14].state, JourneyDayState.perfect); // Day 15
      expect(days[15].state, JourneyDayState.perfect);
      // A joined day without progress is missed, which notJoined never is.
      expect(days[16].state, JourneyDayState.missed);
      expect(days[16].state, isNot(JourneyDayState.notJoined));
      expect(days[19].state, JourneyDayState.today);
      expect(days[19].isToday, isTrue);
      expect(days.skip(20).every((d) => d.isFuture), isTrue);
      expect((journey.position as ArcInProgress).dayNumber, 20);
    });

    test('a rolling Journey has no notJoined days', () {
      final journey = JourneyOverview.fromHistory(b.arcOf(today: 5));
      expect(journey.days.where((d) => d.isNotJoined), isEmpty);
      expect(journey.days[0].state, JourneyDayState.missed);
    });
  });

  group('services', () {
    late TestApp app;

    setUp(
      () =>
          app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 15, 9))),
    );
    tearDown(() => app.db.close());

    test(
      'a late join tracks Day 15 normally and earns XP from Day 15 only',
      () async {
        final arc = await joinSeason(app, DateTime(2026, 10, 15));
        await completeAll(app);
        final today = await app.tracking.today();
        expect((today.position as ArcInProgress).dayNumber, 15);
        expect(today.isPerfect, isTrue);
        expect(today.totalXp, 4 * 15 + 30);
        final history = await app.tracking.historyFor(arc.id);
        expect(history.elapsedDates, [LocalDate(2026, 10, 15)]);
        expect(history.records.xpByDate.keys, [LocalDate(2026, 10, 15)]);
      },
    );

    test(
      'a date before joining is never writable, even if the clock goes back',
      () async {
        await joinSeason(app, DateTime(2026, 10, 15));
        // E.g. a time-zone change across midnight.
        app.clock.current = DateTime(2026, 10, 14, 23, 30);
        final date = app.clock.today();
        await expectLater(
          app.tracking.perform(
            habitId: 'workout',
            action: HabitAction.increment,
            date: date,
          ),
          _failsWith(DomainRule.arcNotRunningToday),
        );
        await expectLater(
          app.tracking.activateMinimumDay(date: date),
          _failsWith(DomainRule.arcNotRunningToday),
        );
        final arc = (await app.sessions.currentSession())!;
        await expectLater(
          app.reflections.save(
            sessionId: arc.id,
            date: date,
            draft: const ReflectionDraft(mood: Mood.good),
          ),
          _failsWith(DomainRule.reflectionNotAvailable),
        );
        expect((await app.reflections.journal()).canWriteToday, isFalse);
        expect(await app.progress.totalXp(arc.id), 0);
      },
    );

    test(
      'a late-joined season completes with its participation summary',
      () async {
        final arc = await joinSeason(app, DateTime(2026, 11, 20));
        await completeAll(app);
        app.clock.current = DateTime(2027, 1, 1, 9);
        await app.lifecycle.reconcile();
        await app.achievements.reconcile();
        final card = await app.history.card(arc.id);
        expect(card.session.status, WinterArcStatus.completed);
        expect(card.summary.totalDays, 92);
        expect(card.summary.daysElapsed, 42); // 20 Nov – 31 Dec
        expect(card.summary.fullDays, 1);
        expect(card.summary.consistencyPercent, 2);
        final unlocks = {
          for (final u in await app.achievementStore.unlocks(arc.id)) u.key,
        };
        expect(unlocks, contains(AchievementKey.summit));
        expect(unlocks, isNot(contains(AchievementKey.halfway)));
      },
    );
  });

  group('Insights', () {
    InsightArc arc(ArcHistory history, {List<MoodMark> moods = const []}) =>
        InsightArc(history: history, moods: moods);

    test('pre-join dates are excluded from elapsed days and denominators', () {
      final s = InsightRules.compute([
        arc(
          _history(joinDay: 15, today: 24, done: _allDone(_range(15, 19))),
          moods: [
            MoodMark(date: _day(5), mood: Mood.good), // before joining
            MoodMark(date: _day(16), mood: Mood.good),
          ],
        ),
      ]);
      expect(s.overall.elapsedDays, 10); // Day 15 – 24, not 24
      expect(s.overall.fullDays, 5);
      expect(s.overall.consistencyPercent, 50);
      expect(s.overall.activeDay, 24, reason: 'the season day, not a count');
      expect(s.overall.reflectionCount, 1);
      final water = s.habits.singleWhere((h) => h.habitId == 'water');
      expect(water.applicableDays, 10);
      expect(water.completedDays, 5);
    });

    test('future dates of an active season are excluded', () {
      final s = InsightRules.compute([
        arc(_history(joinDay: 1, today: 3, done: _allDone([1, 2, 3]))),
      ]);
      expect(s.overall.elapsedDays, 3);
      expect(s.overall.consistencyPercent, 100);
    });

    test(
      'rolling + seasonal consistency is weighted by participating days',
      () {
        // Rolling: 92 elapsed, 46 full. Seasonal: joined Day 47, 46 elapsed,
        // all 46 full. (46 + 46) / (92 + 46) = 66%.
        final rolling = b.arcOf(today: 200);
        final rollingDone = InsightArc(
          history: ArcHistory(
            session: WinterArcSession(
              id: 1,
              kind: ArcKind.rolling92,
              startDate: LocalDate(2025, 1, 1),
              endDate: WinterArcRules.endDateFor(LocalDate(2025, 1, 1)),
              status: WinterArcStatus.completed,
              createdAt: DateTime(2025),
              participationStartDate: LocalDate(2025, 1, 1),
            ),
            today: LocalDate(2026, 1, 1),
            records: ArcRecords(
              habits: rolling.records.habits,
              progress: [
                for (var i = 0; i < 46; i++)
                  for (final id in ['water', 'junk'])
                    b.progress(id, LocalDate(2025, 1, 1).addDays(i), 8),
              ],
              modes: const {},
              xpByDate: const {},
              totalXp: 0,
            ),
          ),
          moods: const [],
        );
        final seasonal = arc(
          _history(
            joinDay: 47,
            today: 100,
            status: WinterArcStatus.completed,
            done: _allDone(_range(47, 92)),
          ),
        );
        final s = InsightRules.compute([rollingDone, seasonal]);
        expect(s.overall.elapsedDays, 92 + 46);
        expect(s.overall.fullDays, 92);
        expect(s.overall.consistencyPercent, 66);
      },
    );

    test('a timeBefore habit counts like any other habit', () {
      final sleep = Habit(
        id: 'sleep_before',
        title: 'Sleep Before Target',
        type: HabitType.timeBefore,
        target: NightTime(23, 30).value,
        minimumTarget: NightTime(23, 30).value,
        iconKey: 'sleep',
        enabled: true,
        sortOrder: 0,
        createdAt: DateTime(2026, 10, 1),
      );
      final history = ArcHistory(
        session: _seasonal(joinDay: 1),
        today: _day(3),
        records: ArcRecords(
          habits: HabitHistory(habits: [sleep]),
          progress: [
            // Day 1 on time; Day 2 logged late (useful data, not done).
            DailyHabitProgress(
              habitId: sleep.id,
              date: _day(1),
              currentValue: NightTime(23, 10).value,
              completed: true,
              completedAt: _day(1).toLocalDateTime(),
            ),
            DailyHabitProgress(
              habitId: sleep.id,
              date: _day(2),
              currentValue: NightTime(0, 40).value,
              completed: false,
            ),
          ],
          modes: const {},
          xpByDate: const {},
          totalXp: 0,
        ),
      );
      final s = InsightRules.compute([arc(history)]);
      final insight = s.habits.single;
      expect(insight.applicableDays, 3);
      expect(insight.completedDays, 1);
      expect(s.overall.fullDays, 1);
    });

    test('custom habits: one stable id is one habit; same titles stay apart; '
        'a rename keeps the lineage', () {
      const reused = 'custom_0123456789abcdef0123456789abcdef';
      const other = 'custom_fedcba9876543210fedcba9876543210';
      Habit custom(String id, String title) => Habit(
        id: id,
        title: title,
        type: HabitType.binary,
        target: 1,
        minimumTarget: 1,
        iconKey: 'star',
        enabled: true,
        sortOrder: id == reused ? 0 : 1,
        createdAt: DateTime(2026),
      );
      expect(SetupHabitRules.isCustomId(reused), isTrue);
      final first = _history(
        joinDay: 1,
        today: 100,
        status: WinterArcStatus.completed,
        habits: [custom(reused, 'Reading')],
        done: {
          1: const [reused],
          2: const [reused],
        },
      );
      final second = ArcHistory(
        session: WinterArcSession(
          id: 2,
          kind: ArcKind.rolling92,
          startDate: LocalDate(2027, 2, 1),
          endDate: WinterArcRules.endDateFor(LocalDate(2027, 2, 1)),
          status: WinterArcStatus.active,
          createdAt: DateTime(2027, 2, 1),
          participationStartDate: LocalDate(2027, 2, 1),
        ),
        today: LocalDate(2027, 2, 2),
        records: ArcRecords(
          habits: HabitHistory(
            habits: [custom(reused, 'Deep Reading'), custom(other, 'Reading')],
          ),
          progress: [
            b.progress(reused, LocalDate(2027, 2, 1), 1),
            b.progress(other, LocalDate(2027, 2, 2), 1),
          ],
          modes: const {},
          xpByDate: const {},
          totalXp: 0,
        ),
      );
      final s = InsightRules.compute([arc(first), arc(second)]);
      HabitInsight byId(String id) =>
          s.habits.singleWhere((h) => h.habitId == id);
      expect(s.habits, hasLength(2));
      expect(byId(reused).applicableDays, 92 + 2);
      expect(byId(reused).completedDays, 3);
      expect(byId(reused).arcCount, 2);
      expect(byId(reused).title, 'Deep Reading', reason: 'latest name');
      expect(byId(other).applicableDays, 2);
      expect(byId(other).completedDays, 1);
      expect(byId(other).title, 'Reading');
    });

    test('setup sessions are still excluded', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 9, 5, 9)));
      addTearDown(app.db.close);
      await app.winterArc.startNewArc(
        NewArcBaseline.fresh,
        kind: ArcKind.seasonalWinter,
      );
      expect((await app.insights.snapshot()).isEmpty, isTrue);
    });
  });
}
