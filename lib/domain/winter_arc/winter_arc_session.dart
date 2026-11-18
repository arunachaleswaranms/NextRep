import '../../core/time/local_date.dart';
import 'arc_freeze.dart';
import 'arc_kind.dart';

export 'arc_freeze.dart';
export 'arc_kind.dart';

/// Configuration of the Winter Arc challenge itself.
abstract final class WinterArcRules {
  /// A Winter Arc has 92 challenge days.
  ///
  /// A rolling arc started on October 1 and never paused ends exactly on
  /// December 31, which is also the Seasonal Winter Arc's window. A paused
  /// rolling arc still has 92 challenge days; its calendar span is longer
  /// ([WinterArcSession.calendarSpanInDays]).
  static const int lengthInDays = 92;

  /// The inclusive end date of a rolling arc that starts on [start] and is
  /// never paused.
  static LocalDate endDateFor(LocalDate start) =>
      start.addDays(lengthInDays - 1);

  /// The first rule [session] breaks, or null if it is a valid session:
  ///
  /// * every arc: the end is not before the start
  /// * rolling: [lengthInDays] challenge days, i.e. the end is
  ///   `start + 91 + closed paused days`; once started, participation
  ///   begins on the start date
  /// * seasonal: exactly 1 October – 31 December of one year; once started,
  ///   participation begins inside that window; never paused
  /// * a session in setup has no participation date yet and no freeze
  /// * freezes (see [ArcFreezeRules.problemWith]): rolling, started arcs only;
  ///   ordered, never overlapping and separated by at least one challenge
  ///   day; each starts after a lived day and pauses a day still to come;
  ///   at most one is open, it is the last, and only an active arc has one
  /// * `closedOn` is present exactly for an `ended` arc, and is then one of
  ///   its challenge dates; an ended arc has no open freeze
  ///
  /// The single definition of a well-formed session, used by the services
  /// before they persist one and by backup validation.
  static String? problemWith(WinterArcSession session) {
    final start = session.startDate;
    final end = session.endDate;
    final joined = session.participationStartDate;
    if (end.isBefore(start)) return 'end date before start date';
    if (session.status == WinterArcStatus.setup) {
      if (joined != null) return 'a session in setup has no participation';
    } else if (joined == null) {
      return 'a started session has a participation date';
    }
    final closedOn = session.closedOn;
    if (closedOn != null && session.status != WinterArcStatus.ended) {
      return 'only an ended arc has a closing date';
    }
    if (ArcFreezeRules.problemWith(session) case final problem?) return problem;
    switch (session.kind) {
      case ArcKind.rolling92:
        if (end != endDateFor(start).addDays(session.pausedDays)) {
          return 'not a $lengthInDays-day arc';
        }
        if (joined != null && joined != start) {
          return 'a rolling arc is joined on its start date';
        }
      case ArcKind.seasonalWinter:
        if (!SeasonalWinterRules.isSeasonWindow(start, end)) {
          return 'not a 1 October – 31 December season';
        }
        if (joined != null && (joined.isBefore(start) || joined.isAfter(end))) {
          return 'participation outside the season';
        }
    }
    if (session.status == WinterArcStatus.ended) {
      if (closedOn == null) return 'an ended arc has a closing date';
      if (session.hasOpenFreeze) return 'an ended arc is not paused';
      if (!session.isParticipatingOn(closedOn)) {
        return 'an ended arc closes on one of its challenge days';
      }
    }
    return null;
  }
}

/// Lifecycle of a session. Persisted by [name], so never rename values.
///
/// | | unfinished | finished history | completed (awards, counts) | writable |
/// |---|---|---|---|---|
/// | [setup] | yes | | | |
/// | [active] | yes | | | on a participating date |
/// | [completed] | | yes | yes | |
/// | [ended] | | yes | **no** | |
///
/// Never treat "not completed" as "unfinished" or "active": an [ended] arc
/// is neither. Never treat [ended] as [completed]: it earns no Summit and
/// is not a completed arc in any count.
enum WinterArcStatus {
  /// Onboarding finished; the user is choosing habits. Dates are provisional.
  setup,

  /// The challenge is running between [WinterArcSession.startDate] and
  /// [WinterArcSession.endDate].
  active,

  /// The arc is over: the local date moved past [WinterArcSession.endDate].
  /// Set by `ArcLifecycleService`. History stays readable; tracking is
  /// read-only.
  completed,

  /// The arc was deliberately ended before its natural completion (by
  /// Restart, Phase 12F); its last counted date is
  /// [WinterArcSession.closedOn]. Read-only history. Not [completed]: it
  /// never earns Summit and is never counted as a completed arc. It is
  /// never the active arc, never an unfinished setup, and never becomes
  /// active again.
  ///
  /// Schema v7 / backup format 4. Nothing in Phase 12E1 ends an arc; only
  /// a restored format-4 backup can hold one.
  ended;

  /// In setup or running: the at most one arc that can still change
  /// (`single_open_session`).
  bool get isUnfinished => this == setup || this == active;

  /// Read-only history: [completed] or [ended].
  bool get isFinished => this == completed || this == ended;
}

/// One 92-day Winter Arc attempt: a rolling arc or one Seasonal Winter
/// Arc.
///
/// **Challenge days and calendar dates.** A challenge day number (1..92)
/// is mapped to a calendar date by [dateOfDay], and back by [dayNumberOf].
/// Without a freeze, Day `n` is `startDate + (n − 1)`, exactly as before
/// schema v7. A rolling arc may be paused ([freezes]): its paused dates
/// are not days of the arc (no day number, never missed, never counted),
/// and its later challenge days move to later dates. Day numbers of dates
/// already lived never change, because a freeze always starts after them.
/// While a freeze is open, the dates of the days after it are unknown
/// ([dateOfDay] returns null) until it is resumed.
///
/// Day numbers always count from [startDate]. For a seasonal arc that is
/// 1 October, so a user who joins on 15 October is on Day 15 of 92, not
/// Day 1. The days a user actually takes part in run from
/// [participationStartDate] to [endDate] (to [closedOn] for an ended arc),
/// without paused dates; earlier days of a season are neutral ("before
/// you joined") and never count for or against them.
final class WinterArcSession {
  const WinterArcSession({
    required this.id,
    required this.kind,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    this.participationStartDate,
    this.startedAt,
    this.freezes = const [],
    this.closedOn,
  });

  final int id;

  /// Rolling or seasonal. Fixed for the life of the session.
  final ArcKind kind;

  /// First challenge day (Day 1). Provisional while a rolling arc is in
  /// [WinterArcStatus.setup]; always 1 October for a seasonal arc.
  final LocalDate startDate;

  /// The last calendar date the arc can reach (inclusive): Day 92 once
  /// every closed freeze is accounted for (`start + 91 + closed paused
  /// days` for a rolling arc). While a freeze is open the date of Day 92 is
  /// unknown, and [endDate] does not mean the arc finishes on it (see
  /// [isOverOn]).
  final LocalDate endDate;
  final WinterArcStatus status;
  final DateTime createdAt;

  /// When the user pressed "Start Winter Arc". Null while in setup.
  ///
  /// An instant, for information only: it can fall on another local date
  /// after a time-zone change or a restore elsewhere, so participation is
  /// never derived from it (see [participationStartDate]).
  final DateTime? startedAt;

  /// The first calendar date the user takes part in: the start date of a
  /// rolling arc, the join date of a seasonal one. Null while in setup;
  /// always set once started (see [WinterArcRules.problemWith]).
  final LocalDate? participationStartDate;

  /// The pauses of a rolling arc, oldest first (schema v7). Empty for every
  /// arc that was never paused, and always for a seasonal arc. Validated
  /// by [WinterArcRules.problemWith]; the mapping below assumes a valid
  /// list.
  final List<ArcFreeze> freezes;

  /// The last counted date of an [WinterArcStatus.ended] arc; null for
  /// every other status (schema v7).
  final LocalDate? closedOn;

  /// The number of challenge days: [WinterArcRules.lengthInDays] for every
  /// valid arc, paused or not. (Without a freeze it is the calendar span,
  /// exactly as before schema v7.)
  int get lengthInDays => calendarSpanInDays - pausedDays;

  /// Calendar dates from [startDate] to [endDate], inclusive: the challenge
  /// days plus the dates of closed pauses. Not a count of challenge days.
  int get calendarSpanInDays => startDate.daysUntil(endDate) + 1;

  bool get isSeasonal => kind.isSeasonal;

  /// Whether a freeze is open: the arc is paused, or will be from a later
  /// date, until it is resumed.
  bool get hasOpenFreeze => freezes.isNotEmpty && freezes.last.isOpen;

  /// Total dates of closed pauses.
  int get pausedDays => ArcFreezeRules.closedPausedDays(freezes);

  /// The first participating date of a started session.
  ///
  /// Throws [StateError] for a session still in setup, which has no
  /// participation and no history.
  LocalDate get participationStart =>
      participationStartDate ??
      (throw StateError('Session $id has not started'));

  /// Whether [date] lies in a pause `[frozenFrom, resumedOn)`, including
  /// every date from the start of an open pause on.
  bool isFrozenOn(LocalDate date) => _freezeOn(date) != null;

  /// Whether [date] is one of the days the user takes part in: from the
  /// participation start through [endDate], not paused, and for an ended
  /// arc not after [closedOn]. False for every date of a session still in
  /// setup.
  bool isParticipatingOn(LocalDate date) {
    final joined = participationStartDate;
    if (joined == null || date.isBefore(joined) || date.isAfter(endDate)) {
      return false;
    }
    if (closedOn case final last? when date.isAfter(last)) return false;
    return !isFrozenOn(date);
  }

  /// Whether [date] is the open day of the arc on that date: a
  /// participating date of an arc that isn't [WinterArcStatus.ended]
  /// (spec § 12.5.2, `openToday`). An ended arc has no open day: its last
  /// counted day is already settled.
  bool isOpenOn(LocalDate date) =>
      status != WinterArcStatus.ended && isParticipatingOn(date);

  /// Whether [date] is a day of the arc before the user joined it (only
  /// possible for a seasonal arc joined late). Such days are neutral.
  bool isBeforeJoining(LocalDate date) {
    final joined = participationStartDate;
    return joined != null && !date.isBefore(startDate) && date.isBefore(joined);
  }

  /// The participating dates that have started by [today], oldest first:
  /// from the participation start through `min(today, endDate, closedOn)`,
  /// without paused dates. Empty before the participation start and for a
  /// session in setup.
  List<LocalDate> participatingDatesThrough(LocalDate today) {
    final joined = participationStartDate;
    if (joined == null) return const [];
    var last = today.isBefore(endDate) ? today : endDate;
    if (closedOn case final closed? when closed.isBefore(last)) last = closed;
    final dates = <LocalDate>[];
    var date = joined;
    var next = 0; // the first freeze that doesn't end on or before [date]
    while (!date.isAfter(last)) {
      while (next < freezes.length && freezes[next].endsOnOrBefore(date)) {
        next++;
      }
      if (next < freezes.length && freezes[next].contains(date)) {
        // Jump over the pause instead of walking its dates.
        final resumed = freezes[next].resumedOn;
        if (resumed == null) break;
        date = resumed;
        continue;
      }
      dates.add(date);
      date = date.addDays(1);
    }
    return dates;
  }

  /// Whether the user joined after Day 1 (a seasonal arc joined late).
  bool get joinedLate =>
      participationStartDate != null &&
      participationStartDate!.isAfter(startDate);

  /// The challenge day the user joined on (Day 1 for a rolling arc), or
  /// null in setup. The join date is never paused.
  int? get joinDayNumber => switch (participationStartDate) {
    null => null,
    final joined => dayNumberOf(joined),
  };

  /// How many challenge days the user takes part in, from joining to Day
  /// 92, or to the last counted day of an ended arc. Paused dates are not
  /// among them.
  int get participationLengthInDays => switch (closedOn) {
    null => participationStart.daysUntil(endDate) + 1 - pausedDays,
    final last => participatingDatesThrough(last).length,
  };

  /// Whether every challenge day is over on [date]. The arc stays open for
  /// the whole of its last day, so this is only true from the day after
  /// [endDate], and never while a freeze is open: a paused arc never
  /// completes.
  bool isOverOn(LocalDate date) => date.isAfter(endDate) && !hasOpenFreeze;

  /// 1-based challenge day of [date], or null if [date] is paused (a paused
  /// date has no day number). Can be outside `1..lengthInDays` for a date
  /// before the start or after the last day.
  int? dayNumberOf(LocalDate date) =>
      isFrozenOn(date) ? null : _challengeDaysBefore(date) + 1;

  /// The calendar date of challenge day [dayNumber]: the inverse of
  /// [dayNumberOf]. Null when that date is not known yet, because the day
  /// comes after the start of an open freeze: it is dated only when the
  /// arc is resumed. Never an estimate.
  ///
  /// For an ended arc, a day after [closedOn] keeps its planned date; it is
  /// a day the arc did not reach ([isParticipatingOn] is false).
  LocalDate? dateOfDay(int dayNumber) {
    var date = startDate.addDays(dayNumber - 1);
    for (final freeze in freezes) {
      if (date.isBefore(freeze.frozenFrom)) break;
      final resumed = freeze.resumedOn;
      if (resumed == null) return null;
      date = date.addDays(freeze.frozenFrom.daysUntil(resumed));
    }
    return date;
  }

  /// Whether a challenge day of this arc falls on [date] or later: [date]
  /// is not before the start, not after an ended arc's last day, and fewer
  /// than [lengthInDays] challenge days lie before it. Without a freeze or
  /// closing date this is exactly `startDate ≤ date ≤ endDate`.
  ///
  /// A goal revision is dated the next calendar date (addendum C7), even
  /// when that date is the first of a scheduled pause: the revision then
  /// waits and applies from the first challenge day on or after it.
  bool hasChallengeDayOnOrAfter(LocalDate date) {
    if (date.isBefore(startDate)) return false;
    if (closedOn case final last? when date.isAfter(last)) return false;
    return _challengeDaysBefore(date) < lengthInDays;
  }

  /// Where [date] falls relative to this arc's challenge days. Without a
  /// freeze or closing date, exactly as before schema v7.
  ArcDayPosition positionOn(LocalDate date) {
    final totalDays = lengthInDays;
    final offset = startDate.daysUntil(date);
    if (offset < 0) {
      return ArcNotStarted(daysUntilStart: -offset, totalDays: totalDays);
    }
    if (_freezeOn(date) case final freeze?) {
      return ArcPaused(
        lastDayNumber: _challengeDaysBefore(freeze.frozenFrom),
        pausedSince: freeze.frozenFrom,
        resumesOn: freeze.resumedOn,
        totalDays: totalDays,
      );
    }
    if (status == WinterArcStatus.ended) {
      if (closedOn case final last? when date.isAfter(last)) {
        return ArcEnded(
          lastDayNumber: _challengeDaysBefore(last) + 1,
          closedOn: last,
          totalDays: totalDays,
        );
      }
    }
    if (date.isAfter(endDate)) return ArcFinished(totalDays: totalDays);
    return ArcInProgress(
      dayNumber: _challengeDaysBefore(date) + 1,
      totalDays: totalDays,
    );
  }

  /// The freeze interval containing [date], if any.
  ArcFreeze? _freezeOn(LocalDate date) {
    for (final freeze in freezes) {
      if (freeze.contains(date)) return freeze;
    }
    return null;
  }

  /// Paused dates strictly before [date] (of an open pause, those up to
  /// [date]).
  int _pausedBefore(LocalDate date) =>
      ArcFreezeRules.pausedBefore(freezes, date);

  /// Challenge days (counted from [startDate]) strictly before [date].
  int _challengeDaysBefore(LocalDate date) =>
      startDate.daysUntil(date) - _pausedBefore(date);

  /// A copy with the given fields replaced. The [kind] never changes.
  WinterArcSession copyWith({
    LocalDate? startDate,
    LocalDate? endDate,
    WinterArcStatus? status,
    DateTime? startedAt,
    LocalDate? participationStartDate,
    List<ArcFreeze>? freezes,
    LocalDate? closedOn,
  }) => WinterArcSession(
    id: id,
    kind: kind,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
    participationStartDate:
        participationStartDate ?? this.participationStartDate,
    freezes: freezes ?? this.freezes,
    closedOn: closedOn ?? this.closedOn,
  );
}

/// Position of a calendar date relative to an arc's challenge days.
sealed class ArcDayPosition {
  const ArcDayPosition({required this.totalDays});

  /// The number of challenge days (92).
  final int totalDays;
}

final class ArcNotStarted extends ArcDayPosition {
  const ArcNotStarted({required this.daysUntilStart, required super.totalDays});

  final int daysUntilStart;
}

final class ArcInProgress extends ArcDayPosition {
  const ArcInProgress({required this.dayNumber, required super.totalDays});

  /// 1-based challenge day, `1..totalDays`.
  final int dayNumber;
}

final class ArcFinished extends ArcDayPosition {
  const ArcFinished({required super.totalDays});
}

/// A paused date of a rolling arc (schema v7): not a challenge day.
final class ArcPaused extends ArcDayPosition {
  const ArcPaused({
    required this.lastDayNumber,
    required this.pausedSince,
    required this.resumesOn,
    required super.totalDays,
  });

  /// The challenge day lived just before the pause.
  final int lastDayNumber;

  /// The first paused date.
  final LocalDate pausedSince;

  /// The first challenge date after the pause, or null while it is open.
  final LocalDate? resumesOn;
}

/// A date after the last counted day of an ended arc (schema v7): a day
/// the arc did not reach.
final class ArcEnded extends ArcDayPosition {
  const ArcEnded({
    required this.lastDayNumber,
    required this.closedOn,
    required super.totalDays,
  });

  /// The challenge day of [closedOn].
  final int lastDayNumber;
  final LocalDate closedOn;
}
