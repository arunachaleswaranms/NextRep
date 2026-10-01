import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/xp/xp.dart';

final _created = DateTime(2026, 10, 1);
final _now = DateTime(2026, 10, 1, 9, 30);
final _date = LocalDate(2026, 10, 1);

Habit _habit(HabitType type, {int target = 1, String id = 'h'}) => Habit(
  id: id,
  title: id,
  type: type,
  target: target,
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
]) => HabitProgressRules.apply(
  habit: habit,
  current: current ?? DailyHabitProgress.empty(habitId: habit.id, date: _date),
  action: action,
  now: _now,
);

void main() {
  group('binary habit', () {
    final habit = _habit(HabitType.binary);

    test('complete marks done, timestamps, and grants XP once', () {
      final t = _apply(habit, HabitAction.complete);
      expect(t.after.completed, isTrue);
      expect(t.after.currentValue, 1);
      expect(t.after.completedAt, _now);
      expect(t.becameCompleted, isTrue);
      final grant = t.xpEffect as GrantXp;
      expect(grant.award.amount, XpRules.habitCompletion);
      expect(grant.award.sourceKey, 'habit_completed:h:2026-10-01');
    });

    test('completing an already completed habit is a no-op', () {
      final done = _apply(habit, HabitAction.complete).after;
      final again = _apply(habit, HabitAction.complete, done);
      expect(again.changed, isFalse);
      expect(again.xpEffect, isA<NoXpChange>());
      expect(again.after.completedAt, done.completedAt);
    });

    test('undo reverts completion and revokes the same XP key', () {
      final done = _apply(habit, HabitAction.complete).after;
      final undone = _apply(habit, HabitAction.undoCompletion, done);
      expect(undone.after.completed, isFalse);
      expect(undone.after.completedAt, isNull);
      expect(
        (undone.xpEffect as RevokeXp).sourceKey,
        XpRules.habitCompletionKey('h', _date),
      );
    });

    test('undo on an incomplete habit is a no-op', () {
      final t = _apply(habit, HabitAction.undoCompletion);
      expect(t.changed, isFalse);
      expect(t.xpEffect, isA<NoXpChange>());
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
      expect(t.xpEffect, isA<NoXpChange>());
    });

    test('reaching the target completes and grants XP', () {
      var p = DailyHabitProgress.empty(habitId: 'water', date: _date);
      p = _apply(water, HabitAction.increment, p).after;
      p = _apply(water, HabitAction.increment, p).after;
      final last = _apply(water, HabitAction.increment, p);
      expect(last.after.currentValue, 3);
      expect(last.becameCompleted, isTrue);
      expect(last.xpEffect, isA<GrantXp>());
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
      expect(extra.xpEffect, isA<NoXpChange>());
    });

    test('dropping below target un-completes and revokes XP', () {
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
      expect(t.xpEffect, isA<RevokeXp>());
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
}
