import '../../core/time/local_date.dart';
import '../winter_arc/winter_arc_session.dart';
import '../xp/level_rules.dart';
import 'arc_history.dart';
import 'day_mode.dart';
import 'day_record.dart';
import 'streak_rules.dart';

/// Read model for the current day of an active Winter Arc.
final class DaySummary {
  DaySummary({
    required this.session,
    required this.record,
    required this.totalXp,
    required this.habitStreaks,
    required this.perfectDays,
  }) : position = session.positionOn(record.date),
       level = LevelRules.progressFor(totalXp);

  factory DaySummary.fromHistory(ArcHistory history) {
    final record = history.recordOn(history.today);
    return DaySummary(
      session: history.session,
      record: record,
      totalXp: history.records.totalXp,
      habitStreaks: {
        for (final entry in record.entries)
          entry.habit.id: history.habitStreak(entry.habit.id),
      },
      perfectDays: history.perfectDays,
    );
  }

  final WinterArcSession session;
  final DayRecord record;
  final ArcDayPosition position;

  /// Total XP earned in this session so far.
  final int totalXp;
  final LevelProgress level;

  /// Streak per enabled habit.
  final Map<String, Streak> habitStreaks;
  final PerfectDayStats perfectDays;

  LocalDate get date => record.date;
  DayMode get mode => record.mode;

  /// Enabled habits in display order.
  List<HabitDayEntry> get entries => record.entries;
  DayCompletion get completion => record.completion;
  bool get isPerfect => record.isPerfect;

  /// Today can be tracked: the arc is active and today is one of its
  /// participating days (never a season day before the user joined).
  bool get isTrackable =>
      session.status == WinterArcStatus.active &&
      session.isParticipatingOn(record.date);

  /// Whether the user may still switch today to a Minimum Day.
  bool get canSwitchToMinimum =>
      isTrackable && mode == DayMode.normal && !record.isPerfect;

  Streak streakFor(String habitId) => habitStreaks[habitId] ?? Streak.none;
}
