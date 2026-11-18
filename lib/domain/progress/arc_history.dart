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
/// future never count either. Neither do paused dates (schema v7), nor an
/// ended arc's dates after its last counted day.
///
/// The elapsed dates split into the settled dates and at most one open
/// date, [today] while [isTodayOpen] (spec § 12.5.2). An ended arc has no
/// open date: its last counted day is final, never pending.
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

  /// Whether every challenge day is over (today is after the last day, and
  /// the arc isn't paused).
  bool get isOver => session.isOverOn(today);

  /// Whether [today] is the arc's open day: participating, and the arc is
  /// not ended (`openToday`, spec § 12.5.2). Without schema v7 states this
  /// is exactly "today is an elapsed date".
  late final bool isTodayOpen = session.isOpenOn(today);

  /// How each elapsed date (aligned with [elapsedDates]) affects the streak
  /// of [habitId].
  ///
  /// Days on which the habit was disabled are skipped (they neither count
  /// nor break the streak). Completing the minimum target on a Minimum Day
  /// counts. The open day only counts once completed and never breaks the
  /// streak; an ended arc's last day is final, so it is a miss if not
  /// completed. Paused dates are not elapsed: they neither grow nor break
  /// it.
  List<StreakMark> habitMarks(String habitId) => [
    for (final date in elapsedDates)
      switch (recordOn(date).entryFor(habitId)) {
        null => StreakMark.skip,
        final entry when entry.progress.completed => StreakMark.hit,
        _ when isTodayOpen && date == today => StreakMark.pending,
        _ => StreakMark.miss,
      },
  ];

  /// Current and best streak of consecutive completed days for [habitId].
  Streak habitStreak(String habitId) =>
      StreakRules.compute(habitMarks(habitId));

  /// How each elapsed date (aligned with [elapsedDates]) affects the Perfect
  /// Day streak. A Minimum Day breaks it, including today once switched to
  /// Minimum. Only the open day can be pending.
  late final List<StreakMark> perfectMarks = [
    for (final date in elapsedDates)
      if (recordOn(date).isPerfect)
        StreakMark.hit
      else if (isTodayOpen &&
          date == today &&
          recordOn(date).mode == DayMode.normal)
        StreakMark.pending
      else
        StreakMark.miss,
  ];

  /// Streak of consecutive Perfect Days, and how many there were.
  late final PerfectDayStats perfectDays = PerfectDayStats(
    streak: StreakRules.compute(perfectMarks),
    total: perfectMarks.where((m) => m == StreakMark.hit).length,
  );

  /// All challenge days of the arc, Day 1 first, each on its date
  /// ([WinterArcSession.dateOfDay]); paused dates are not days and are not
  /// listed. A seasonal arc always shows its 92 season days; the ones
  /// before the user joined are [JourneyDayState.notJoined]. An ended
  /// arc's days after its last counted day are
  /// [JourneyDayState.notReached]; a day not dated yet (after an open
  /// pause) is [JourneyDayState.future] with no date.
  List<JourneyDay> journey() => [
    for (var day = 1; day <= session.lengthInDays; day++) journeyDay(day),
  ];

  /// Challenge day [dayNumber] exactly as [journey] lists it, without
  /// building the other days (the Weekly Review's week strip needs 7 or 8).
  JourneyDay journeyDay(int dayNumber) =>
      _journeyDay(dayNumber, session.dateOfDay(dayNumber));

  JourneyDay _journeyDay(int dayNumber, LocalDate? date) {
    if (date == null) {
      return JourneyDay(
        dayNumber: dayNumber,
        date: null,
        state: JourneyDayState.future,
        isToday: false,
        xpEarned: 0,
      );
    }
    final isToday = date == today;
    if (session.isBeforeJoining(date)) {
      return JourneyDay(
        dayNumber: dayNumber,
        date: date,
        state: JourneyDayState.notJoined,
        // An ended arc has no today at all (spec § 12.3).
        isToday: isToday && session.status != WinterArcStatus.ended,
        xpEarned: 0,
      );
    }
    if (session.status == WinterArcStatus.ended &&
        !session.isParticipatingOn(date)) {
      // After the last counted day: the arc ended before it. Never marked
      // as today, so nothing is drawn as walked beyond the last day.
      return JourneyDay(
        dayNumber: dayNumber,
        date: date,
        state: JourneyDayState.notReached,
        isToday: false,
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
    // Only the open day is today (`openToday`, spec § 12.5.2). An ended
    // arc's last day is settled even on its own date: it takes its final
    // state and is never marked, announced or scrolled to as today.
    final isOpenToday = isToday && isTodayOpen;
    return JourneyDay(
      dayNumber: dayNumber,
      date: date,
      state: JourneyRules.stateOf(record, isToday: isOpenToday),
      isToday: isOpenToday,
      record: record,
      xpEarned: records.xpByDate[date] ?? 0,
    );
  }
}
