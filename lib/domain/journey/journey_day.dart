import '../../core/time/local_date.dart';
import '../progress/day_mode.dart';
import '../progress/day_record.dart';

/// The single, non-overlapping state of a challenge day on the Journey.
///
/// | state | when |
/// |---|---|
/// | [notJoined] | a seasonal day before the user joined (neutral) |
/// | [future] | after today |
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
  future,
  today,
  perfect,
  minimumComplete,
  partial,
  minimumPartial,
  missed;

  /// Whether the day is over and its outcome final.
  bool get isFinal => this != future && this != today && this != notJoined;
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
  final LocalDate date;
  final JourneyDayState state;

  /// True for the current date, whatever its [state].
  final bool isToday;

  /// What happened that day. Null for future days and days before the
  /// user joined.
  final DayRecord? record;

  /// XP credited to this date (habit completions and Perfect Day bonus).
  final int xpEarned;

  DayMode? get mode => record?.mode;
  bool get isFuture => state == JourneyDayState.future;
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
