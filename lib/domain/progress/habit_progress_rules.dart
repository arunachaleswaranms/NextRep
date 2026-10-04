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

  /// Clock-time habits: record a time (see [HabitProgressRules.apply]'s
  /// `time`). Replaces an earlier time of the same day.
  setTime,

  /// Clock-time habits: remove the recorded time (back to not logged).
  clearTime,
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
/// * Completing an already-completed habit is a no-op (idempotent), and so
///   is recording the same time again.
/// * Undoing / decrementing below [target] un-completes the habit.
/// * Increments stop at [target]. Decrements stop at 0. A value already
///   above [target] (e.g. after switching to a Minimum Day) is never reduced
///   by an increment.
abstract final class HabitProgressRules {
  /// The action that reverts the step which just completed [habit]:
  /// un-check a binary habit, remove the last increment of a numeric one, or
  /// clear a clock-time habit's recorded time.
  static HabitAction undoActionFor(Habit habit) => switch (habit.type) {
    HabitType.binary => HabitAction.undoCompletion,
    HabitType.count || HabitType.duration => HabitAction.decrement,
    HabitType.timeBefore => HabitAction.clearTime,
  };

  /// Applies [action] to [current], where [target] is the habit's effective
  /// target for the day (normal or minimum).
  ///
  /// [time] is the time to record for [HabitAction.setTime], and must be
  /// null for every other action. A clock-time habit keeps a recorded time
  /// that misses the target: it is real data, just not a completion.
  static ProgressTransition apply({
    required Habit habit,
    required int target,
    required DailyHabitProgress current,
    required HabitAction action,
    required DateTime now,
    NightTime? time,
  }) {
    _checkSupported(habit, action);
    if ((action == HabitAction.setTime) != (time != null)) {
      throw ArgumentError.value(time, 'time', 'only for ${action.name}');
    }

    final value = current.currentValue;
    final nextValue = switch (action) {
      HabitAction.complete => target,
      HabitAction.undoCompletion || HabitAction.clearTime => 0,
      HabitAction.increment =>
        value >= target ? value : (value + habit.type.step).clamp(0, target),
      HabitAction.decrement => (value - habit.type.step).clamp(0, value),
      HabitAction.setTime => time!.value,
    };

    return ProgressTransition(
      before: current,
      after: current.withValue(
        nextValue,
        type: habit.type,
        target: target,
        now: now,
      ),
    );
  }

  static void _checkSupported(Habit habit, HabitAction action) {
    final type = habit.type;
    final supported = switch (action) {
      HabitAction.complete ||
      HabitAction.undoCompletion => type == HabitType.binary,
      HabitAction.increment || HabitAction.decrement => type.isNumeric,
      HabitAction.setTime || HabitAction.clearTime => type.isClockTime,
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
