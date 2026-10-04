import 'package:intl/intl.dart';

import '../../domain/journey/arc_milestones.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

/// "Day 4 of 92", "Starts tomorrow", or "Winter Arc complete".
String dayTitle(ArcDayPosition position) => switch (position) {
  ArcInProgress(:final dayNumber, :final totalDays) =>
    'Day $dayNumber of $totalDays',
  ArcNotStarted(:final daysUntilStart) =>
    daysUntilStart == 1 ? 'Starts tomorrow' : 'Starts in $daysUntilStart days',
  ArcFinished() => 'Winter Arc complete',
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
/// two years.
String arcDateRange(WinterArcSession session) {
  final start = session.startDate.toLocalDateTime();
  final end = session.endDate.toLocalDateTime();
  final startFormat = start.year == end.year ? 'd MMM' : 'd MMM y';
  return '${DateFormat(startFormat).format(start)} – '
      '${DateFormat('d MMM y').format(end)}';
}
