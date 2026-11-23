import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';

import '../../domain/journey/arc_milestones.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

/// "Day 4 of 92", "Starts tomorrow", or "Winter Arc complete".
///
/// A paused date (Freeze, Phase 12E2) reads "Paused after Day N of 92"
/// where a day title is shown (Journey); Today shows its own paused card.
/// A date after an ended arc's last day reads "Ended early · Day N of 92"
/// (spec § 6.5).
String dayTitle(ArcDayPosition position) => switch (position) {
  ArcInProgress(:final dayNumber, :final totalDays) =>
    'Day $dayNumber of $totalDays',
  ArcNotStarted(:final daysUntilStart) =>
    daysUntilStart == 1 ? 'Starts tomorrow' : 'Starts in $daysUntilStart days',
  ArcFinished() => 'Winter Arc complete',
  ArcPaused(:final lastDayNumber, :final totalDays) =>
    'Paused after Day $lastDayNumber of $totalDays',
  ArcEnded(:final lastDayNumber, :final totalDays) =>
    'Ended early · Day $lastDayNumber of $totalDays',
};

/// Display name of a scene milestone.
String milestoneTitle(ArcMilestone milestone) => switch (milestone) {
  ArcMilestone.frozenTrail => 'Frozen Trail',
  ArcMilestone.firstCamp => 'First Camp',
  ArcMilestone.forestCamp => 'Forest Camp',
  ArcMilestone.ridge => 'Mountain Ridge',
  ArcMilestone.aurora => 'Aurora',
  ArcMilestone.highRidge => 'High Ridge',
  ArcMilestone.summitShelter => 'Summit Shelter',
  ArcMilestone.summit => 'Summit',
};

/// Display name of a Journey chapter.
String chapterTitle(JourneyChapter chapter) => switch (chapter) {
  JourneyChapter.frozenForest => 'Frozen Forest',
  JourneyChapter.firstAscent => 'First Ascent',
  JourneyChapter.ridge => 'Ridge',
  JourneyChapter.auroraPass => 'Aurora Pass',
  JourneyChapter.highMountain => 'High Mountain',
  JourneyChapter.summitApproach => 'Summit Approach',
};

/// "Forest Camp in 5 days", or null once the summit is reached.
String? nextMilestoneLabel(int dayNumber) {
  final next = ArcMilestone.forDay(dayNumber).next;
  if (next == null) return null;
  final days = next.day - dayNumber;
  return '${milestoneTitle(next)} in $days ${days == 1 ? 'day' : 'days'}';
}

/// "1 Jul – 30 Sep 2026", or "4 Oct 2026 – 3 Jan 2027" when the arc spans
/// two years. An ended arc runs to its last counted day; a paused arc has
/// no known end yet ("1 Mar 2027 – paused").
///
/// [today] is the local date the caller's screen state was read on (never a
/// fresh clock read here): an open pause that starts after [today] is only
/// scheduled ("1 Mar 2027 – pause scheduled"), one in effect on [today]
/// reads "– paused" (Gate E2 review R2). A pause scheduled for a date that
/// the clock later moved back before reads "scheduled" again.
String arcDateRange(WinterArcSession session, {required LocalDate today}) {
  final start = session.startDate.toLocalDateTime();
  if (session.freezes.isNotEmpty && session.freezes.last.isOpen) {
    final scheduled = today.isBefore(session.freezes.last.frozenFrom);
    return '${DateFormat('d MMM y').format(start)} – '
        '${scheduled ? 'pause scheduled' : 'paused'}';
  }
  final end = (session.closedOn ?? session.endDate).toLocalDateTime();
  final startFormat = start.year == end.year ? 'd MMM' : 'd MMM y';
  return '${DateFormat(startFormat).format(start)} – '
      '${DateFormat('d MMM y').format(end)}';
}

/// "Rolling Winter Arc" or "Seasonal Winter Arc · 2026".
String arcKindTitle(WinterArcSession session) => switch (session.kind) {
  ArcKind.rolling92 => 'Rolling Winter Arc',
  ArcKind.seasonalWinter => 'Seasonal Winter Arc · ${session.startDate.year}',
};

/// "Winter Arc · 1 Jul – 30 Sep 2026" for a rolling arc, "Seasonal Winter
/// Arc · 1 Oct – 31 Dec 2026" for a seasonal one: an arc's heading on its
/// history pages.
String arcHeading(WinterArcSession session, {required LocalDate today}) =>
    '${session.isSeasonal ? 'Seasonal Winter Arc' : 'Winter Arc'} · '
    '${arcDateRange(session, today: today)}';

/// "Joined Day 15 · 78 days participated", or null for an arc joined on
/// Day 1 (every rolling arc) or not started.
String? joinedLabel(WinterArcSession session) {
  if (!session.joinedLate) return null;
  final days = session.participationLengthInDays;
  return 'Joined Day ${session.joinDayNumber} · $days '
      '${days == 1 ? 'day' : 'days'} participated';
}
