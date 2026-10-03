import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../winter_arc/winter_arc_session.dart';
import 'daily_habit_progress.dart';

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

  bool get isPerfect => total > 0 && completed == total;
}

/// A habit paired with its progress on a given day.
final class HabitDayEntry {
  const HabitDayEntry({required this.habit, required this.progress});

  final Habit habit;
  final DailyHabitProgress progress;
}

/// Read model for a single day of an active Winter Arc.
final class DaySummary {
  DaySummary({
    required this.session,
    required this.date,
    required this.entries,
    required this.totalXp,
  }) : position = session.positionOn(date),
       completion = DayCompletion.of(entries);

  final WinterArcSession session;
  final LocalDate date;
  final ArcDayPosition position;

  /// Enabled habits in display order.
  final List<HabitDayEntry> entries;
  final DayCompletion completion;

  /// Total XP earned in this session so far.
  final int totalXp;

  bool get isTrackable => position is ArcInProgress;
}
