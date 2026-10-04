import '../../core/time/local_date.dart';
import 'arc_kind.dart';

export 'arc_kind.dart';

/// Configuration of the Winter Arc challenge itself.
abstract final class WinterArcRules {
  /// A Winter Arc lasts 92 calendar days (inclusive of start and end).
  ///
  /// A rolling arc started on October 1 ends exactly on December 31, which
  /// is also the Seasonal Winter Arc's window.
  static const int lengthInDays = 92;

  /// The inclusive end date of a rolling arc that starts on [start].
  static LocalDate endDateFor(LocalDate start) =>
      start.addDays(lengthInDays - 1);

  /// The first rule [session] breaks, or null if it is a valid session:
  ///
  /// * every arc: the end is not before the start
  /// * rolling: exactly [lengthInDays] days; once started, participation
  ///   begins on the start date
  /// * seasonal: exactly 1 October – 31 December of one year; once started,
  ///   participation begins inside that window
  /// * a session in setup has no participation date yet
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
    switch (session.kind) {
      case ArcKind.rolling92:
        if (end != endDateFor(start)) return 'not a $lengthInDays-day arc';
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
    return null;
  }
}

/// Lifecycle of a session. Persisted by [name], so never rename values.
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
}

/// One 92-day Winter Arc attempt: a rolling arc or one Seasonal Winter
/// Arc.
///
/// Day numbers always count from [startDate]. For a seasonal arc that is
/// 1 October, so a user who joins on 15 October is on Day 15 of 92, not
/// Day 1. The days a user actually takes part in run from
/// [participationStartDate] to [endDate]; earlier days of a season are
/// neutral ("before you joined") and never count for or against them.
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
  });

  final int id;

  /// Rolling or seasonal. Fixed for the life of the session.
  final ArcKind kind;

  /// First challenge day (Day 1). Provisional while a rolling arc is in
  /// [WinterArcStatus.setup]; always 1 October for a seasonal arc.
  final LocalDate startDate;

  /// Last challenge day (inclusive).
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

  int get lengthInDays => startDate.daysUntil(endDate) + 1;

  bool get isSeasonal => kind.isSeasonal;

  /// The first participating date of a started session.
  ///
  /// Throws [StateError] for a session still in setup, which has no
  /// participation and no history.
  LocalDate get participationStart =>
      participationStartDate ??
      (throw StateError('Session $id has not started'));

  /// Whether [date] is one of the days the user takes part in: from the
  /// participation start through [endDate]. False for every date of a
  /// session still in setup.
  bool isParticipatingOn(LocalDate date) {
    final joined = participationStartDate;
    return joined != null && !date.isBefore(joined) && !date.isAfter(endDate);
  }

  /// Whether [date] is a day of the arc before the user joined it (only
  /// possible for a seasonal arc joined late). Such days are neutral.
  bool isBeforeJoining(LocalDate date) {
    final joined = participationStartDate;
    return joined != null && !date.isBefore(startDate) && date.isBefore(joined);
  }

  /// The participating dates that have started by [today], oldest first:
  /// from the participation start through `min(today, endDate)`. Empty
  /// before the participation start and for a session in setup.
  List<LocalDate> participatingDatesThrough(LocalDate today) {
    final joined = participationStartDate;
    if (joined == null) return const [];
    final last = today.isBefore(endDate) ? today : endDate;
    final count = joined.daysUntil(last) + 1;
    return [for (var i = 0; i < count; i++) joined.addDays(i)];
  }

  /// Whether the user joined after Day 1 (a seasonal arc joined late).
  bool get joinedLate =>
      participationStartDate != null &&
      participationStartDate!.isAfter(startDate);

  /// The challenge day the user joined on (Day 1 for a rolling arc), or
  /// null in setup.
  int? get joinDayNumber => switch (participationStartDate) {
    null => null,
    final joined => dayNumberOf(joined),
  };

  /// How many days the user takes part in, from joining to the last day.
  int get participationLengthInDays =>
      participationStart.daysUntil(endDate) + 1;

  /// Whether every challenge day is over on [date]. The arc stays open for
  /// the whole of its last day, so this is only true from the day after
  /// [endDate].
  bool isOverOn(LocalDate date) => date.isAfter(endDate);

  /// 1-based challenge day of [date] (can be outside `1..lengthInDays`).
  int dayNumberOf(LocalDate date) => startDate.daysUntil(date) + 1;

  /// Where [date] falls relative to this arc's window.
  ArcDayPosition positionOn(LocalDate date) {
    final offset = startDate.daysUntil(date);
    if (offset < 0) {
      return ArcNotStarted(daysUntilStart: -offset, totalDays: lengthInDays);
    }
    if (offset >= lengthInDays) {
      return ArcFinished(totalDays: lengthInDays);
    }
    return ArcInProgress(dayNumber: offset + 1, totalDays: lengthInDays);
  }

  /// A copy with the given fields replaced. The [kind] never changes.
  WinterArcSession copyWith({
    LocalDate? startDate,
    LocalDate? endDate,
    WinterArcStatus? status,
    DateTime? startedAt,
    LocalDate? participationStartDate,
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
  );
}

/// Position of a calendar date relative to an arc's window.
sealed class ArcDayPosition {
  const ArcDayPosition({required this.totalDays});

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
