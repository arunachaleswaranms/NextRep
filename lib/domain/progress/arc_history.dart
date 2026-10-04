import '../../core/time/local_date.dart';
import '../habit/habit_config.dart';
import '../journey/journey_day.dart';
import '../winter_arc/winter_arc_session.dart';
import 'daily_habit_progress.dart';
import 'day_mode.dart';
import 'day_record.dart';
import 'day_rules.dart';
import 'streak_rules.dart';

/// Everything persisted for one arc that history is derived from.
final class ArcRecords {
  ArcRecords({
    required this.habits,
    required Iterable<DailyHabitProgress> progress,
    required this.modes,
    required this.xpByDate,
    required this.totalXp,
  }) : _progress = _index(progress);

  final HabitHistory habits;

  /// Stored day modes. Dates without an entry are [DayMode.normal].
  final Map<LocalDate, DayMode> modes;

  /// Sum of ledger amounts per date.
  final Map<LocalDate, int> xpByDate;
  final int totalXp;

  final Map<LocalDate, Map<String, DailyHabitProgress>> _progress;

  static Map<LocalDate, Map<String, DailyHabitProgress>> _index(
    Iterable<DailyHabitProgress> all,
  ) {
    final byDate = <LocalDate, Map<String, DailyHabitProgress>>{};
    for (final p in all) {
      (byDate[p.date] ??= {})[p.habitId] = p;
    }
    return byDate;
  }

  DayMode modeOn(LocalDate date) => modes[date] ?? DayMode.normal;

  Map<String, DailyHabitProgress> progressOn(LocalDate date) =>
      _progress[date] ?? const {};
}

/// Perfect Day statistics for an arc.
final class PerfectDayStats {
  const PerfectDayStats({required this.streak, required this.total});

  final Streak streak;

  /// Number of Perfect Days so far.
  final int total;
}

/// Derived, read-only history of an arc as of [today].
///
/// Only participating days, from the participation start up to
/// `min(today, end)`, are ever evaluated. For a rolling arc that is Day 1
/// onwards; for a seasonal arc joined late, the days before joining are
/// neutral: never missed, never part of a streak, a consistency
/// denominator, a Perfect or Minimum Day, XP or an achievement. Days in the
/// future never count either.
final class ArcHistory {
  ArcHistory({
    required this.session,
    required this.records,
    required this.today,
  });

  final WinterArcSession session;
  final ArcRecords records;
  final LocalDate today;

  final Map<LocalDate, DayRecord> _cache = {};

  /// Participating challenge days that have started, oldest first (see
  /// [WinterArcSession.participatingDatesThrough]).
  late final List<LocalDate> elapsedDates = session.participatingDatesThrough(
    today,
  );

  DayRecord recordOn(LocalDate date) => _cache.putIfAbsent(
    date,
    () => DayRules.recordFor(
      date: date,
      habits: records.habits,
      mode: records.modeOn(date),
      progress: records.progressOn(date),
    ),
  );

  /// Whether every challenge day is over (today is after the last day).
  bool get isOver => session.isOverOn(today);

  /// How each elapsed date (aligned with [elapsedDates]) affects the streak
  /// of [habitId].
  ///
  /// Days on which the habit was disabled are skipped (they neither count
  /// nor break the streak). Completing the minimum target on a Minimum Day
  /// counts. Today only counts once completed and never breaks the streak.
  List<StreakMark> habitMarks(String habitId) => [
    for (final date in elapsedDates)
      switch (recordOn(date).entryFor(habitId)) {
        null => StreakMark.skip,
        final entry when entry.progress.completed => StreakMark.hit,
        _ when date == today => StreakMark.pending,
        _ => StreakMark.miss,
      },
  ];

  /// Current and best streak of consecutive completed days for [habitId].
  Streak habitStreak(String habitId) =>
      StreakRules.compute(habitMarks(habitId));

  /// How each elapsed date (aligned with [elapsedDates]) affects the Perfect
  /// Day streak. A Minimum Day breaks it, including today once switched to
  /// Minimum.
  late final List<StreakMark> perfectMarks = [
    for (final date in elapsedDates)
      if (recordOn(date).isPerfect)
        StreakMark.hit
      else if (date == today && recordOn(date).mode == DayMode.normal)
        StreakMark.pending
      else
        StreakMark.miss,
  ];

  /// Streak of consecutive Perfect Days, and how many there were.
  late final PerfectDayStats perfectDays = PerfectDayStats(
    streak: StreakRules.compute(perfectMarks),
    total: perfectMarks.where((m) => m == StreakMark.hit).length,
  );

  /// All days of the arc, Day 1 first. A seasonal arc always shows its 92
  /// season days; the ones before the user joined are
  /// [JourneyDayState.notJoined].
  List<JourneyDay> journey() => [
    for (var i = 0; i < session.lengthInDays; i++)
      _journeyDay(i + 1, session.startDate.addDays(i)),
  ];

  JourneyDay _journeyDay(int dayNumber, LocalDate date) {
    final isToday = date == today;
    if (session.isBeforeJoining(date)) {
      return JourneyDay(
        dayNumber: dayNumber,
        date: date,
        state: JourneyDayState.notJoined,
        isToday: isToday,
        xpEarned: 0,
      );
    }
    if (date.isAfter(today)) {
      return JourneyDay(
        dayNumber: dayNumber,
        date: date,
        state: JourneyDayState.future,
        isToday: false,
        xpEarned: 0,
      );
    }
    final record = recordOn(date);
    return JourneyDay(
      dayNumber: dayNumber,
      date: date,
      state: JourneyRules.stateOf(record, isToday: isToday),
      isToday: isToday,
      record: record,
      xpEarned: records.xpByDate[date] ?? 0,
    );
  }
}
