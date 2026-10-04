import '../habit/habit.dart';
import '../xp/level_rules.dart';
import 'arc_history.dart';

/// A habit's record over the arc.
final class HabitHighlight {
  const HabitHighlight({
    required this.habit,
    required this.bestStreak,
    required this.completedDays,
  });

  final Habit habit;

  /// Longest run of consecutive completed days.
  final int bestStreak;

  /// Days on which it was completed (normal or minimum target).
  final int completedDays;
}

/// End-of-Arc summary, derived entirely from stored history.
final class ArcSummary {
  const ArcSummary({
    required this.totalDays,
    required this.daysElapsed,
    required this.level,
    required this.perfectDays,
    required this.bestPerfectStreak,
    required this.strongestHabit,
    required this.habitsCompleted,
    required this.minimumDaysCompleted,
    required this.fullDays,
    required this.achievementsUnlocked,
    required this.achievementsTotal,
  });

  factory ArcSummary.fromHistory(
    ArcHistory history, {
    required int achievementsUnlocked,
    required int achievementsTotal,
  }) {
    var habitsCompleted = 0;
    var minimumDays = 0;
    var fullDays = 0;
    final completedDays = <String, int>{};
    for (final date in history.elapsedDates) {
      final record = history.recordOn(date);
      for (final entry in record.entries) {
        if (!entry.progress.completed) continue;
        habitsCompleted++;
        completedDays.update(entry.habit.id, (n) => n + 1, ifAbsent: () => 1);
      }
      if (record.isMinimumComplete) minimumDays++;
      if (record.isPerfect || record.isMinimumComplete) fullDays++;
    }

    // Highest best streak, then most completed days, then display order.
    HabitHighlight? strongest;
    for (final habit in history.records.habits.habits) {
      final days = completedDays[habit.id] ?? 0;
      if (days == 0) continue;
      final candidate = HabitHighlight(
        habit: habit,
        bestStreak: history.habitStreak(habit.id).best,
        completedDays: days,
      );
      if (strongest == null ||
          candidate.bestStreak > strongest.bestStreak ||
          (candidate.bestStreak == strongest.bestStreak &&
              candidate.completedDays > strongest.completedDays)) {
        strongest = candidate;
      }
    }

    final perfect = history.perfectDays;
    return ArcSummary(
      totalDays: history.session.lengthInDays,
      daysElapsed: history.elapsedDates.length,
      level: LevelRules.progressFor(history.records.totalXp),
      perfectDays: perfect.total,
      bestPerfectStreak: perfect.streak.best,
      strongestHabit: strongest,
      habitsCompleted: habitsCompleted,
      minimumDaysCompleted: minimumDays,
      fullDays: fullDays,
      achievementsUnlocked: achievementsUnlocked,
      achievementsTotal: achievementsTotal,
    );
  }

  /// Length of the arc (92).
  final int totalDays;

  /// Challenge days that have started (all of them once the arc is over).
  final int daysElapsed;

  /// Final level and total XP.
  final LevelProgress level;
  final int perfectDays;
  final int bestPerfectStreak;

  /// Null if no habit was ever completed.
  final HabitHighlight? strongestHabit;

  /// Completed habit-days over the arc.
  final int habitsCompleted;

  /// Minimum Days with every habit at its minimum.
  final int minimumDaysCompleted;

  /// Days with every habit done: Perfect Days plus completed Minimum Days.
  final int fullDays;

  final int achievementsUnlocked;
  final int achievementsTotal;

  int get totalXp => level.totalXp;

  /// Share of elapsed days on which every habit was done, `0..100`, rounded
  /// down.
  int get consistencyPercent =>
      daysElapsed == 0 ? 0 : (fullDays * 100) ~/ daysElapsed;
}
