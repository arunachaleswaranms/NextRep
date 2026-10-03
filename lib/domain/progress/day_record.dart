import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import 'daily_habit_progress.dart';
import 'day_mode.dart';

/// Completed vs. tracked habits for a day.
final class DayCompletion {
  const DayCompletion({required this.completed, required this.total})
    : assert(completed >= 0 && completed <= total);

  factory DayCompletion.of(Iterable<HabitDayEntry> entries) {
    var total = 0;
    var completed = 0;
    for (final entry in entries) {
      total++;
      if (entry.progress.completed) completed++;
    }
    return DayCompletion(completed: completed, total: total);
  }

  final int completed;
  final int total;

  /// `0.0..1.0`. A day with no tracked habits is 0.
  double get ratio => total == 0 ? 0 : completed / total;

  /// Whole percentage, rounded down so 100 means every habit is done.
  int get percent => total == 0 ? 0 : (completed * 100) ~/ total;

  /// Every tracked habit is complete. A day with no habits never is.
  bool get isFull => total > 0 && completed == total;
}

/// An enabled habit on a given day, with the target that applied that day
/// and the progress made.
final class HabitDayEntry {
  const HabitDayEntry({
    required this.habit,
    required this.config,
    required this.target,
    required this.progress,
  });

  final Habit habit;

  /// The habit's configuration in effect that day.
  final HabitConfig config;

  /// Effective target for the day (normal or minimum).
  final int target;
  final DailyHabitProgress progress;
}

/// Everything that happened on one challenge day: its mode, the habits that
/// were enabled that day with their effective targets, and their progress.
final class DayRecord {
  DayRecord({required this.date, required this.mode, required this.entries})
    : completion = DayCompletion.of(entries);

  final LocalDate date;
  final DayMode mode;

  /// Habits enabled on [date], in display order.
  final List<HabitDayEntry> entries;
  final DayCompletion completion;

  /// A normal day on which every enabled habit was completed.
  ///
  /// Minimum Days are never Perfect Days, and a day with no enabled habits
  /// is not one either.
  bool get isPerfect => mode == DayMode.normal && completion.isFull;

  /// A Minimum Day on which every enabled habit reached its minimum target.
  bool get isMinimumComplete => mode == DayMode.minimum && completion.isFull;

  /// Any enabled habit has some progress recorded.
  bool get hasProgress => entries.any((e) => e.progress.currentValue > 0);

  HabitDayEntry? entryFor(String habitId) {
    for (final entry in entries) {
      if (entry.habit.id == habitId) return entry;
    }
    return null;
  }
}
