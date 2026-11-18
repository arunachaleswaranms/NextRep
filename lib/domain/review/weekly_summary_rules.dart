import '../journey/arc_weeks.dart';
import '../winter_arc/winter_arc_session.dart';
import 'weekly_review.dart';

/// The headline of a Weekly Review summary (ARC_MOMENTUM_SPEC § 6.3), in
/// priority order: the first that matches wins.
enum WeeklySummaryKind {
  /// `N == 0`.
  start,

  /// `1 ≤ N ≤ 2`.
  lowData,

  /// Every settled day was full (`F == N`).
  allFull,

  /// Habit completion of at least 80% (floored).
  high,

  /// A day under half complete was followed by a full day.
  recovery,

  /// A completed Minimum Day (`Mc ≥ 1`).
  minimum,

  /// Habit completion of at least 50% (floored).
  steady,

  /// Something was completed (`C ≥ 1`).
  some,

  /// Nothing was completed (`C == 0`).
  quiet,
}

/// Whether the summary speaks of a finished week or one still running.
enum WeeklySummaryTense { inProgress, complete }

/// What a Weekly Review's summary says (spec § 6.2). Pure data: the text
/// is built from it by the review screen, never stored.
final class WeeklySummary {
  const WeeklySummary({
    required this.kind,
    required this.tense,
    required this.finalWeek,
    required this.firstWeek,
    required this.paused,
    required this.arcEnded,
    required this.minimumIncluded,
    this.mostConsistent,
    this.roomToGrow,
  });

  final WeeklySummaryKind kind;
  final WeeklySummaryTense tense;

  /// The complete last week of the Arc (Week 13, or an `ended` Arc's last
  /// week): wording that doesn't look ahead to a next week.
  final bool finalWeek;

  /// The week the user joined in.
  final bool firstWeek;

  /// The week is paused: the Arc is paused today.
  final bool paused;

  /// The Arc was ended early (Restart): it never reached the summit.
  final bool arcEnded;

  /// A completed Minimum Day is among the week's full days (ALL_FULL
  /// wording).
  final bool minimumIncluded;

  final HabitWeekTally? mostConsistent;
  final HabitWeekTally? roomToGrow;

  @override
  bool operator ==(Object other) =>
      other is WeeklySummary &&
      other.kind == kind &&
      other.tense == tense &&
      other.finalWeek == finalWeek &&
      other.firstWeek == firstWeek &&
      other.paused == paused &&
      other.arcEnded == arcEnded &&
      other.minimumIncluded == minimumIncluded &&
      identical(other.mostConsistent?.habit, mostConsistent?.habit) &&
      identical(other.roomToGrow?.habit, roomToGrow?.habit);

  @override
  int get hashCode => Object.hash(
    kind,
    tense,
    finalWeek,
    firstWeek,
    paused,
    arcEnded,
    minimumIncluded,
    mostConsistent?.habit.id,
    roomToGrow?.habit.id,
  );
}

/// The Weekly Review's summary rules (spec § 6): pure and deterministic.
/// No randomness, no clock, no locale, no network and nothing generated:
/// the same review always gives the same summary.
abstract final class WeeklySummaryRules {
  static WeeklySummary summarize(WeeklyReview review) {
    final tense = switch (review.status) {
      ArcWeekStatus.inProgress ||
      ArcWeekStatus.paused => WeeklySummaryTense.inProgress,
      _ => WeeklySummaryTense.complete,
    };
    return WeeklySummary(
      kind: kindOf(review),
      tense: tense,
      finalWeek: review.isFinalReview,
      firstWeek: review.isFirstWeek,
      paused: review.status == ArcWeekStatus.paused,
      arcEnded: review.session.status == WinterArcStatus.ended,
      minimumIncluded: review.minimumDaysCompleted >= 1,
      mostConsistent: review.mostConsistent,
      roomToGrow: review.roomToGrow,
    );
  }

  /// The headline kind: the first rule of spec § 6.3 that matches.
  /// Percentages compare floored integers, so 79.9% is 79 and not HIGH;
  /// with no opportunity there is no percentage and neither HIGH nor
  /// STEADY matches.
  static WeeklySummaryKind kindOf(WeeklyReview review) {
    final n = review.countedDays;
    final completion = review.completionPercent;
    if (n == 0) return WeeklySummaryKind.start;
    if (n <= 2) return WeeklySummaryKind.lowData;
    if (review.fullDays == n) return WeeklySummaryKind.allFull;
    if (completion != null && completion >= 80) return WeeklySummaryKind.high;
    if (_recovered(review.dailyCompletion)) return WeeklySummaryKind.recovery;
    if (review.minimumDaysCompleted >= 1) return WeeklySummaryKind.minimum;
    if (completion != null && completion >= 50) {
      return WeeklySummaryKind.steady;
    }
    if (review.completedHabitDays >= 1) return WeeklySummaryKind.some;
    return WeeklySummaryKind.quiet;
  }

  /// Some settled `D1 < D2` with `2·C(D1) < H(D1)` and `D2` full. [days]
  /// is in date order. A full day is `C == H > 0`, which is exactly
  /// `isPerfect || isMinimumComplete`.
  static bool _recovered(List<(int, int)> days) {
    var hadHardDay = false;
    for (final (completed, total) in days) {
      if (hadHardDay && total > 0 && completed == total) return true;
      if (2 * completed < total) hadHardDay = true;
    }
    return false;
  }
}
