import '../../core/time/local_date.dart';
import '../progress/arc_history.dart';
import '../reflection/daily_reflection.dart';
import '../winter_arc/winter_arc_session.dart';

/// The stored facts of one started arc that insights are computed from:
/// its derived history (as of today) and the date and mood of each
/// reflection. Reflection text is never part of it.
final class InsightArc {
  const InsightArc({required this.history, this.moods = const []});

  final ArcHistory history;
  final List<MoodMark> moods;

  WinterArcSession get session => history.session;
}

/// Totals across every included arc.
final class OverallInsight {
  const OverallInsight({
    required this.arcCount,
    required this.completedArcs,
    required this.activeArc,
    required this.activeDay,
    required this.elapsedDays,
    required this.fullDays,
    required this.perfectDays,
    required this.minimumDaysCompleted,
    required this.totalXp,
    required this.highestLevel,
    required this.reflectionCount,
  });

  /// Arcs included: every completed arc and the active one.
  final int arcCount;
  final int completedArcs;

  /// The running arc, if any, and today's day number in it.
  final WinterArcSession? activeArc;
  final int? activeDay;

  /// Challenge days that have started, summed over the arcs. A running
  /// arc counts up to and including today.
  final int elapsedDays;

  /// Days with every habit done: Perfect Days plus completed Minimum Days.
  final int fullDays;
  final int perfectDays;
  final int minimumDaysCompleted;
  final int totalXp;

  /// The highest level any arc reached (each arc's XP is its own), or null
  /// with no arcs.
  final int? highestLevel;

  /// Reflections saved on elapsed days.
  final int reflectionCount;

  /// Weighted consistency, `0.0..1.0`: all full days over all elapsed
  /// days. A short arc weighs as much as its days, never as much as a
  /// whole 92-day arc. 0 with no elapsed days.
  double get consistency => elapsedDays == 0 ? 0 : fullDays / elapsedDays;

  /// [consistency] as a whole percentage, rounded down (like an arc's
  /// summary, so 100% means every day was full).
  int get consistencyPercent =>
      elapsedDays == 0 ? 0 : (fullDays * 100) ~/ elapsedDays;

  /// XP per elapsed day, or 0 with no elapsed days.
  double get averageXpPerDay => elapsedDays == 0 ? 0 : totalXp / elapsedDays;

  /// Share of elapsed days with a reflection, `0.0..1.0`.
  double get reflectionRate =>
      elapsedDays == 0 ? 0 : reflectionCount / elapsedDays;

  int get reflectionPercent =>
      elapsedDays == 0 ? 0 : (reflectionCount * 100) ~/ elapsedDays;
}

/// One habit's record across arcs, identified by its stable id.
final class HabitInsight {
  const HabitInsight({
    required this.habitId,
    required this.title,
    required this.iconKey,
    required this.applicableDays,
    required this.completedDays,
    required this.bestStreak,
    required this.arcCount,
  });

  final String habitId;

  /// The most recent title (renames keep the same habit).
  final String title;
  final String iconKey;

  /// Elapsed days on which the habit was enabled. Disabled days don't
  /// count against it.
  final int applicableDays;

  /// Applicable days on which it was completed, at the normal target or,
  /// on a Minimum Day, at the minimum target.
  final int completedDays;

  /// The longest run of consecutive completed days within one arc. Arcs
  /// are separate climbs, so a run never continues from one to the next.
  final int bestStreak;

  /// Arcs in which it was enabled on at least one elapsed day.
  final int arcCount;

  double get completion =>
      applicableDays == 0 ? 0 : completedDays / applicableDays;

  /// [completion] as a whole percentage, rounded down.
  int get completionPercent =>
      applicableDays == 0 ? 0 : (completedDays * 100) ~/ applicableDays;
}

/// One reflected day with a mood, for the mood timeline.
final class MoodPoint {
  const MoodPoint({
    required this.sessionId,
    required this.date,
    required this.dayNumber,
    required this.mood,
  });

  final int sessionId;
  final LocalDate date;

  /// Challenge day of [date] in its arc.
  final int dayNumber;
  final Mood mood;
}

/// What the Journal's moods describe. Counts only: no interpretation and
/// no text.
final class MoodInsight {
  const MoodInsight({
    required this.counts,
    required this.withoutMood,
    required this.recent,
  });

  /// Reflections per mood, every mood present (0 when unused).
  final Map<Mood, int> counts;

  /// Reflections saved with text only.
  final int withoutMood;

  /// The most recent reflected days that have a mood, oldest first.
  final List<MoodPoint> recent;

  int get withMood => counts.values.fold(0, (sum, n) => sum + n);

  int get total => withMood + withoutMood;

  bool get isEmpty => total == 0;
}

/// Everything the Insights screen shows, derived on demand from stored
/// history. Never persisted.
final class InsightSnapshot {
  const InsightSnapshot({
    required this.overall,
    required this.habits,
    required this.mostConsistent,
    required this.bestStreak,
    required this.moods,
  });

  final OverallInsight overall;

  /// Habits with at least one applicable day, strongest completion first.
  final List<HabitInsight> habits;

  /// Highest completion among habits with enough history, if any.
  final HabitInsight? mostConsistent;

  /// Longest single-arc streak, if any habit has one.
  final HabitInsight? bestStreak;
  final MoodInsight moods;

  /// No started arc to learn from yet.
  bool get isEmpty => overall.arcCount == 0;
}
