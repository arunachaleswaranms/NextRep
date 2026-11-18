import '../../core/time/local_date.dart';
import '../progress/day_mode.dart';
import '../progress/day_record.dart';

/// The single, non-overlapping state of a challenge day on the Journey.
///
/// | state | when |
/// |---|---|
/// | [notJoined] | a seasonal day before the user joined (neutral) |
/// | [notReached] | a day of an ended arc after its last counted day |
/// | [future] | after today, or not dated yet (after an open pause) |
/// | [perfect] | normal day, every enabled habit complete (past or today) |
/// | [minimumComplete] | Minimum Day, every enabled habit at its minimum (past or today) |
/// | [today] | today, not yet perfect / minimum-complete |
/// | [partial] | past normal day with some progress, not all complete |
/// | [minimumPartial] | past Minimum Day with some progress, not all complete |
/// | [missed] | past day (either mode) with no progress at all |
enum JourneyDayState {
  /// A day of a seasonal arc before the user joined it. Neutral: not a
  /// miss, not a future day; it has no record and no detail beyond the
  /// explanation.
  notJoined,

  /// A day of an `ended` arc after its last counted day (schema v7, spec
  /// § 12.4): the arc ended before reaching it. Final, never missed; no
  /// record. Only a restored format-4 backup holds such an arc in Phase
  /// 12E1.
  notReached,
  future,
  today,
  perfect,
  minimumComplete,
  partial,
  minimumPartial,
  missed;

  /// Whether the day is over and its outcome final.
  bool get isFinal =>
      this != future &&
      this != today &&
      this != notJoined &&
      this != notReached;
}

/// One of the arc's days, as shown on the Journey.
final class JourneyDay {
  const JourneyDay({
    required this.dayNumber,
    required this.date,
    required this.state,
    required this.isToday,
    required this.xpEarned,
    this.record,
  });

  /// 1-based challenge day.
  final int dayNumber;

  /// The day's calendar date, or null while it is unknown: a day after the
  /// start of an open pause is dated only when the arc is resumed. Always
  /// known for a day that has a [record], and for a day before joining.
  final LocalDate? date;
  final JourneyDayState state;

  /// True for the current date, whatever its [state], except on an ended
  /// arc: it has no open day (spec § 12.3), so even its last day, viewed
  /// on its own date, is settled history and never today.
  final bool isToday;

  /// What happened that day. Null for future days and days before the
  /// user joined.
  final DayRecord? record;

  /// XP credited to this date (habit completions and Perfect Day bonus).
  final int xpEarned;

  DayMode? get mode => record?.mode;

  /// No outcome to show yet, or ever: a day still to come, or one an ended
  /// arc did not reach. Such a day has no record and no detail.
  bool get isFuture =>
      state == JourneyDayState.future || state == JourneyDayState.notReached;
  bool get isNotJoined => state == JourneyDayState.notJoined;
}

abstract final class JourneyRules {
  /// The state of a day that has a [record] (i.e. is today or earlier).
  static JourneyDayState stateOf(DayRecord record, {required bool isToday}) {
    if (record.isPerfect) return JourneyDayState.perfect;
    if (record.isMinimumComplete) return JourneyDayState.minimumComplete;
    if (isToday) return JourneyDayState.today;
    if (!record.hasProgress) return JourneyDayState.missed;
    return record.mode.isMinimum
        ? JourneyDayState.minimumPartial
        : JourneyDayState.partial;
  }
}
