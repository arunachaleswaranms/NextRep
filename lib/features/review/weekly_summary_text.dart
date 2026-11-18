import '../../domain/review/weekly_summary_rules.dart';

/// The Weekly Review's summary sentences: the approved copy of
/// ARC_MOMENTUM_SPEC §§ 6.3 and 6.4, chosen by [WeeklySummary] and nothing
/// else. Deterministic: no randomness, no variants, nothing generated or
/// stored. Habit titles are the user's own text, inserted as is.
///
/// Two Phase 12B decisions, presented for the owner's Gate B sign-off
/// (docs/PHASE_12B.md):
///
/// * An `ended` Arc's last week takes the final-week wording, except HIGH:
///   "…all the way to the summit." would claim a summit the Arc never
///   reached, so it keeps the approved complete-week HIGH sentence.
/// * A paused week with no settled day has no START sentence ("A new week
///   begins today." isn't true while paused); it shows the approved
///   paused line, "This week begins when you resume.".
abstract final class WeeklySummaryText {
  /// The paused week's line when no day of it is settled yet.
  static const pausedEmpty = 'This week begins when you resume.';

  /// The headline sentence(s).
  static String headline(WeeklySummary s) {
    final complete = s.tense == WeeklySummaryTense.complete;
    final last = complete && s.finalWeek;
    return switch (s.kind) {
      WeeklySummaryKind.start when s.paused => pausedEmpty,
      WeeklySummaryKind.start when s.firstWeek =>
        'Your Arc is just getting started. More days will reveal your '
            'rhythm.',
      WeeklySummaryKind.start =>
        'A new week begins today. One habit at a time.',
      WeeklySummaryKind.lowData when last =>
        'A short final week. Every day you showed up counts.',
      WeeklySummaryKind.lowData when complete =>
        'A short first week. More days will reveal your rhythm.',
      WeeklySummaryKind.lowData =>
        'Just a few days in. Your rhythm will show as the week goes on.',
      WeeklySummaryKind.allFull when !complete =>
        'Every day so far this week has been a full day.',
      WeeklySummaryKind.allFull when s.minimumIncluded =>
        'Every day this week was a full day, Minimum Days included. '
            "That's real momentum.",
      WeeklySummaryKind.allFull =>
        "Every day this week was a full day. That's real momentum.",
      WeeklySummaryKind.high when last && !s.arcEnded =>
        'You kept showing up all the way to the summit.',
      WeeklySummaryKind.high when complete =>
        'You kept showing up this week. Keep that momentum going.',
      WeeklySummaryKind.high =>
        "You've kept showing up so far this week. Keep that momentum going.",
      WeeklySummaryKind.recovery =>
        'You found your way back this week. Every return matters.',
      WeeklySummaryKind.minimum =>
        'On harder days you chose a Minimum Day and still showed up.',
      WeeklySummaryKind.steady when complete =>
        'You completed at least half of your habits this week. Small steps '
            'add up.',
      WeeklySummaryKind.steady =>
        'You completed at least half of your habits so far this week. Small '
            'steps add up.',
      WeeklySummaryKind.some when last =>
        'This week had its challenges, and you still made progress.',
      WeeklySummaryKind.some when complete =>
        'This week had its challenges, and you still made progress. Next '
            'week is a fresh start.',
      WeeklySummaryKind.some =>
        "This week has had its challenges, and you're still making progress.",
      WeeklySummaryKind.quiet when last =>
        'The final week was quiet. Reaching the end of an Arc still matters.',
      WeeklySummaryKind.quiet when complete =>
        "This week was quiet. Whenever you're ready, one habit is a good "
            'place to start.',
      WeeklySummaryKind.quiet =>
        'A quiet start to the week. One habit is a good place to begin.',
    };
  }

  /// The habit lines that follow the headline: Most consistent, then Room
  /// to grow, each only when present.
  static List<String> habitLines(WeeklySummary s) {
    final complete = s.tense == WeeklySummaryTense.complete;
    final last = complete && s.finalWeek;
    return [
      if (s.mostConsistent case final best?)
        complete
            ? '${best.habit.title} was a steady part of your week: '
                  '${best.completedDays} of ${best.applicableDays} days.'
            : '${best.habit.title} has been steady so far: '
                  '${best.completedDays} of ${best.applicableDays} days.',
      if (s.roomToGrow case final grow?)
        last
            ? '${grow.habit.title} had the most room to grow this week.'
            : complete
            ? '${grow.habit.title} could use a little more attention next '
                  'week.'
            : '${grow.habit.title} could use a little attention in the days '
                  'ahead.',
    ];
  }

  /// The whole summary as one paragraph.
  static String paragraph(WeeklySummary s) =>
      [headline(s), ...habitLines(s)].join(' ');
}
