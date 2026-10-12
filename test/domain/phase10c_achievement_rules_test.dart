import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_rules.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/builders.dart';
import '../support/share_fixtures.dart' show seasonalSession;

/// Phase 10C: the 17 new achievements, decided by the pure rules from
/// history alone.

/// Built-in habit [id] from the catalogue, optionally renamed by the user.
Habit _builtIn(String id, {String? title, int sortOrder = 0}) {
  final habit = HabitTemplateCatalog.byId(id)!.toHabit(
    sortOrder: sortOrder,
    createdAt: DateTime(2026, 10, 1),
    enabled: true,
  );
  return title == null ? habit : habit.copyWith(title: title);
}

/// A habit of the user's own with [title] (and a random-style id).
Habit _custom(String title, {int sortOrder = 0, String hex = 'a'}) => Habit(
  id: 'custom_${hex * 32}',
  title: title,
  type: HabitType.binary,
  target: 1,
  minimumTarget: 1,
  iconKey: 'star',
  enabled: true,
  sortOrder: sortOrder,
  createdAt: DateTime(2026, 10, 1),
);

/// An arc as of day [today] in which each habit of [habits] was complete
/// on the day numbers in [done] (by habit id). Days are relative to the
/// session's Day 1 ([day1] unless [session] says otherwise).
ArcHistory _arc({
  required int today,
  required List<Habit> habits,
  Map<String, Iterable<int>> done = const {},
  Map<int, DayMode> modes = const {},
  List<HabitRevision> revisions = const [],
  WinterArcSession? session,
}) {
  final arc = session ?? activeSession();
  LocalDate on(int day) => arc.startDate.addDays(day - 1);
  return ArcHistory(
    session: arc,
    today: on(today),
    records: ArcRecords(
      habits: HabitHistory(habits: habits, revisions: revisions),
      progress: <DailyHabitProgress>[
        for (final MapEntry(key: id, value: days) in done.entries)
          for (final day in days) progress(id, on(day), 1, completed: true),
      ],
      modes: {
        for (final MapEntry(key: day, value: mode) in modes.entries)
          on(day): mode,
      },
      xpByDate: const {},
      totalXp: 0,
    ),
  );
}

Map<AchievementKey, LocalDate> _earned(
  ArcHistory history, {
  Iterable<LocalDate> reflections = const [],
}) => {
  for (final e in AchievementRules.evaluate(
    AchievementContext(history: history, reflectionDates: reflections),
  ))
    e.key: e.earnedOn,
};

Iterable<int> _days(int from, int to) => [for (var d = from; d <= to; d++) d];

/// Every day from 1 to [to] except [except].
Iterable<int> _daysExcept(int to, Set<int> except) =>
    _days(1, to).where((d) => !except.contains(d));

/// Asserts the threshold rules of [key] for a habit-history achievement:
/// locked one short, earned on the exact day, unmoved by later days, and
/// not earned if today's completion that would reach it is missing.
void _threshold(
  AchievementKey key, {
  required int days,
  required ArcHistory Function(int today, Iterable<int> doneDays) arc,
}) {
  expect(
    _earned(arc(days - 1, _days(1, days - 1))),
    isNot(contains(key)),
    reason: '${key.id}: one day short',
  );
  expect(
    _earned(arc(days, _days(1, days)))[key],
    dayN(days),
    reason: '${key.id}: earned on the exact day',
  );
  expect(
    _earned(arc(days + 10, _days(1, days + 10)))[key],
    dayN(days),
    reason: '${key.id}: later days never move it',
  );
  // Reached today, then today's completion undone: not earned (yet).
  expect(
    _earned(arc(days, _days(1, days - 1))),
    isNot(contains(key)),
    reason: '${key.id}: today undone',
  );
}

void main() {
  final water = habit('h1', binary: true);

  group('generic streaks', () {
    for (final (key, length) in const [
      (AchievementKey.streak14, 14),
      (AchievementKey.streak30, 30),
      (AchievementKey.streak50, 50),
    ]) {
      test('${key.id}: a $length-day streak on any habit', () {
        _threshold(
          key,
          days: length,
          arc: (today, days) =>
              _arc(today: today, habits: [water], done: {'h1': days}),
        );
      });
    }

    test('a miss resets; a disabled day neither counts nor breaks', () {
      // Missed Day 10: the run restarts on Day 11 and reaches 14 on Day 24.
      final missed = _arc(
        today: 30,
        habits: [water],
        done: {
          'h1': _daysExcept(30, {10}),
        },
      );
      expect(_earned(missed)[AchievementKey.streak14], dayN(24));

      // Disabled on Days 10-11 (no entry): skipped, so the run of 14
      // completed days ends on Day 16.
      final disabled = _arc(
        today: 30,
        habits: [water],
        done: {
          'h1': _daysExcept(30, {10, 11}),
        },
        revisions: [
          revision('h1', dayN(10), target: 1, enabled: false),
          revision('h1', dayN(12), target: 1),
        ],
      );
      expect(_earned(disabled)[AchievementKey.streak14], dayN(16));
    });
  });

  group('Perfect and Minimum Day totals', () {
    test('perfect_25: the 25th Perfect Day', () {
      _threshold(
        AchievementKey.perfect25,
        days: 25,
        arc: (today, days) =>
            _arc(today: today, habits: [water], done: {'h1': days}),
      );
      // A completed Minimum Day is not a Perfect Day.
      final withMinimum = _arc(
        today: 30,
        habits: [water],
        done: {'h1': _days(1, 30)},
        modes: {5: DayMode.minimum},
      );
      expect(_earned(withMinimum)[AchievementKey.perfect25], dayN(26));
    });

    test("minimum_7: the 7th fully completed Minimum Day", () {
      ArcHistory arc(int today, Iterable<int> doneDays) => _arc(
        today: today,
        habits: [water],
        done: {'h1': doneDays},
        modes: {for (final d in _days(1, today)) d: DayMode.minimum},
      );
      _threshold(AchievementKey.minimum7, days: 7, arc: arc);
      // An incomplete Minimum Day doesn't count.
      expect(
        _earned(arc(8, _daysExcept(8, {3})))[AchievementKey.minimum7],
        dayN(8),
      );
    });
  });

  group('reflections', () {
    for (final (key, count) in const [
      (AchievementKey.reflections14, 14),
      (AchievementKey.reflections30, 30),
    ]) {
      test('${key.id}: $count reflection dates, not necessarily in a row', () {
        // Every other day.
        final dates = [for (var i = 0; i < count; i++) dayN(1 + i * 2)];
        final last = 1 + (count - 1) * 2;
        final history = _arc(today: last + 5, habits: [water]);
        expect(
          _earned(history, reflections: dates.take(count - 1)),
          isNot(contains(key)),
        );
        expect(_earned(history, reflections: dates)[key], dayN(last));
        expect(
          _earned(
            history,
            reflections: [...dates, dayN(last + 1), dayN(last + 3)],
          )[key],
          dayN(last),
        );
        // Reached by today's reflection; without it, not earned.
        final today = _arc(today: last, habits: [water]);
        expect(_earned(today, reflections: dates)[key], dayN(last));
        expect(
          _earned(today, reflections: dates.take(count - 1)),
          isNot(contains(key)),
        );
      });
    }

    test('only dates are used: duplicates and dates outside the arc are '
        'ignored', () {
      final history = _arc(today: 20, habits: [water]);
      final dates = [
        for (final d in _days(1, 13)) dayN(d),
        dayN(13), // duplicate
        day1.addDays(-1), // before the arc
        dayN(25), // future
      ];
      expect(
        _earned(history, reflections: dates),
        isNot(contains(AchievementKey.reflections14)),
      );
    });
  });

  group('journey milestones', () {
    for (final (key, day) in const [
      (AchievementKey.day14, 14),
      (AchievementKey.day60, 60),
      (AchievementKey.day75, 75),
    ]) {
      test('${key.id}: Day $day itself, never early', () {
        // No habit needs to be done: taking part that day is the milestone.
        expect(
          _earned(_arc(today: day - 1, habits: [water])),
          isNot(contains(key)),
        );
        expect(_earned(_arc(today: day, habits: [water]))[key], dayN(day));
        expect(_earned(_arc(today: 93, habits: [water]))[key], dayN(day));
      });
    }

    test('a season joined on Day 15 never earns Day 14', () {
      final joined15 = seasonalSession(joinDay: 15);
      final history = _arc(today: 80, habits: [water], session: joined15);
      final earned = _earned(history);
      expect(earned, isNot(contains(AchievementKey.day14)));
      // Joined before Day 60: Day 60 and later milestones unlock.
      final start = joined15.startDate;
      expect(earned[AchievementKey.halfway], start.addDays(45));
      expect(earned[AchievementKey.day60], start.addDays(59));
      expect(earned[AchievementKey.day75], start.addDays(74));
    });

    test('a season joined on Day 61 earns neither Day 14 nor Day 60', () {
      final history = _arc(
        today: 70,
        habits: [water],
        session: seasonalSession(joinDay: 61),
      );
      final earned = _earned(history);
      expect(earned, isNot(contains(AchievementKey.day14)));
      expect(earned, isNot(contains(AchievementKey.halfway)));
      expect(earned, isNot(contains(AchievementKey.day60)));
      expect(earned, isNot(contains(AchievementKey.day75)));
    });
  });

  group('No Junk Food streaks', () {
    for (final (key, length) in const [
      (AchievementKey.noJunk7, 7),
      (AchievementKey.noJunk30, 30),
      (AchievementKey.noJunk50, 50),
    ]) {
      test('${key.id}: a $length-day run of the built-in habit', () {
        _threshold(
          key,
          days: length,
          arc: (today, days) => _arc(
            today: today,
            habits: [_builtIn('no_junk_food')],
            done: {'no_junk_food': days},
          ),
        );
      });
    }

    test('6 days: Clean Week stays locked', () {
      final history = _arc(
        today: 6,
        habits: [_builtIn('no_junk_food')],
        done: {'no_junk_food': _days(1, 6)},
      );
      expect(_earned(history), isNot(contains(AchievementKey.noJunk7)));
    });

    test('matched by stable id: a rename still counts, a custom habit with '
        'the same name never does', () {
      final renamed = _arc(
        today: 7,
        habits: [_builtIn('no_junk_food', title: 'Clean eating')],
        done: {'no_junk_food': _days(1, 7)},
      );
      expect(_earned(renamed)[AchievementKey.noJunk7], dayN(7));

      final custom = _custom('No Junk Food');
      final lookalike = _arc(
        today: 60,
        habits: [custom],
        done: {custom.id: _days(1, 60)},
      );
      final earned = _earned(lookalike);
      for (final key in const [
        AchievementKey.noJunk7,
        AchievementKey.noJunk30,
        AchievementKey.noJunk50,
      ]) {
        expect(earned, isNot(contains(key)));
      }
      // It still counts toward the generic streaks.
      expect(earned[AchievementKey.streak50], dayN(50));
    });

    test('uses the habit streak semantics: a disabled day is skipped, a '
        'completed Minimum Day counts, a miss resets', () {
      final history = _arc(
        today: 12,
        habits: [_builtIn('no_junk_food')],
        // Days 1-3, disabled 4, 5-6 (6 a Minimum Day), missed 7, 8-12.
        done: {
          'no_junk_food': [1, 2, 3, 5, 6, 8, 9, 10, 11, 12],
        },
        modes: {6: DayMode.minimum},
        revisions: [
          revision('no_junk_food', dayN(4), target: 1, enabled: false),
          revision('no_junk_food', dayN(5), target: 1),
        ],
      );
      expect(_earned(history), isNot(contains(AchievementKey.noJunk7)));

      final through = _arc(
        today: 9,
        habits: [_builtIn('no_junk_food')],
        done: {
          'no_junk_food': [1, 2, 3, 5, 6, 7, 8],
        },
        modes: {6: DayMode.minimum},
        revisions: [
          revision('no_junk_food', dayN(4), target: 1, enabled: false),
          revision('no_junk_food', dayN(5), target: 1),
        ],
      );
      // 1-3 + 5-8 = 7 completed days across the disabled Day 4.
      expect(_earned(through)[AchievementKey.noJunk7], dayN(8));
    });
  });

  group('cumulative habit totals', () {
    for (final (key, id, days) in const [
      (AchievementKey.workout30, 'workout', 30),
      (AchievementKey.water30, 'water', 30),
      (AchievementKey.learning30, 'learning', 30),
      (AchievementKey.sleep14, 'sleep_before', 14),
    ]) {
      test('${key.id}: $days completed days of built-in "$id"', () {
        _threshold(
          key,
          days: days,
          arc: (today, done) =>
              _arc(today: today, habits: [_builtIn(id)], done: {id: done}),
        );
      });

      test('${key.id}: not consecutive; renamed counts, lookalikes don\'t', () {
        // Every other day: the total is reached on day 2 * days - 1.
        final spread = [for (var i = 0; i < days; i++) 1 + i * 2];
        final renamed = _arc(
          today: 2 * days + 5,
          habits: [_builtIn(id, title: 'Renamed')],
          done: {id: spread},
        );
        expect(_earned(renamed)[key], dayN(2 * days - 1));

        final template = HabitTemplateCatalog.byId(id)!;
        final custom = _custom(template.title);
        final lookalike = _arc(
          today: 60,
          habits: [custom],
          done: {custom.id: _days(1, 60)},
        );
        expect(_earned(lookalike), isNot(contains(key)));
      });
    }

    test('disabled days are not applicable and do not count', () {
      final history = _arc(
        today: 40,
        habits: [_builtIn('workout')],
        // Completion rows on disabled days 11-15 are not entries at all.
        done: {'workout': _days(1, 35)},
        revisions: [
          revision(
            'workout',
            dayN(11),
            target: 30,
            minimum: 10,
            enabled: false,
          ),
          revision('workout', dayN(16), target: 30, minimum: 10),
        ],
      );
      // 35 days with a completion row, 5 of them disabled: the 30th
      // applicable completion is on Day 35, not Day 30.
      expect(_earned(history)[AchievementKey.workout30], dayN(35));
    });

    test('Water: only completion counts, whatever the target', () {
      // 29 complete days plus a day with progress short of the goal.
      final arc = activeSession();
      final history = ArcHistory(
        session: arc,
        today: dayN(31),
        records: ArcRecords(
          habits: HabitHistory(habits: [_builtIn('water')]),
          progress: [
            for (final d in _days(1, 29)) progress('water', dayN(d), 8),
            progress('water', dayN(30), 7, completed: false),
          ],
          modes: const {},
          xpByDate: const {},
          totalXp: 0,
        ),
      );
      expect(_earned(history), isNot(contains(AchievementKey.water30)));
    });

    test('Sleep: legacy sleep_on_time never counts toward Rest Rhythm', () {
      final legacy = Habit(
        id: 'sleep_on_time',
        title: 'Sleep Before Target',
        type: HabitType.binary,
        target: 1,
        minimumTarget: 1,
        iconKey: 'sleep',
        enabled: true,
        sortOrder: 0,
        createdAt: DateTime(2026, 10, 1),
      );
      final history = _arc(
        today: 30,
        habits: [legacy],
        done: {'sleep_on_time': _days(1, 30)},
      );
      expect(_earned(history), isNot(contains(AchievementKey.sleep14)));
    });

    test('Sleep: decided by the entry being complete, not the logged time', () {
      // Completed entries carry a logged night time; an incomplete entry
      // with an "early" time does not count.
      final sleep = _builtIn('sleep_before');
      final early = NightTime(21, 0).value;
      final history = ArcHistory(
        session: activeSession(),
        today: dayN(15),
        records: ArcRecords(
          habits: HabitHistory(habits: [sleep]),
          progress: [
            for (final d in _days(1, 13))
              progress('sleep_before', dayN(d), early, completed: true),
            progress('sleep_before', dayN(14), early, completed: false),
          ],
          modes: const {},
          xpByDate: const {},
          totalXp: 0,
        ),
      );
      expect(_earned(history), isNot(contains(AchievementKey.sleep14)));
    });
  });

  test('every rule only reads ids, dates and completion: the same history '
      'with other titles and icons earns the same', () {
    ArcHistory arc(bool renamed) => _arc(
      today: 60,
      habits: [
        for (final (i, id) in const [
          'workout',
          'water',
          'learning',
          'no_junk_food',
          'sleep_before',
        ].indexed)
          _builtIn(
            id,
            title: renamed ? 'Habit $i' : null,
            sortOrder: i,
          ).copyWith(iconKey: renamed ? 'star' : null),
      ],
      done: {
        for (final id in const [
          'workout',
          'water',
          'learning',
          'no_junk_food',
          'sleep_before',
        ])
          id: _days(1, 55),
      },
    );
    final reflections = [for (final d in _days(1, 30)) dayN(d)];
    final plain = _earned(arc(false), reflections: reflections);
    expect(_earned(arc(true), reflections: reflections), plain);
    expect(
      plain.keys,
      containsAll(
        AchievementKey.values.toSet()..removeAll([
          AchievementKey.summit,
          AchievementKey.minimumComplete,
          AchievementKey.minimum3,
          AchievementKey.minimum7,
          AchievementKey.level2,
          AchievementKey.level3,
          AchievementKey.level5,
          AchievementKey.day75,
        ]),
      ),
    );
  });
}
