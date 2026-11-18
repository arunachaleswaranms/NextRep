import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../journey/arc_weeks.dart';
import '../journey/journey_day.dart';
import '../progress/arc_history.dart';
import '../progress/day_mode.dart';
import '../winter_arc/winter_arc_session.dart';

/// One habit's record over a week's settled days (spec § 4.2).
final class HabitWeekTally {
  const HabitWeekTally({
    required this.habit,
    required this.displayIndex,
    required this.applicableDays,
    required this.completedDays,
  });

  final Habit habit;

  /// Position in the Arc's display order ([Habit.sortOrder]), for
  /// tie-breaks.
  final int displayIndex;

  /// `a(i)`: settled days on which the habit was enabled.
  final int applicableDays;

  /// `c(i)`: of those, days whose stored progress is completed.
  final int completedDays;

  /// Whether this habit's ratio `c/a` is strictly higher than [other]'s,
  /// compared exactly (`c(i)·a(j) > c(j)·a(i)`), never as rounded
  /// percentages.
  bool hasHigherRatioThan(HabitWeekTally other) =>
      completedDays * other.applicableDays >
      other.completedDays * applicableDays;
}

/// Today's open day, shown apart from the week's totals ("Today so far").
final class TodaySoFar {
  const TodaySoFar({
    required this.dayNumber,
    required this.date,
    required this.completed,
    required this.total,
    required this.xp,
    required this.mode,
  });

  final int dayNumber;
  final LocalDate date;

  /// Completed enabled habits so far.
  final int completed;

  /// Enabled habits today.
  final int total;

  /// Ledger XP dated today so far.
  final int xp;
  final DayMode mode;
}

/// One day of the review's week strip: its Arc-week class and its Journey
/// presentation (the same [JourneyDay] the Journey shows for that day).
final class ReviewDay {
  const ReviewDay({required this.weekDay, required this.journeyDay});

  final ArcWeekDay weekDay;
  final JourneyDay journeyDay;

  int get dayNumber => weekDay.dayNumber;
  LocalDate? get date => weekDay.date;
}

/// The Weekly Arc Review of one Arc week as of the history's `today`
/// (ARC_MOMENTUM_SPEC §§ 4, 12.5). An immutable read model, derived only
/// from [ArcHistory]: it reads stored records and the XP ledger and never
/// writes, awards or re-scores anything.
///
/// Every total covers the week's **settled** days only. Today's open day is
/// in [today] and never in a total; upcoming, neutral, not-reached and
/// paused dates are in nothing.
final class WeeklyReview {
  WeeklyReview._({
    required this.session,
    required this.date,
    required this.weeks,
    required this.week,
    required this.days,
    required this.countedDays,
    required this.habitOpportunities,
    required this.completedHabitDays,
    required this.fullDays,
    required this.perfectDays,
    required this.minimumDaysChosen,
    required this.minimumDaysCompleted,
    required this.xpEarned,
    required this.dailyCompletion,
    required this.habits,
    required this.today,
  });

  /// The review of week [week] (`1..13`) of [history]'s Arc. [weeks], when
  /// given, must be `ArcWeeks.of(history.session, history.today)`; it is
  /// accepted only to avoid computing it twice.
  ///
  /// Any week can be computed; a week that isn't reviewable simply has no
  /// settled day. Throws [RangeError] for a week outside `1..13`.
  factory WeeklyReview.fromHistory(
    ArcHistory history,
    int week, {
    ArcWeeks? weeks,
  }) {
    final arcWeeks = weeks ?? ArcWeeks.of(history.session, history.today);
    assert(
      identical(arcWeeks.session, history.session) &&
          arcWeeks.today == history.today,
      'weeks of another history',
    );
    final arcWeek = arcWeeks.week(week);
    final xpByDate = history.records.xpByDate;
    final allHabits = history.records.habits.habits;
    final applicable = List.filled(allHabits.length, 0);
    final completed = List.filled(allHabits.length, 0);

    var opportunities = 0;
    var done = 0;
    var full = 0;
    var perfect = 0;
    var minimumChosen = 0;
    var minimumDone = 0;
    var xp = 0;
    final daily = <(int, int)>[];
    TodaySoFar? today;

    for (final day in arcWeek.days) {
      switch (day.dayClass) {
        case ArcDayClass.settled:
          final date = day.date!;
          final record = history.recordOn(date);
          opportunities += record.completion.total;
          done += record.completion.completed;
          daily.add((record.completion.completed, record.completion.total));
          if (record.isPerfect) perfect++;
          if (record.isMinimumComplete) minimumDone++;
          if (record.isPerfect || record.isMinimumComplete) full++;
          if (record.mode == DayMode.minimum) minimumChosen++;
          xp += xpByDate[date] ?? 0;
          for (final (i, habit) in allHabits.indexed) {
            final entry = record.entryFor(habit.id);
            if (entry == null) continue;
            applicable[i]++;
            if (entry.progress.completed) completed[i]++;
          }
        case ArcDayClass.open:
          final date = day.date!;
          final record = history.recordOn(date);
          today = TodaySoFar(
            dayNumber: day.dayNumber,
            date: date,
            completed: record.completion.completed,
            total: record.completion.total,
            xp: xpByDate[date] ?? 0,
            mode: record.mode,
          );
        case ArcDayClass.neutral ||
            ArcDayClass.notReached ||
            ArcDayClass.upcoming:
          break;
      }
    }

    return WeeklyReview._(
      session: history.session,
      date: history.today,
      weeks: arcWeeks,
      week: arcWeek,
      days: List.unmodifiable([
        for (final day in arcWeek.days)
          ReviewDay(
            weekDay: day,
            journeyDay: history.journeyDay(day.dayNumber),
          ),
      ]),
      countedDays: daily.length,
      habitOpportunities: opportunities,
      completedHabitDays: done,
      fullDays: full,
      perfectDays: perfect,
      minimumDaysChosen: minimumChosen,
      minimumDaysCompleted: minimumDone,
      xpEarned: xp,
      dailyCompletion: List.unmodifiable(daily),
      habits: List.unmodifiable([
        for (final (i, habit) in allHabits.indexed)
          if (applicable[i] > 0)
            HabitWeekTally(
              habit: habit,
              displayIndex: i,
              applicableDays: applicable[i],
              completedDays: completed[i],
            ),
      ]),
      today: today,
    );
  }

  /// Highlights need at least this many settled days, and a habit at least
  /// this many applicable days (spec § 4.4).
  static const int minimumSample = 3;

  final WinterArcSession session;

  /// The local date the review was computed on (`T`).
  final LocalDate date;

  /// All 13 weeks on [date].
  final ArcWeeks weeks;

  /// The reviewed week.
  final ArcWeek week;

  /// The week strip: the week's 7 or 8 challenge days, in Arc order.
  final List<ReviewDay> days;

  /// `N`: settled days.
  final int countedDays;

  /// `H`: enabled habits summed over the settled days.
  final int habitOpportunities;

  /// `C`: completed habit-days over the settled days (stored flags).
  final int completedHabitDays;

  /// `F`: settled days that were Perfect or completed Minimum Days.
  final int fullDays;

  /// `P`: settled Perfect Days.
  final int perfectDays;

  /// `M`: settled days stored as Minimum Days.
  final int minimumDaysChosen;

  /// `Mc`: settled Minimum Days with every habit at its minimum.
  final int minimumDaysCompleted;

  /// `X`: ledger XP dated on the settled days.
  final int xpEarned;

  /// Per settled day, oldest first: (completed, enabled) habits.
  final List<(int completed, int total)> dailyCompletion;

  /// Habits enabled on at least one settled day, in display order.
  final List<HabitWeekTally> habits;

  /// Today's open day; only while this week is in progress.
  final TodaySoFar? today;

  int get number => week.number;
  ArcWeekStatus get status => week.status;

  /// Habit completion `(100·C) ~/ H`, or null when there is no opportunity.
  int? get completionPercent => habitOpportunities == 0
      ? null
      : (100 * completedHabitDays) ~/ habitOpportunities;

  /// Consistency `(100·F) ~/ N`, the app's meaning of the word over this
  /// week's settled days, or null when there is none.
  int? get consistencyPercent =>
      countedDays == 0 ? null : (100 * fullDays) ~/ countedDays;

  /// The paused date the Arc stopped on, while this week is paused.
  LocalDate? get pausedSince =>
      status == ArcWeekStatus.paused ? weeks.pausedSince : null;

  /// The join week (first-week wording applies).
  bool get isFirstWeek => number == weeks.joinWeek;

  /// The complete last week of the Arc (Week 13, or an `ended` Arc's week
  /// of `closedOn`): no week follows it.
  bool get isFinalReview => weeks.isFinalReview(number);

  int? get previousWeek => weeks.previousReviewable(number);
  int? get nextWeek => weeks.nextReviewable(number);

  /// "Most consistent this week" (spec § 4.4): the top-ranked habit with at
  /// least [minimumSample] applicable days that was completed on at least
  /// half of them, when at least [minimumSample] days are settled.
  late final HabitWeekTally? mostConsistent = () {
    final ranked = [..._eligible]..sort(_byRank);
    for (final tally in ranked) {
      if (2 * tally.completedDays >= tally.applicableDays) return tally;
    }
    return null;
  }();

  /// "Room to grow" (spec § 4.4): an eligible habit completed on fewer
  /// than half of its days, when something was completed this week and
  /// another eligible habit has a strictly higher ratio. The lowest ratio
  /// wins; then more applicable days; then display order. Never the same
  /// habit as [mostConsistent].
  late final HabitWeekTally? roomToGrow = () {
    if (completedHabitDays < 1) return null;
    final eligible = _eligible;
    final candidates = [
      for (final tally in eligible)
        if (2 * tally.completedDays < tally.applicableDays &&
            eligible.any((other) => other.hasHigherRatioThan(tally)))
          tally,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      if (b.hasHigherRatioThan(a)) return -1; // a has the lower ratio
      if (a.hasHigherRatioThan(b)) return 1;
      final byDays = b.applicableDays.compareTo(a.applicableDays);
      if (byDays != 0) return byDays;
      return a.displayIndex.compareTo(b.displayIndex);
    });
    return candidates.first;
  }();

  List<HabitWeekTally> get _eligible => countedDays < minimumSample
      ? const []
      : [
          for (final tally in habits)
            if (tally.applicableDays >= minimumSample) tally,
        ];

  /// Higher exact ratio first, then more completed days, then display
  /// order.
  static int _byRank(HabitWeekTally a, HabitWeekTally b) {
    if (a.hasHigherRatioThan(b)) return -1;
    if (b.hasHigherRatioThan(a)) return 1;
    final byDone = b.completedDays.compareTo(a.completedDays);
    if (byDone != 0) return byDone;
    return a.displayIndex.compareTo(b.displayIndex);
  }
}
