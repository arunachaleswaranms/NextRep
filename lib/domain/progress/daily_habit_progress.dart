import '../../core/time/local_date.dart';
import '../habit/habit.dart';

/// A habit's progress on one calendar day.
///
/// [completed] is stored rather than derived so that history keeps its
/// meaning: it is decided against the effective target of that day and is
/// only ever re-evaluated while that day is still today.
final class DailyHabitProgress {
  const DailyHabitProgress({
    required this.habitId,
    required this.date,
    required this.currentValue,
    required this.completed,
    this.completedAt,
  });

  /// No progress recorded yet for [habitId] on [date].
  const DailyHabitProgress.empty({required this.habitId, required this.date})
    : currentValue = 0,
      completed = false,
      completedAt = null;

  final String habitId;
  final LocalDate date;
  final int currentValue;
  final bool completed;
  final DateTime? completedAt;

  /// This progress with [value], completed iff [type] says [value] meets
  /// [target] (see [HabitType.isCompletedBy]).
  ///
  /// Keeps the original completion time while it stays completed.
  DailyHabitProgress withValue(
    int value, {
    required HabitType type,
    required int target,
    required DateTime now,
  }) {
    final nowCompleted = type.isCompletedBy(value, target);
    return DailyHabitProgress(
      habitId: habitId,
      date: date,
      currentValue: value,
      completed: nowCompleted,
      completedAt: nowCompleted ? (completedAt ?? now) : null,
    );
  }

  bool sameStateAs(DailyHabitProgress other) =>
      habitId == other.habitId &&
      date == other.date &&
      currentValue == other.currentValue &&
      completed == other.completed &&
      completedAt == other.completedAt;
}
