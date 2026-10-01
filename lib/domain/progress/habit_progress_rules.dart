import '../../core/errors/app_failure.dart';
import '../habit/habit.dart';
import '../xp/xp.dart';
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

/// What the XP ledger must do as a consequence of a transition.
sealed class XpEffect {
  const XpEffect();
}

final class NoXpChange extends XpEffect {
  const NoXpChange();
}

final class GrantXp extends XpEffect {
  const GrantXp(this.award);

  final XpAward award;
}

final class RevokeXp extends XpEffect {
  const RevokeXp(this.sourceKey);

  final String sourceKey;
}

/// The result of applying a [HabitAction] to a habit's day progress.
final class ProgressTransition {
  const ProgressTransition({
    required this.before,
    required this.after,
    required this.xpEffect,
  });

  final DailyHabitProgress before;
  final DailyHabitProgress after;
  final XpEffect xpEffect;

  bool get changed => !before.sameStateAs(after);
  bool get becameCompleted => !before.completed && after.completed;
  bool get becameIncomplete => before.completed && !after.completed;
}

/// Pure, deterministic progress rules. The single authority for what an
/// action does to progress and XP; persistence and UI only follow its output.
///
/// Semantics:
/// * Completing an already-completed habit is a no-op (idempotent).
/// * Undoing / decrementing below target un-completes the habit and revokes
///   that habit-day's XP. Re-completing re-grants it, so a habit-day is worth
///   at most [XpRules.habitCompletion] no matter how often it is toggled.
/// * Numeric progress is clamped to `0..target`.
abstract final class HabitProgressRules {
  /// The action that reverts the step which just completed [habit]:
  /// un-check a binary habit, or remove the last increment of a numeric one.
  static HabitAction undoActionFor(Habit habit) =>
      habit.type.isNumeric ? HabitAction.decrement : HabitAction.undoCompletion;

  static ProgressTransition apply({
    required Habit habit,
    required DailyHabitProgress current,
    required HabitAction action,
    required DateTime now,
  }) {
    _checkSupported(habit, action);

    final nextValue = switch (action) {
      HabitAction.complete => habit.target,
      HabitAction.undoCompletion => 0,
      HabitAction.increment => current.currentValue + habit.type.step,
      HabitAction.decrement => current.currentValue - habit.type.step,
    }.clamp(0, habit.target);

    final nowCompleted = nextValue >= habit.target;
    final after = DailyHabitProgress(
      habitId: current.habitId,
      date: current.date,
      currentValue: nextValue,
      completed: nowCompleted,
      completedAt: nowCompleted ? (current.completedAt ?? now) : null,
    );

    final sourceKey = XpRules.habitCompletionKey(habit.id, current.date);
    final XpEffect xpEffect = switch ((current.completed, nowCompleted)) {
      (false, true) => GrantXp(
        XpAward(
          sourceKey: sourceKey,
          reason: XpReason.habitCompleted,
          amount: XpRules.habitCompletion,
          date: current.date,
          habitId: habit.id,
          awardedAt: now,
        ),
      ),
      (true, false) => RevokeXp(sourceKey),
      _ => const NoXpChange(),
    };

    return ProgressTransition(
      before: current,
      after: after,
      xpEffect: xpEffect,
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
