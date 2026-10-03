import '../../core/errors/app_failure.dart';
import '../habit/habit.dart';
import 'daily_habit_progress.dart';

/// User intents on a habit for the current day.
enum HabitAction {
  /// Binary habits: mark done.
  complete,

  /// Binary habits: revert a completion.
  undoCompletion,

  /// Numeric habits: add one [HabitType.step].
  increment,

  /// Numeric habits: remove one [HabitType.step].
  decrement,
}

/// The result of applying a [HabitAction] to a habit's day progress.
final class ProgressTransition {
  const ProgressTransition({required this.before, required this.after});

  final DailyHabitProgress before;
  final DailyHabitProgress after;

  bool get changed => !before.sameStateAs(after);
  bool get becameCompleted => !before.completed && after.completed;
  bool get becameIncomplete => before.completed && !after.completed;
}

/// Pure, deterministic progress rules: the single authority for what an
/// action does to a habit's progress on a day.
///
/// XP is not decided here. The ledger for a day is derived from the day's
/// resulting state by `DayRules` (a completed enabled habit is worth
/// `XpRules.habitCompletion`), which keeps completion and XP in lock-step
/// however the state was reached (action, Minimum Day, or habit edit).
///
/// Semantics:
/// * Completing an already-completed habit is a no-op (idempotent).
/// * Undoing / decrementing below [target] un-completes the habit.
/// * Increments stop at [target]. Decrements stop at 0. A value already
///   above [target] (e.g. after switching to a Minimum Day) is never reduced
///   by an increment.
abstract final class HabitProgressRules {
  /// The action that reverts the step which just completed [habit]:
  /// un-check a binary habit, or remove the last increment of a numeric one.
  static HabitAction undoActionFor(Habit habit) =>
      habit.type.isNumeric ? HabitAction.decrement : HabitAction.undoCompletion;

  /// Applies [action] to [current], where [target] is the habit's effective
  /// target for the day (normal or minimum).
  static ProgressTransition apply({
    required Habit habit,
    required int target,
    required DailyHabitProgress current,
    required HabitAction action,
    required DateTime now,
  }) {
    _checkSupported(habit, action);

    final value = current.currentValue;
    final nextValue = switch (action) {
      HabitAction.complete => target,
      HabitAction.undoCompletion => 0,
      HabitAction.increment =>
        value >= target ? value : (value + habit.type.step).clamp(0, target),
      HabitAction.decrement => (value - habit.type.step).clamp(0, value),
    };

    return ProgressTransition(
      before: current,
      after: current.withValue(nextValue, target: target, now: now),
    );
  }

  static void _checkSupported(Habit habit, HabitAction action) {
    final supported = switch (action) {
      HabitAction.complete ||
      HabitAction.undoCompletion => !habit.type.isNumeric,
      HabitAction.increment || HabitAction.decrement => habit.type.isNumeric,
    };
    if (!supported) {
      throw DomainFailure(
        DomainRule.actionNotSupportedForHabitType,
        '${action.name} is not supported for ${habit.type.name} habit '
        '"${habit.id}"',
      );
    }
  }
}
