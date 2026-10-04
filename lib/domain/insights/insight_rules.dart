import '../reflection/daily_reflection.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/level_rules.dart';
import 'insight_snapshot.dart';

/// Pure rules turning the stored history of every arc into insights.
///
/// Scope: completed arcs in full and the active arc up to and including
/// today ([ArcHistory.elapsedDates]). Arcs in setup have no history and are
/// skipped; future dates are never evaluated. Nothing is read from storage
/// and nothing is persisted.
///
/// * **Consistency** is weighted by days: the sum of full days (Perfect
///   Days plus completed Minimum Days) over the sum of elapsed days. Arc
///   percentages are never averaged, so a short arc can't outweigh a
///   whole 92-day one. It is the same definition as an arc's summary, so
///   one arc's insight matches its summary.
/// * **Habits** are grouped by stable habit id. The same id in several
///   arcs (starter habits, Reuse Last Setup) is one habit; a rename keeps
///   its lineage; two different ids are never merged, even with the same
///   title. A day counts only if the habit was enabled that day.
/// * **Moods** are counted as entered. No sentiment analysis, no scores,
///   no interpretation.
abstract final class InsightRules {
  /// Applicable days a habit needs before it can be called the most
  /// consistent, so a single lucky day can't top the list.
  static const minDaysForMostConsistent = 7;

  /// How many reflected days the mood timeline shows.
  static const recentMoodDays = 14;

  static InsightSnapshot compute(Iterable<InsightArc> facts) {
    final arcs = [
      for (final arc in facts)
        if (arc.session.status != WinterArcStatus.setup) arc,
    ]..sort(_chronological);

    var completed = 0;
    WinterArcSession? active;
    int? activeDay;
    var elapsed = 0;
    var full = 0;
    var perfect = 0;
    var minimum = 0;
    var xp = 0;
    int? highestLevel;
    var reflections = 0;
    final moodCounts = {for (final mood in Mood.values) mood: 0};
    var withoutMood = 0;
    final points = <MoodPoint>[];
    final habits = <String, _HabitTally>{};

    for (final arc in arcs) {
      final history = arc.history;
      final session = history.session;
      if (session.status == WinterArcStatus.completed) {
        completed++;
      } else {
        active = session;
        activeDay = history.elapsedDates.length;
      }
      final dates = history.elapsedDates;
      elapsed += dates.length;
      xp += history.records.totalXp;
      final level = LevelRules.levelFor(history.records.totalXp);
      if (highestLevel == null || level > highestLevel) highestLevel = level;

      for (final date in dates) {
        final record = history.recordOn(date);
        if (record.isPerfect) perfect++;
        if (record.isMinimumComplete) minimum++;
        if (record.isPerfect || record.isMinimumComplete) full++;
      }

      for (final habit in history.records.habits.habits) {
        var applicable = 0;
        var done = 0;
        for (final date in dates) {
          final entry = history.recordOn(date).entryFor(habit.id);
          if (entry == null) continue; // disabled that day
          applicable++;
          if (entry.progress.completed) done++;
        }
        // Arcs are in date order, so the last arc seen names the habit.
        final tally = habits[habit.id] ??= _HabitTally(habit.id);
        tally
          ..title = habit.title
          ..iconKey = habit.iconKey;
        if (applicable == 0) continue;
        tally
          ..applicable += applicable
          ..completed += done
          ..arcs += 1;
        final streak = history.habitStreak(habit.id).best;
        if (streak > tally.bestStreak) tally.bestStreak = streak;
      }

      final elapsedSet = dates.toSet();
      for (final mark in arc.moods) {
        if (!elapsedSet.contains(mark.date)) continue;
        reflections++;
        if (mark.mood case final mood?) {
          moodCounts[mood] = moodCounts[mood]! + 1;
          points.add(
            MoodPoint(
              sessionId: session.id,
              date: mark.date,
              dayNumber: session.dayNumberOf(mark.date),
              mood: mood,
            ),
          );
        } else {
          withoutMood++;
        }
      }
    }

    points.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.sessionId.compareTo(b.sessionId);
    });

    final ranked = [
      for (final tally in habits.values)
        if (tally.applicable > 0) tally.toInsight(),
    ]..sort(_byCompletion);
    final eligible = ranked.where(
      (h) => h.applicableDays >= minDaysForMostConsistent,
    );
    final streaks = [
      for (final h in ranked)
        if (h.bestStreak > 0) h,
    ]..sort(_byStreak);

    return InsightSnapshot(
      overall: OverallInsight(
        arcCount: arcs.length,
        completedArcs: completed,
        activeArc: active,
        activeDay: activeDay,
        elapsedDays: elapsed,
        fullDays: full,
        perfectDays: perfect,
        minimumDaysCompleted: minimum,
        totalXp: xp,
        highestLevel: highestLevel,
        reflectionCount: reflections,
      ),
      habits: ranked,
      mostConsistent: eligible.firstOrNull,
      bestStreak: streaks.firstOrNull,
      moods: MoodInsight(
        counts: moodCounts,
        withoutMood: withoutMood,
        recent: points.length <= recentMoodDays
            ? points
            : points.sublist(points.length - recentMoodDays),
      ),
    );
  }

  static int _chronological(InsightArc a, InsightArc b) {
    final byStart = a.session.startDate.compareTo(b.session.startDate);
    return byStart != 0 ? byStart : a.session.id.compareTo(b.session.id);
  }

  /// Higher completion first (compared exactly, without rounding), then
  /// more completed days, then habit id.
  static int _byCompletion(HabitInsight a, HabitInsight b) {
    final byRatio = (b.completedDays * a.applicableDays).compareTo(
      a.completedDays * b.applicableDays,
    );
    if (byRatio != 0) return byRatio;
    final byDays = b.completedDays.compareTo(a.completedDays);
    return byDays != 0 ? byDays : a.habitId.compareTo(b.habitId);
  }

  /// Longer streak first, then [_byCompletion].
  static int _byStreak(HabitInsight a, HabitInsight b) {
    final byStreak = b.bestStreak.compareTo(a.bestStreak);
    return byStreak != 0 ? byStreak : _byCompletion(a, b);
  }
}

final class _HabitTally {
  _HabitTally(this.habitId);

  final String habitId;
  String title = '';
  String iconKey = '';
  int applicable = 0;
  int completed = 0;
  int bestStreak = 0;
  int arcs = 0;

  HabitInsight toInsight() => HabitInsight(
    habitId: habitId,
    title: title,
    iconKey: iconKey,
    applicableDays: applicable,
    completedDays: completed,
    bestStreak: bestStreak,
    arcCount: arcs,
  );
}
