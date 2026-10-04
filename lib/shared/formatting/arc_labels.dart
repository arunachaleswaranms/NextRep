import '../../domain/winter_arc/winter_arc_session.dart';

/// "Day 4 of 92", "Starts tomorrow", or "Winter Arc complete".
String dayTitle(ArcDayPosition position) => switch (position) {
  ArcInProgress(:final dayNumber, :final totalDays) =>
    'Day $dayNumber of $totalDays',
  ArcNotStarted(:final daysUntilStart) =>
    daysUntilStart == 1 ? 'Starts tomorrow' : 'Starts in $daysUntilStart days',
  ArcFinished() => 'Winter Arc complete',
};
