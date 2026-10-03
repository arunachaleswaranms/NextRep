import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/streak_rules.dart';

import '../support/builders.dart';

LocalDate _d(int dayNumber) => day1.addDays(dayNumber - 1);

/// An arc with [habits] where [done] lists, per day number, the habit ids
/// completed that day (at their target).
ArcHistory _arc({
  required int today,
  List<String> habits = const ['water', 'junk'],
  Map<int, List<String>> done = const {},
  Map<int, Map<String, int>> partial = const {},
  Map<int, DayMode> modes = const {},
  List<HabitRevision> revisions = const [],
  Map<int, int> xp = const {},
}) {
  final list = [
    for (final (i, id) in habits.indexed)
      habit(id, target: 8, minimum: 3, sortOrder: i),
  ];
  return ArcHistory(
    session: activeSession(),
    today: _d(today),
    records: ArcRecords(
      habits: HabitHistory(habits: list, revisions: revisions),
      progress: <DailyHabitProgress>[
        for (final MapEntry(key: day, value: ids) in done.entries)
          for (final id in ids) progress(id, _d(day), 8),
        for (final MapEntry(key: day, value: values) in partial.entries)
          for (final MapEntry(key: id, value: v) in values.entries)
            progress(id, _d(day), v, completed: false),
      ],
      modes: {
        for (final MapEntry(key: day, value: mode) in modes.entries)
          _d(day): mode,
      },
      xpByDate: {
        for (final MapEntry(key: day, value: amount) in xp.entries)
          _d(day): amount,
      },
      totalXp: xp.values.fold(0, (a, b) => a + b),
    ),
  );
}

void main() {
  group('habit streaks', () {
    test('current streak counts consecutive completed days to today', () {
      final arc = _arc(
        today: 4,
        done: {
          1: ['water'],
          2: ['water'],
          3: ['water'],
          4: ['water'],
        },
      );
      expect(arc.habitStreak('water'), const Streak(current: 4, best: 4));
    });

    test('best streak survives a later miss', () {
      final arc = _arc(
        today: 6,
        done: {
          1: ['water'],
          2: ['water'],
          3: ['water'],
          5: ['water'],
        },
      );
      expect(arc.habitStreak('water'), const Streak(current: 1, best: 3));
    });

    test('a missed past day breaks the streak', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water'],
        },
      );
      expect(arc.habitStreak('water').current, 0);
    });

    test('today not done yet does not break the streak', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water'],
          2: ['water'],
        },
      );
      expect(arc.habitStreak('water'), const Streak(current: 2, best: 2));
    });

    test('days on which the habit was disabled are skipped', () {
      final arc = _arc(
        today: 5,
        done: {
          1: ['water'],
          2: ['water'],
          5: ['water'],
        },
        revisions: [
          revision('water', _d(3), target: 8, minimum: 3, enabled: false),
          revision('water', _d(5), target: 8, minimum: 3),
        ],
      );
      expect(arc.habitStreak('water'), const Streak(current: 3, best: 3));
    });

    test('completing the minimum on a Minimum Day counts', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water'],
          3: ['water'],
        },
        partial: {
          2: {'water': 3},
        },
        modes: {2: DayMode.minimum},
      );
      expect(arc.recordOn(_d(2)).entryFor('water')!.target, 3);
      final kept = _arc(
        today: 3,
        done: {
          1: ['water'],
          2: ['water'],
          3: ['water'],
        },
        modes: {2: DayMode.minimum},
      );
      expect(kept.habitStreak('water'), const Streak(current: 3, best: 3));
      expect(arc.habitStreak('water').best, 1); // an incomplete day breaks it
    });

    test('only challenge days up to today are evaluated', () {
      final arc = _arc(
        today: 2,
        done: {
          1: ['water'],
          2: ['water'],
          // Recorded "future" progress must not count.
          3: ['water'],
          4: ['water'],
        },
      );
      expect(arc.elapsedDates, [_d(1), _d(2)]);
      expect(arc.habitStreak('water').best, 2);
    });

    test('after the arc ends, only its 92 days count', () {
      final arc = _arc(today: 120);
      expect(arc.elapsedDates.length, 92);
      expect(arc.elapsedDates.last, activeSession().endDate);
    });
  });

  group('Perfect Day streak', () {
    test('counts perfect days, total and best', () {
      final arc = _arc(
        today: 5,
        done: {
          1: ['water', 'junk'],
          2: ['water', 'junk'],
          3: ['water'],
          4: ['water', 'junk'],
          5: ['water', 'junk'],
        },
      );
      expect(arc.perfectDays.total, 4);
      expect(arc.perfectDays.streak, const Streak(current: 2, best: 2));
    });

    test('a Minimum Day breaks it, even when fully complete', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water', 'junk'],
          2: ['water', 'junk'],
          3: ['water', 'junk'],
        },
        modes: {2: DayMode.minimum},
      );
      expect(arc.perfectDays.total, 2);
      expect(arc.perfectDays.streak, const Streak(current: 1, best: 1));
    });

    test('today as a Minimum Day ends the current perfect streak', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water', 'junk'],
          2: ['water', 'junk'],
        },
        modes: {3: DayMode.minimum},
      );
      expect(arc.perfectDays.streak.current, 0);
      expect(arc.perfectDays.streak.best, 2);
    });

    test('an unfinished normal today keeps the streak pending', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water', 'junk'],
          2: ['water', 'junk'],
        },
      );
      expect(arc.perfectDays.streak.current, 2);
    });

    test('disabling an unfinished habit later does not make old days '
        'perfect', () {
      final arc = _arc(
        today: 3,
        done: {
          1: ['water'], // junk was enabled and not done on Day 1
        },
        revisions: [
          revision('junk', _d(3), target: 1, minimum: 1, enabled: false),
        ],
      );
      expect(arc.recordOn(_d(1)).isPerfect, isFalse);
      expect(arc.perfectDays.total, 0);
    });

    test('raising a target later does not un-complete old days', () {
      final arc = _arc(
        today: 10,
        done: {
          1: ['water', 'junk'],
        },
        revisions: [revision('water', _d(10), target: 10, minimum: 3)],
      );
      final day1Record = arc.recordOn(_d(1));
      expect(day1Record.entryFor('water')!.target, 8);
      expect(day1Record.isPerfect, isTrue);
    });
  });

  group('Journey states', () {
    final arc = _arc(
      today: 6,
      done: {
        1: ['water', 'junk'],
        2: ['water'],
        4: ['water', 'junk'],
        6: ['water'],
      },
      partial: {
        5: {'water': 1},
      },
      modes: {4: DayMode.minimum, 5: DayMode.minimum},
      xp: {1: 60, 2: 15, 4: 30, 6: 15},
    );
    final days = arc.journey();

    test('covers every day of the arc', () {
      expect(days, hasLength(92));
      expect(days.first.dayNumber, 1);
      expect(days.last.date, activeSession().endDate);
    });

    test('each day has one deterministic state', () {
      expect(days[0].state, JourneyDayState.perfect);
      expect(days[1].state, JourneyDayState.partial);
      expect(days[2].state, JourneyDayState.missed);
      expect(days[3].state, JourneyDayState.minimumComplete);
      expect(days[4].state, JourneyDayState.minimumPartial);
      expect(days[5].state, JourneyDayState.today);
      expect(days[6].state, JourneyDayState.future);
      expect(days[91].state, JourneyDayState.future);
    });

    test('today is flagged and keeps its outcome once achieved', () {
      expect(days[5].isToday, isTrue);
      expect(days.where((d) => d.isToday), hasLength(1));
      final perfectToday = _arc(
        today: 1,
        done: {
          1: ['water', 'junk'],
        },
      ).journey().first;
      expect(perfectToday.isToday, isTrue);
      expect(perfectToday.state, JourneyDayState.perfect);
    });

    test('a Minimum Day with no progress is missed', () {
      final missed = _arc(today: 3, modes: {1: DayMode.minimum}).journey();
      expect(missed.first.state, JourneyDayState.missed);
      expect(missed.first.mode, DayMode.minimum);
    });

    test('day detail values come from stored history', () {
      final day1 = days[0];
      expect(day1.record!.completion.completed, 2);
      expect(day1.record!.completion.percent, 100);
      expect(day1.record!.isPerfect, isTrue);
      expect(day1.xpEarned, 60);
      final day2 = days[1];
      expect(day2.record!.completion.completed, 1);
      expect(day2.record!.completion.total, 2);
      expect(day2.record!.completion.percent, 50);
      expect(day2.xpEarned, 15);
      expect(days[3].mode, DayMode.minimum);
      expect(days[3].record!.entryFor('water')!.target, 3);
      expect(days[6].record, isNull);
      expect(days[6].xpEarned, 0);
    });
  });
}
