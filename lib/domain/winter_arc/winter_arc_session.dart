import '../../core/time/local_date.dart';

/// Configuration of the Winter Arc challenge itself.
abstract final class WinterArcRules {
  /// A Winter Arc lasts 92 calendar days (inclusive of start and end).
  ///
  /// Started on October 1 this ends exactly on December 31.
  static const int lengthInDays = 92;

  /// The inclusive end date of an arc that starts on [start].
  static LocalDate endDateFor(LocalDate start) =>
      start.addDays(lengthInDays - 1);
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

/// One 92-day Winter Arc attempt.
final class WinterArcSession {
  const WinterArcSession({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    this.startedAt,
  });

  final int id;

  /// First challenge day (Day 1). Provisional while in [WinterArcStatus.setup].
  final LocalDate startDate;

  /// Last challenge day (inclusive).
  final LocalDate endDate;
  final WinterArcStatus status;
  final DateTime createdAt;

  /// When the user pressed "Start Winter Arc". Null while in setup.
  final DateTime? startedAt;

  int get lengthInDays => startDate.daysUntil(endDate) + 1;

  /// Whether every challenge day is over on [date]. The arc stays open for
  /// the whole of its last day, so this is only true from the day after
  /// [endDate].
  bool isOverOn(LocalDate date) => date.isAfter(endDate);

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

  WinterArcSession copyWith({
    LocalDate? startDate,
    LocalDate? endDate,
    WinterArcStatus? status,
    DateTime? startedAt,
  }) => WinterArcSession(
    id: id,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
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
