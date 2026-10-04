import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/progress/day_mode.dart';

import '../support/builders.dart';

ArcSummary _summary(ArcHistory history, {int unlocked = 0}) =>
    ArcSummary.fromHistory(
      history,
      achievementsUnlocked: unlocked,
      achievementsTotal: 10,
    );

void main() {
  // A finished arc (today = Day 93) over two habits, water and junk.
  final finished = arcOf(
    today: 93,
    done: {
      1: ['water', 'junk'], // perfect
      2: ['water', 'junk'], // perfect
      3: ['water'],
      4: ['water', 'junk'], // perfect
      5: ['water', 'junk'], // perfect
      6: ['water', 'junk'], // perfect
      7: ['water', 'junk'], // minimum complete
      8: ['junk'],
    },
    modes: {7: DayMode.minimum, 9: DayMode.minimum},
    partial: {
      9: {'water': 1},
    },
    xp: {1: 60, 2: 60, 3: 15, 4: 60, 5: 60, 6: 60, 7: 30, 8: 15},
  );

  test('total XP and final level come from the ledger', () {
    final summary = _summary(finished);
    expect(summary.totalXp, 360);
    expect(summary.level.level, 2);
    expect(summary.level.totalXp, 360);
  });

  test('Perfect Day total and best Perfect Day streak', () {
    final summary = _summary(finished);
    expect(summary.perfectDays, 5);
    expect(summary.bestPerfectStreak, 3); // days 4-6
  });

  test('habit and Minimum Day counts', () {
    final summary = _summary(finished);
    // water: 1-7 (7), junk: 1,2,4,5,6,7,8 (7).
    expect(summary.habitsCompleted, 14);
    expect(summary.minimumDaysCompleted, 1); // day 9 was a partial minimum
    expect(summary.fullDays, 6);
    expect(summary.totalDays, 92);
    expect(summary.daysElapsed, 92);
    expect(summary.consistencyPercent, 6); // 6 / 92 = 6.5%, rounded down
  });

  test('strongest habit: best streak first', () {
    final strongest = _summary(finished).strongestHabit!;
    expect(strongest.habit.id, 'water'); // 7 in a row vs. junk's 5
    expect(strongest.bestStreak, 7);
    expect(strongest.completedDays, 7);
  });

  test('strongest habit ties: more completed days, then display order', () {
    final byDays = arcOf(
      today: 10,
      habits: ['water', 'junk'],
      done: {
        1: ['water', 'junk'],
        2: ['water', 'junk'],
        4: ['junk'],
      },
    );
    expect(_summary(byDays).strongestHabit!.habit.id, 'junk');

    final byOrder = arcOf(
      today: 10,
      habits: ['water', 'junk'],
      done: {
        1: ['water', 'junk'],
        2: ['water', 'junk'],
      },
    );
    // Same streak and days: the earlier habit in display order wins, every
    // time.
    for (var i = 0; i < 3; i++) {
      expect(_summary(byOrder).strongestHabit!.habit.id, 'water');
    }
  });

  test('no completions means no strongest habit and 0% consistency', () {
    final empty = _summary(arcOf(today: 93));
    expect(empty.strongestHabit, isNull);
    expect(empty.habitsCompleted, 0);
    expect(empty.consistencyPercent, 0);
    expect(empty.level.level, 1);
  });

  test('achievement counts are carried through', () {
    final summary = _summary(finished, unlocked: 7);
    expect(summary.achievementsUnlocked, 7);
    expect(summary.achievementsTotal, 10);
  });
}
