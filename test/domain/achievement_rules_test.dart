import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/achievement/achievement_rules.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/day_mode.dart';

import '../support/builders.dart';

Map<AchievementKey, LocalDate> _earned(ArcHistory history) => {
  for (final e in AchievementRules.evaluate(history)) e.key: e.earnedOn,
};

/// [days] days on which every habit (`water`, `junk`) was completed.
Map<int, List<String>> _allDone(Iterable<int> days) => {
  for (final d in days) d: const ['water', 'junk'],
};

void main() {
  test('a fresh arc has earned nothing', () {
    expect(AchievementRules.evaluate(arcOf(today: 1)), isEmpty);
    expect(
      AchievementRules.evaluate(
        arcOf(
          today: 3,
          partial: {
            1: {'water': 4},
          },
        ),
      ),
      isEmpty,
    );
  });

  test('First Rep: the first completed habit', () {
    final earned = _earned(
      arcOf(
        today: 4,
        partial: {
          1: {'water': 2},
        },
        done: {
          2: ['junk'],
          3: ['water'],
        },
      ),
    );
    expect(earned[AchievementKey.firstRep], dayN(2));
  });

  test('Clean Sweep: the first Perfect Day', () {
    final earned = _earned(
      arcOf(
        today: 5,
        done: {
          1: ['water'],
          ..._allDone([3, 4]),
        },
      ),
    );
    expect(earned[AchievementKey.firstPerfect], dayN(3));
    expect(earned, isNot(contains(AchievementKey.perfect3)));
  });

  test('Snowball: a 3-day streak on any habit, not before', () {
    final two = arcOf(
      today: 3,
      done: {
        1: ['water'],
        2: ['water'],
      },
    );
    expect(_earned(two), isNot(contains(AchievementKey.streak3)));

    final earned = _earned(
      arcOf(
        today: 8,
        done: {
          1: ['water'],
          2: ['water'],
          // A miss on day 3 resets water; junk reaches 3 first.
          4: ['water', 'junk'],
          5: ['junk'],
          6: ['junk', 'water'],
        },
      ),
    );
    expect(earned[AchievementKey.streak3], dayN(6));
  });

  test('Cold Front: a 7-day streak; disabled days neither count nor break', () {
    final earned = _earned(
      arcOf(
        today: 9,
        done: {
          for (var d = 1; d <= 7; d++) d: const ['water'],
        },
      ),
    );
    expect(earned[AchievementKey.streak3], dayN(3));
    expect(earned[AchievementKey.streak7], dayN(7));

    final six = _earned(
      arcOf(
        today: 7,
        done: {
          for (var d = 1; d <= 6; d++) d: const ['water'],
        },
      ),
    );
    expect(six, isNot(contains(AchievementKey.streak7)));
  });

  test(
    'Three Perfect Days: the third Perfect Day, not necessarily in a row',
    () {
      final earned = _earned(arcOf(today: 9, done: _allDone([1, 4, 8])));
      expect(earned[AchievementKey.firstPerfect], dayN(1));
      expect(earned[AchievementKey.perfect3], dayN(8));
    },
  );

  test('Still Moving: a fully completed Minimum Day only', () {
    final partialMinimum = arcOf(
      today: 3,
      modes: {2: DayMode.minimum},
      done: {
        2: ['water'],
      },
    );
    expect(
      _earned(partialMinimum),
      isNot(contains(AchievementKey.minimumComplete)),
    );

    final earned = _earned(
      arcOf(today: 4, modes: {3: DayMode.minimum}, done: _allDone([3])),
    );
    expect(earned[AchievementKey.minimumComplete], dayN(3));
    // A complete Minimum Day is not a Perfect Day.
    expect(earned, isNot(contains(AchievementKey.firstPerfect)));
  });

  test('Getting Stronger and Momentum: running XP crosses 250 and 500', () {
    final earned = _earned(
      arcOf(today: 6, done: _allDone([1]), xp: {1: 200, 2: 60, 4: 200, 5: 100}),
    );
    expect(earned[AchievementKey.level2], dayN(2)); // 260
    expect(earned[AchievementKey.level3], dayN(5)); // 560

    final short = _earned(arcOf(today: 3, xp: {1: 249}));
    expect(short, isNot(contains(AchievementKey.level2)));
  });

  test('a level skipped in one day still unlocks every level passed', () {
    final earned = _earned(arcOf(today: 2, xp: {2: 600}));
    expect(earned[AchievementKey.level2], dayN(2));
    expect(earned[AchievementKey.level3], dayN(2));
  });

  test('Midwinter: reaching challenge Day 46', () {
    expect(_earned(arcOf(today: 45)), isNot(contains(AchievementKey.halfway)));
    expect(_earned(arcOf(today: 46))[AchievementKey.halfway], dayN(46));
    expect(_earned(arcOf(today: 80))[AchievementKey.halfway], dayN(46));
  });

  test('Summit: only once the 92-day arc is over', () {
    expect(_earned(arcOf(today: 92)), isNot(contains(AchievementKey.summit)));
    final earned = _earned(arcOf(today: 93));
    expect(earned[AchievementKey.summit], dayN(92));
    expect(earned[AchievementKey.halfway], dayN(46));
  });

  test('several achievements can be earned together, in catalog order', () {
    final earned = AchievementRules.evaluate(
      arcOf(today: 3, done: _allDone([1, 2, 3]), xp: {1: 90, 2: 90, 3: 90}),
    );
    expect(earned.map((e) => e.key), [
      AchievementKey.firstRep,
      AchievementKey.firstPerfect,
      AchievementKey.streak3,
      AchievementKey.perfect3,
      AchievementKey.level2,
    ]);
    final order = AchievementCatalog.all.map((d) => d.key).toList();
    final indexes = earned.map((e) => order.indexOf(e.key)).toList();
    expect(indexes, [...indexes]..sort());
  });

  test('the catalog has stable, unique keys', () {
    expect(AchievementCatalog.all, hasLength(10));
    expect(AchievementCatalog.all.map((d) => d.key).toSet(), hasLength(10));
    expect(AchievementKey.values.map((k) => k.id), [
      'first_rep',
      'first_perfect',
      'streak_3',
      'streak_7',
      'perfect_3',
      'minimum_complete',
      'level_2',
      'level_3',
      'halfway',
      'summit',
    ]);
    expect(AchievementKey.fromId('streak_7'), AchievementKey.streak7);
    expect(AchievementKey.fromId('nope'), isNull);
  });
}
