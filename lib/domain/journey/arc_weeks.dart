import 'dart:math' as math;

import '../../core/time/local_date.dart';
import '../winter_arc/winter_arc_session.dart';

/// How one challenge day of an Arc week stands on a given local date
/// (ARC_MOMENTUM_SPEC § 12.3). Every day is in exactly one class, checked
/// in this order. Only [settled] days count in a week's totals.
///
/// A paused (frozen) date is not a challenge day, so it has no class: it
/// is never listed in a week at all.
enum ArcDayClass {
  /// A season day before the user joined (a late Seasonal join). Never
  /// counted.
  neutral,

  /// A day of an `ended` Arc after its last counted day (`closedOn`).
  /// Never counted, never missed.
  notReached,

  /// A day after today, or a day whose date is not known yet because it
  /// comes after the start of an open pause. Never counted.
  upcoming,

  /// Today, a participating date of an Arc that isn't `ended`
  /// (`openToday`, spec § 12.5.2). Shown as "Today so far", never in the
  /// totals.
  open,

  /// A participating date before today; for an `ended` Arc, also its
  /// participating date equal to today. Counted.
  settled,
}

/// Where a whole Arc week stands on a given local date (spec § 12.3).
enum ArcWeekStatus {
  /// Every day of the week is before the user joined. Not reviewable.
  beforeJoining,

  /// The Arc is `ended` and the week starts after its last counted day.
  /// Not reviewable.
  notReached,

  /// Final: its last date is known and before today, or the Arc is
  /// `ended` and the week has a settled day. Reviewable.
  complete,

  /// Today is a participating date in this week and the Arc isn't
  /// `ended`. Reviewable.
  inProgress,

  /// Today is a paused date, the Arc isn't `ended`, and this week holds
  /// the next challenge day after the pause. Reviewable, even with no
  /// settled day.
  paused,

  /// Not reached yet. Not reviewable.
  upcoming;

  /// Whether a Weekly Review of the week can be opened.
  bool get isReviewable =>
      this == complete || this == inProgress || this == paused;
}

/// One challenge day of an Arc week.
final class ArcWeekDay {
  const ArcWeekDay({
    required this.dayNumber,
    required this.date,
    required this.dayClass,
  });

  /// 1-based challenge day, `1..92`.
  final int dayNumber;

  /// The day's calendar date ([WinterArcSession.dateOfDay]), or null while
  /// it comes after the start of an open pause. Never an estimate.
  final LocalDate? date;
  final ArcDayClass dayClass;
}

/// One of an Arc's 13 weeks on a given local date: its challenge days, in
/// Arc order, and its status.
final class ArcWeek {
  const ArcWeek({
    required this.number,
    required this.days,
    required this.status,
  });

  /// `1..13`.
  final int number;

  /// The week's 7 challenge days (8 for Week 13), Day [firstDay] first.
  final List<ArcWeekDay> days;
  final ArcWeekStatus status;

  int get firstDay => ArcWeeks.firstDayOf(number);
  int get lastDay => ArcWeeks.lastDayOf(number);

  /// 7, or 8 for Week 13.
  int get length => days.length;

  /// The date of the week's first day, or null if not known yet.
  LocalDate? get firstDate => days.first.date;

  /// The date of the week's last day, or null if not known yet (an open
  /// pause lies before it).
  LocalDate? get lastDate => days.last.date;

  bool get isReviewable => status.isReviewable;

  /// Whether some of the week's dates are not known yet (an open pause).
  bool get hasUndatedDays => days.any((d) => d.date == null);

  /// Paused dates between the week's first and last date: the length of a
  /// closed pause that falls inside it, or 0. Zero while dates are unknown.
  int get pausedDaysWithin => switch ((firstDate, lastDate)) {
    (final first?, final last?) => first.daysUntil(last) + 1 - length,
    _ => 0,
  };

  /// The dates counted in the week's totals, oldest first.
  List<LocalDate> get settledDates => [
    for (final day in days)
      if (day.dayClass == ArcDayClass.settled) day.date!,
  ];

  /// Today's day, while it is open in this week.
  ArcWeekDay? get openDay {
    for (final day in days) {
      if (day.dayClass == ArcDayClass.open) return day;
    }
    return null;
  }
}

/// The 13 Arc weeks of a started session on the local date [today]
/// (ARC_MOMENTUM_SPEC §§ 3, 12.2, 12.3). Pure and read-only.
///
/// A NextRep week is an **Arc week**: Days 1–7, 8–14, … 78–84, then a
/// summit week of Days 85–92. There is no calendar (Monday–Sunday) week
/// and nothing depends on the locale. A day's date always comes from
/// [WinterArcSession.dateOfDay], so a pause moves dates, never day numbers;
/// a paused date belongs to no week.
final class ArcWeeks {
  /// Throws [ArgumentError] for a session still in setup: it has no days.
  factory ArcWeeks.of(WinterArcSession session, LocalDate today) {
    if (session.participationStartDate == null) {
      throw ArgumentError.value(session.id, 'session', 'has not started');
    }
    final ended = session.status == WinterArcStatus.ended;
    final closedOn = ended ? session.closedOn : null;
    final closedDay = closedOn == null ? null : session.dayNumberOf(closedOn);
    // While today is paused, the next challenge day after the pause.
    final pausedNextDay = switch (ended ? null : session.positionOn(today)) {
      ArcPaused(:final lastDayNumber) => lastDayNumber + 1,
      _ => null,
    };
    final todayParticipates = session.isParticipatingOn(today);

    ArcDayClass classify(LocalDate? date) {
      if (date != null && session.isBeforeJoining(date)) {
        return ArcDayClass.neutral;
      }
      if (ended && (date == null || date.isAfter(closedOn!))) {
        return ArcDayClass.notReached;
      }
      if (date == null || date.isAfter(today)) return ArcDayClass.upcoming;
      if (date == today && session.isOpenOn(today)) return ArcDayClass.open;
      if (session.isParticipatingOn(date)) return ArcDayClass.settled;
      // Unreachable for a valid session (a challenge date on or before
      // today is participating); never counted either way.
      return ArcDayClass.upcoming;
    }

    ArcWeekStatus statusOf(int number, List<ArcWeekDay> days) {
      if (days.every((d) => d.dayClass == ArcDayClass.neutral)) {
        return ArcWeekStatus.beforeJoining;
      }
      if (closedDay != null && firstDayOf(number) > closedDay) {
        return ArcWeekStatus.notReached;
      }
      final last = days.last.date;
      if ((last != null && last.isBefore(today)) ||
          (ended && days.any((d) => d.dayClass == ArcDayClass.settled))) {
        return ArcWeekStatus.complete;
      }
      if (!ended && todayParticipates && days.any((d) => d.date == today)) {
        return ArcWeekStatus.inProgress;
      }
      if (pausedNextDay != null &&
          pausedNextDay >= firstDayOf(number) &&
          pausedNextDay <= lastDayOf(number)) {
        return ArcWeekStatus.paused;
      }
      return ArcWeekStatus.upcoming;
    }

    final weeks = <ArcWeek>[
      for (var number = 1; number <= count; number++)
        () {
          final days = [
            for (var day = firstDayOf(number); day <= lastDayOf(number); day++)
              () {
                final date = session.dateOfDay(day);
                return ArcWeekDay(
                  dayNumber: day,
                  date: date,
                  dayClass: classify(date),
                );
              }(),
          ];
          return ArcWeek(
            number: number,
            days: List.unmodifiable(days),
            status: statusOf(number, days),
          );
        }(),
    ];
    return ArcWeeks._(
      session: session,
      today: today,
      weeks: List.unmodifiable(weeks),
      finalWeek: closedDay == null ? count : weekOf(closedDay),
      pausedSince: switch (ended ? null : session.positionOn(today)) {
        ArcPaused(:final pausedSince) => pausedSince,
        _ => null,
      },
    );
  }

  ArcWeeks._({
    required this.session,
    required this.today,
    required this.weeks,
    required this.finalWeek,
    required this.pausedSince,
  });

  /// Every Arc has exactly 13 weeks.
  static const int count = 13;

  /// The first challenge day of week [week]: `7·(w − 1) + 1`.
  static int firstDayOf(int week) {
    _checkWeek(week);
    return 7 * (week - 1) + 1;
  }

  /// The last challenge day of week [week]: `7·w`, and Day 92 for Week 13.
  static int lastDayOf(int week) {
    _checkWeek(week);
    return week == count ? WinterArcRules.lengthInDays : 7 * week;
  }

  /// The week of challenge day [day]: `min(13, (d − 1) ~/ 7 + 1)`.
  static int weekOf(int day) {
    RangeError.checkValueInInterval(day, 1, WinterArcRules.lengthInDays, 'day');
    return math.min(count, (day - 1) ~/ 7 + 1);
  }

  /// Whether [week] names one of the 13 weeks.
  static bool isWeek(int week) => week >= 1 && week <= count;

  static void _checkWeek(int week) =>
      RangeError.checkValueInInterval(week, 1, count, 'week');

  final WinterArcSession session;
  final LocalDate today;

  /// Weeks 1–13, in order.
  final List<ArcWeek> weeks;

  /// The Arc's last week: Week 13, or the week of an `ended` Arc's
  /// `closedOn`. No week follows it.
  final int finalWeek;

  /// The first paused date of the pause today falls in, or null when today
  /// isn't paused (never for an `ended` Arc).
  final LocalDate? pausedSince;

  /// Week [number], `1..13`.
  ArcWeek week(int number) {
    _checkWeek(number);
    return weeks[number - 1];
  }

  /// The week the user joined in (Week 1 for every Rolling Arc).
  int get joinWeek => weekOf(session.joinDayNumber!);

  /// The weeks that can be opened as a review, in order. Empty before the
  /// participation start.
  late final List<int> reviewableWeeks = [
    for (final week in weeks)
      if (week.isReviewable) week.number,
  ];

  bool get hasReviewableWeek => reviewableWeeks.isNotEmpty;

  /// The week a review opens on when none is asked for: the week in
  /// progress, else the paused week, else the latest reviewable week
  /// (Week 13 of a completed Arc; the week of an `ended` Arc's
  /// `closedOn`). Null when no week is reviewable.
  late final int? defaultWeek = () {
    for (final status in [ArcWeekStatus.inProgress, ArcWeekStatus.paused]) {
      for (final week in weeks) {
        if (week.status == status) return week.number;
      }
    }
    return reviewableWeeks.isEmpty ? null : reviewableWeeks.last;
  }();

  /// Whether [number] is the Arc's final week and it is complete: Week 13
  /// of an Arc that is over, or an `ended` Arc's last week.
  bool isFinalReview(int number) =>
      number == finalWeek && week(number).status == ArcWeekStatus.complete;

  /// The closest reviewable week before [number], if any.
  int? previousReviewable(int number) {
    for (final week in reviewableWeeks.reversed) {
      if (week < number) return week;
    }
    return null;
  }

  /// The closest reviewable week after [number], if any.
  int? nextReviewable(int number) {
    for (final week in reviewableWeeks) {
      if (week > number) return week;
    }
    return null;
  }

  /// The week a review asked for [requested] shows: [requested] itself
  /// when reviewable; the nearest reviewable week (the earlier on a tie)
  /// when it is a week that can't be opened; [defaultWeek] when it is
  /// missing or outside `1..13`. Null when no week is reviewable.
  int? resolve(int? requested) {
    if (requested == null || !isWeek(requested)) return defaultWeek;
    int? best;
    for (final week in reviewableWeeks) {
      if (best == null || (week - requested).abs() < (best - requested).abs()) {
        best = week;
      }
    }
    return best;
  }
}
