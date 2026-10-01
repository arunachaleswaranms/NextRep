import '../../core/time/local_date.dart';

/// A habit's progress on one calendar day.
///
/// [completed] is stored rather than derived so that history keeps its
/// meaning even if a habit's target changes in a later phase.
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

  bool sameStateAs(DailyHabitProgress other) =>
      habitId == other.habitId &&
      date == other.date &&
      currentValue == other.currentValue &&
      completed == other.completed &&
      completedAt == other.completedAt;
}
