import '../../core/time/local_date.dart';
import '../progress/arc_history.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/level_rules.dart';
import 'journey_day.dart';

/// Read model for the Journey screen.
final class JourneyOverview {
  JourneyOverview.fromHistory(ArcHistory history)
    : session = history.session,
      today = history.today,
      position = history.session.positionOn(history.today),
      days = history.journey(),
      perfectDays = history.perfectDays,
      level = LevelRules.progressFor(history.records.totalXp);

  final WinterArcSession session;
  final LocalDate today;
  final ArcDayPosition position;

  /// Every day of the arc, Day 1 first.
  final List<JourneyDay> days;
  final PerfectDayStats perfectDays;
  final LevelProgress level;
}
