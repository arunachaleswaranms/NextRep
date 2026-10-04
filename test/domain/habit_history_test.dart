import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/progress/day_mode.dart';

import '../support/builders.dart';

void main() {
  final water = habit('water', target: 8, minimum: 3);
  final day5 = day1.addDays(4);
  final day10 = day1.addDays(9);

  test('without revisions every date uses the baseline', () {
    final history = HabitHistory(habits: [water]);
    expect(history.configOn(water, day1), water.baseline);
    expect(history.configOn(water, day10), water.baseline);
  });

  test('a revision applies from its date onwards, never before', () {
    final history = HabitHistory(
      habits: [water],
      revisions: [revision('water', day10, target: 10, minimum: 4)],
    );
    expect(history.configOn(water, day1).target, 8);
    expect(history.configOn(water, day10.addDays(-1)).target, 8);
    expect(history.configOn(water, day10).target, 10);
    expect(history.configOn(water, day10.addDays(30)).minimumTarget, 4);
  });

  test('the latest revision on or before the date wins', () {
    final history = HabitHistory(
      habits: [water],
      revisions: [
        revision('water', day10, target: 12),
        revision('water', day5, target: 10),
      ],
    );
    expect(history.configOn(water, day5.addDays(1)).target, 10);
    expect(history.configOn(water, day10.addDays(1)).target, 12);
  });

  test('withRevision replaces a revision of the same habit and date', () {
    final history = HabitHistory(
      habits: [water],
      revisions: [revision('water', day5, target: 10)],
    ).withRevision(revision('water', day5, target: 6));
    expect(history.revisions, hasLength(1));
    expect(history.configOn(water, day5).target, 6);
  });

  test('plan lists enabled habits in order with the mode\'s target', () {
    final history = HabitHistory(
      habits: [
        habit('b', sortOrder: 1, target: 20, minimum: 5),
        habit('a', sortOrder: 0, target: 8, minimum: 3),
        habit('off', sortOrder: 2, enabled: false),
      ],
    );
    final normal = history.planFor(day1, DayMode.normal);
    expect(normal.map((p) => p.habit.id), ['a', 'b']);
    expect(normal.map((p) => p.target), [8, 20]);
    final minimum = history.planFor(day1, DayMode.minimum);
    expect(minimum.map((p) => p.target), [3, 5]);
  });

  test('disabling via revision only removes the habit from that date on', () {
    final history = HabitHistory(
      habits: [water],
      revisions: [revision('water', day5, target: 8, enabled: false)],
    );
    expect(history.planFor(day1, DayMode.normal), hasLength(1));
    expect(history.planFor(day5, DayMode.normal), isEmpty);
  });
}
