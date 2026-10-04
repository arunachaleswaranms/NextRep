import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/insights/insight_rules.dart';
import 'package:nextrep/domain/insights/insight_snapshot.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/builders.dart' as b;
import '../support/fakes.dart';

final _arcA = LocalDate(2025, 10, 1); // completed long ago
final _arcB = LocalDate(2026, 3, 1);

/// An arc starting on [start] with [habits] (target 8, minimum 3 unless
/// given). [done] lists, per day number, the habits completed that day (at
/// the day's target); [modes] sets day modes; [moods] the reflected days
/// and their mood (null: text only). [today] defaults to after the arc.
InsightArc _arc({
  required int id,
  required LocalDate start,
  WinterArcStatus status = WinterArcStatus.completed,
  int? todayDay,
  List<Habit>? habits,
  List<HabitRevision> revisions = const [],
  Map<int, List<String>> done = const {},
  Map<int, DayMode> modes = const {},
  int totalXp = 0,
  Map<int, Mood?> moods = const {},
}) {
  final list =
      habits ??
      [
        b.habit('water', target: 8, minimum: 3, sortOrder: 0),
        b.habit('junk', target: 8, minimum: 3, sortOrder: 1),
      ];
  LocalDate day(int n) => start.addDays(n - 1);
  final targets = {for (final h in list) h.id: h};
  return InsightArc(
    history: ArcHistory(
      session: WinterArcSession(
        id: id,
        kind: ArcKind.rolling92,
        participationStartDate: status == WinterArcStatus.setup ? null : start,
        startDate: start,
        endDate: WinterArcRules.endDateFor(start),
        status: status,
        createdAt: start.toLocalDateTime(),
        startedAt: status == WinterArcStatus.setup
            ? null
            : start.toLocalDateTime(),
      ),
      today: day(todayDay ?? 200),
      records: ArcRecords(
        habits: HabitHistory(habits: list, revisions: revisions),
        progress: [
          for (final MapEntry(key: n, value: ids) in done.entries)
            for (final id in ids)
              DailyHabitProgress(
                habitId: id,
                date: day(n),
                currentValue: modes[n] == DayMode.minimum
                    ? targets[id]!.minimumTarget
                    : targets[id]!.target,
                completed: true,
                completedAt: day(n).toLocalDateTime(),
              ),
        ],
        modes: {
          for (final MapEntry(key: n, value: mode) in modes.entries)
            day(n): mode,
        },
        xpByDate: {if (totalXp > 0) day(1): totalXp},
        totalXp: totalXp,
      ),
    ),
    moods: [
      for (final MapEntry(key: n, value: mood) in moods.entries)
        MoodMark(date: day(n), mood: mood),
    ],
  );
}

/// [count] consecutive day numbers from [from].
Iterable<int> _days(int from, int count) =>
    Iterable.generate(count, (i) => from + i);

HabitInsight _habit(InsightSnapshot s, String id) =>
    s.habits.singleWhere((h) => h.habitId == id);

void main() {
  group('scope', () {
    test('an arc in setup is excluded', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          status: WinterArcStatus.setup,
          done: {
            1: ['water'],
          },
        ),
      ]);
      expect(s.isEmpty, isTrue);
      expect(s.overall.elapsedDays, 0);
      expect(s.habits, isEmpty);
    });

    test('the active arc counts only up to today; future dates are '
        'never evaluated', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 5,
          done: {
            for (final n in [1, 2, 10, 50]) n: ['water', 'junk'],
          },
          moods: {2: Mood.good, 30: Mood.rough},
        ),
      ]);
      final o = s.overall;
      expect(o.elapsedDays, 5);
      expect(o.activeArc?.id, 1);
      expect(o.activeDay, 5);
      expect(o.completedArcs, 0);
      expect(o.perfectDays, 2, reason: 'days 10 and 50 are in the future');
      expect(_habit(s, 'water').applicableDays, 5);
      expect(_habit(s, 'water').completedDays, 2);
      expect(o.reflectionCount, 1);
      expect(s.moods.counts[Mood.rough], 0);
    });

    test('completed arcs are included in full', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          done: {
            for (final n in _days(1, 92)) n: ['water'],
          },
        ),
      ]);
      expect(s.overall.elapsedDays, 92);
      expect(s.overall.completedArcs, 1);
      expect(s.overall.activeArc, isNull);
      expect(_habit(s, 'water').completedDays, 92);
    });
  });

  group('consistency', () {
    test('is weighted by days across arcs, not an average of percentages', () {
      final s = InsightRules.compute([
        // 46 full days of 92: 50%.
        _arc(
          id: 1,
          start: _arcA,
          done: {
            for (final n in _days(1, 46)) n: ['water', 'junk'],
          },
        ),
        // 4 full days of 4: 100%.
        _arc(
          id: 2,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 4,
          done: {
            for (final n in _days(1, 4)) n: ['water', 'junk'],
          },
        ),
      ]);
      expect(s.overall.fullDays, 50);
      expect(s.overall.elapsedDays, 96);
      expect(s.overall.consistencyPercent, 52); // 50 / 96, not 75
      expect(s.overall.consistency, closeTo(50 / 96, 1e-9));
    });

    test('Perfect Days and completed Minimum Days are totalled', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          done: {
            1: ['water', 'junk'],
            2: ['water', 'junk'],
            3: ['water', 'junk'], // a Minimum Day, done at the minimum
            4: ['water'], // a Minimum Day, not complete
          },
          modes: {3: DayMode.minimum, 4: DayMode.minimum},
        ),
        _arc(
          id: 2,
          start: _arcB,
          done: {
            1: ['water', 'junk'],
          },
        ),
      ]);
      expect(s.overall.perfectDays, 3);
      expect(s.overall.minimumDaysCompleted, 1);
      expect(s.overall.fullDays, 4);
    });

    test('an empty history gives zeros and empty sections, never nonsense', () {
      final s = InsightRules.compute(const []);
      expect(s.isEmpty, isTrue);
      final o = s.overall;
      expect(o.elapsedDays, 0);
      expect(o.consistency, 0);
      expect(o.consistencyPercent, 0);
      expect(o.averageXpPerDay, 0);
      expect(o.reflectionRate, 0);
      expect(o.highestLevel, isNull);
      expect(s.habits, isEmpty);
      expect(s.mostConsistent, isNull);
      expect(s.bestStreak, isNull);
      expect(s.moods.isEmpty, isTrue);
      expect(s.moods.counts.values, everyElement(0));
    });

    test('XP totals, the highest level and XP per day', () {
      final s = InsightRules.compute([
        _arc(id: 1, start: _arcA, totalXp: 600), // level 3
        _arc(
          id: 2,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 8,
          totalXp: 300, // level 2
        ),
      ]);
      expect(s.overall.totalXp, 900);
      expect(s.overall.highestLevel, 3);
      expect(s.overall.averageXpPerDay, closeTo(900 / 100, 1e-9));
    });
  });

  group('habits', () {
    test('days a habit was disabled are not in its denominator', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          // junk is off from Day 3 to the end.
          revisions: [
            b.revision('junk', _arcA.addDays(2), target: 8, enabled: false),
          ],
          done: {
            1: ['junk'],
          },
        ),
      ]);
      final junk = _habit(s, 'junk');
      expect(junk.applicableDays, 2);
      expect(junk.completedDays, 1);
      expect(junk.completionPercent, 50);
      expect(_habit(s, 'water').applicableDays, 92);
    });

    test('a habit never enabled is left out', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          habits: [
            b.habit('water', target: 8, minimum: 3),
            b.habit('english', enabled: false, sortOrder: 1),
          ],
        ),
      ]);
      expect([for (final h in s.habits) h.habitId], ['water']);
    });

    test('completing the minimum on a Minimum Day counts as done', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          status: WinterArcStatus.active,
          todayDay: 2,
          done: {
            1: ['water'],
            2: ['water'],
          },
          modes: {2: DayMode.minimum},
        ),
      ]);
      expect(_habit(s, 'water').completedDays, 2);
      expect(_habit(s, 'water').completionPercent, 100);
    });

    test('the same stable id is one habit across arcs', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          done: {
            for (final n in _days(1, 10)) n: ['water'],
          },
        ),
        _arc(
          id: 2,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 10,
          done: {
            for (final n in _days(1, 5)) n: ['water'],
          },
        ),
      ]);
      final water = _habit(s, 'water');
      expect(s.habits.where((h) => h.habitId == 'water'), hasLength(1));
      expect(water.arcCount, 2);
      expect(water.applicableDays, 102);
      expect(water.completedDays, 15);
    });

    test('different ids with the same title stay separate', () {
      Habit reading(String id, int order) => Habit(
        id: id,
        title: 'Reading',
        type: HabitType.duration,
        target: 20,
        minimumTarget: 5,
        unit: 'min',
        iconKey: 'learning',
        enabled: true,
        sortOrder: order,
        createdAt: DateTime(2025),
      );
      final s = InsightRules.compute([
        _arc(id: 1, start: _arcA, habits: [reading('reading_a', 0)]),
        _arc(id: 2, start: _arcB, habits: [reading('reading_b', 0)]),
      ]);
      expect(
        s.habits.map((h) => h.habitId),
        unorderedEquals(['reading_a', 'reading_b']),
      );
      expect(s.habits.every((h) => h.title == 'Reading'), isTrue);
      expect(s.habits.every((h) => h.arcCount == 1), isTrue);
    });

    test('a renamed habit keeps its lineage and shows its newest title', () {
      final water = b.habit('water', target: 8, minimum: 3);
      final s = InsightRules.compute([
        _arc(
          id: 2,
          start: _arcB,
          habits: [water.copyWith(title: 'Hydrate')],
        ),
        _arc(
          id: 1,
          start: _arcA,
          habits: [water.copyWith(title: 'Water')],
        ),
      ]);
      expect(s.habits, hasLength(1));
      expect(s.habits.single.title, 'Hydrate');
      expect(s.habits.single.arcCount, 2);
    });

    test('the most consistent habit is deterministic on ties and needs '
        'enough history', () {
      List<Habit> three() => [
        b.habit('beta', target: 8, minimum: 3, sortOrder: 0),
        b.habit('alpha', target: 8, minimum: 3, sortOrder: 1),
        b.habit('gamma', target: 8, minimum: 3, sortOrder: 2),
      ];
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          status: WinterArcStatus.active,
          todayDay: 10,
          habits: three(),
          // alpha and beta: 8 of 10. gamma: 9 of 10.
          done: {
            for (final n in _days(1, 8)) n: ['alpha', 'beta', 'gamma'],
            9: ['gamma'],
          },
        ),
      ]);
      expect(s.mostConsistent?.habitId, 'gamma');
      expect([for (final h in s.habits) h.habitId], ['gamma', 'alpha', 'beta']);

      // One perfect day out of one is not "most consistent".
      final short = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          status: WinterArcStatus.active,
          todayDay: 1,
          done: {
            1: ['water'],
          },
        ),
      ]);
      expect(short.habits.first.completionPercent, 100);
      expect(short.mostConsistent, isNull);
    });

    test('the best streak is the longest run within one arc', () {
      final s = InsightRules.compute([
        // Run of 5 ending on Day 92.
        _arc(
          id: 1,
          start: _arcA,
          done: {
            for (final n in _days(88, 5)) n: ['water'],
            for (final n in _days(1, 2)) n: ['junk'],
          },
        ),
        // Run of 3 from Day 1: not added to the previous arc's run.
        _arc(
          id: 2,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 3,
          done: {
            for (final n in _days(1, 3)) n: ['water', 'junk'],
          },
        ),
      ]);
      expect(_habit(s, 'water').bestStreak, 5);
      expect(_habit(s, 'junk').bestStreak, 3);
      expect(s.bestStreak?.habitId, 'water');
    });
  });

  group('moods', () {
    test('counts each mood, and reflections saved without one', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcA,
          moods: {
            1: Mood.excellent,
            2: Mood.good,
            3: Mood.good,
            4: Mood.rough,
            5: null,
          },
        ),
      ]);
      expect(s.moods.counts, {
        Mood.rough: 1,
        Mood.okay: 0,
        Mood.good: 2,
        Mood.excellent: 1,
      });
      expect(s.moods.withoutMood, 1);
      expect(s.moods.total, 5);
      expect(s.moods.recent, hasLength(4), reason: 'only days with a mood');
    });

    test('the reflection rate is reflected days over elapsed days', () {
      final s = InsightRules.compute([
        _arc(
          id: 1,
          start: _arcB,
          status: WinterArcStatus.active,
          todayDay: 8,
          moods: {1: Mood.good, 2: null, 5: Mood.okay, 6: Mood.okay},
        ),
      ]);
      expect(s.overall.reflectionCount, 4);
      expect(s.overall.reflectionRate, 0.5);
      expect(s.overall.reflectionPercent, 50);
    });

    test('the timeline is chronological across arcs and keeps the most '
        'recent days', () {
      final s = InsightRules.compute([
        _arc(
          id: 2,
          start: _arcB,
          moods: {for (final n in _days(1, 10)) n: Mood.excellent},
        ),
        _arc(
          id: 1,
          start: _arcA,
          moods: {for (final n in _days(1, 10)) n: Mood.rough},
        ),
      ]);
      final recent = s.moods.recent;
      expect(recent, hasLength(InsightRules.recentMoodDays));
      for (var i = 1; i < recent.length; i++) {
        expect(recent[i].date.isAfter(recent[i - 1].date), isTrue);
      }
      // The oldest 6 of arc A dropped; arc B's 10 are the newest.
      expect(recent.where((p) => p.sessionId == 1), hasLength(4));
      expect(recent.last.sessionId, 2);
      expect(recent.last.dayNumber, 10);
      expect(recent.first.mood, Mood.rough);
    });
  });

  test('insights are computed from dates and moods only: the service never '
      'reads reflection text', () async {
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
    addTearDown(app.db.close);
    await runFirstArc(app); // a "good" reflection on Day 3
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    final arc2 = await app.winterArc.startWinterArc();
    await app.reflections.save(
      sessionId: arc2.id,
      date: app.clock.today(),
      draft: const ReflectionDraft(win: 'Text only, no mood'),
    );
    final marks = await app.reflectionStore.moodsFor(arc2.id);
    expect(marks.single.mood, isNull);
    expect(marks.single.date, app.clock.today());

    final s = await app.insights.snapshot();
    expect(s.overall.arcCount, 2);
    expect(s.overall.completedArcs, 1);
    expect(s.overall.elapsedDays, 93);
    expect(s.moods.counts[Mood.good], 1);
    expect(s.moods.withoutMood, 1);
    expect(s.habits.map((h) => h.habitId), contains('workout'));
    // Renamed in Arc 1 ("Strength") and reused: one lineage, newest title.
    expect(_habit(s, 'workout').title, 'Strength');
    expect(_habit(s, 'workout').arcCount, 2);
  });
}
