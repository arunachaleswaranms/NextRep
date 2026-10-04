import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';

final _created = DateTime(2026, 10, 1);
final _now = DateTime(2026, 10, 1, 9, 30);
final _date = LocalDate(2026, 10, 1);

Habit _habit(HabitType type, {int target = 1, String id = 'h'}) => Habit(
  id: id,
  title: id,
  type: type,
  target: target,
  minimumTarget: 1,
  unit: type.isNumeric ? 'u' : null,
  iconKey: id,
  enabled: true,
  sortOrder: 0,
  createdAt: _created,
);

ProgressTransition _apply(
  Habit habit,
  HabitAction action, [
  DailyHabitProgress? current,
  int? target,
]) => HabitProgressRules.apply(
  habit: habit,
  target: target ?? habit.target,
  current: current ?? DailyHabitProgress.empty(habitId: habit.id, date: _date),
  action: action,
  now: _now,
);

void main() {
  group('binary habit', () {
    final habit = _habit(HabitType.binary);

    test('complete marks done and timestamps it', () {
      final t = _apply(habit, HabitAction.complete);
      expect(t.after.completed, isTrue);
      expect(t.after.currentValue, 1);
      expect(t.after.completedAt, _now);
      expect(t.becameCompleted, isTrue);
    });

    test('completing an already completed habit is a no-op', () {
      final done = _apply(habit, HabitAction.complete).after;
      final again = _apply(habit, HabitAction.complete, done);
      expect(again.changed, isFalse);
      expect(again.after.completedAt, done.completedAt);
    });

    test('undo reverts completion', () {
      final done = _apply(habit, HabitAction.complete).after;
      final undone = _apply(habit, HabitAction.undoCompletion, done);
      expect(undone.after.completed, isFalse);
      expect(undone.after.completedAt, isNull);
      expect(undone.becameIncomplete, isTrue);
    });

    test('undo on an incomplete habit is a no-op', () {
      final t = _apply(habit, HabitAction.undoCompletion);
      expect(t.changed, isFalse);
    });

    test('numeric actions are rejected', () {
      expect(
        () => _apply(habit, HabitAction.increment),
        throwsA(
          isA<DomainFailure>().having(
            (f) => f.rule,
            'rule',
            DomainRule.actionNotSupportedForHabitType,
          ),
        ),
      );
    });
  });

  group('numeric habit', () {
    final water = _habit(HabitType.count, target: 3, id: 'water');
    final workout = _habit(HabitType.duration, target: 30, id: 'workout');

    test('increments by the type step without completing early', () {
      final t = _apply(workout, HabitAction.increment);
      expect(t.after.currentValue, 5);
      expect(t.after.completed, isFalse);
      expect(t.becameCompleted, isFalse);
    });

    test('reaching the target completes', () {
      var p = DailyHabitProgress.empty(habitId: 'water', date: _date);
      p = _apply(water, HabitAction.increment, p).after;
      p = _apply(water, HabitAction.increment, p).after;
      final last = _apply(water, HabitAction.increment, p);
      expect(last.after.currentValue, 3);
      expect(last.becameCompleted, isTrue);
    });

    test('is clamped to target: extra increments change nothing', () {
      final full = DailyHabitProgress(
        habitId: 'water',
        date: _date,
        currentValue: 3,
        completed: true,
        completedAt: _now,
      );
      final extra = _apply(water, HabitAction.increment, full);
      expect(extra.after.currentValue, 3);
      expect(extra.changed, isFalse);
    });

    test('dropping below target un-completes', () {
      final full = DailyHabitProgress(
        habitId: 'water',
        date: _date,
        currentValue: 3,
        completed: true,
        completedAt: _now,
      );
      final t = _apply(water, HabitAction.decrement, full);
      expect(t.after.currentValue, 2);
      expect(t.becameIncomplete, isTrue);
      expect(t.after.completedAt, isNull);
    });

    test('never goes below zero', () {
      final t = _apply(water, HabitAction.decrement);
      expect(t.after.currentValue, 0);
      expect(t.changed, isFalse);
    });

    test('undo action for numeric habits is a decrement', () {
      expect(HabitProgressRules.undoActionFor(water), HabitAction.decrement);
      expect(
        HabitProgressRules.undoActionFor(_habit(HabitType.binary)),
        HabitAction.undoCompletion,
      );
    });
  });

  group('effective target (Minimum Day / edited target)', () {
    final water = _habit(HabitType.count, target: 8, id: 'water');
    DailyHabitProgress at(int value, {bool completed = false}) =>
        DailyHabitProgress(
          habitId: 'water',
          date: _date,
          currentValue: value,
          completed: completed,
          completedAt: completed ? _now : null,
        );

    test('completes against the target passed in, not the baseline', () {
      final t = _apply(water, HabitAction.increment, at(2), 3);
      expect(t.after.currentValue, 3);
      expect(t.becameCompleted, isTrue);
    });

    test('an increment never lowers a value above the target', () {
      final t = _apply(water, HabitAction.increment, at(6, completed: true), 3);
      expect(t.after.currentValue, 6);
      expect(t.changed, isFalse);
    });

    test('a decrement from above the target stays complete', () {
      final t = _apply(water, HabitAction.decrement, at(6, completed: true), 3);
      expect(t.after.currentValue, 5);
      expect(t.after.completed, isTrue);
      expect(t.becameIncomplete, isFalse);
    });
  });
}
