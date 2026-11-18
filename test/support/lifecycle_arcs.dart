import 'dart:math';

import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

/// Phase 12E1 test helpers: synthetic arcs with freezes and ended arcs
/// (nothing in the app can create either yet), a brute-force model of
/// their challenge dates, and v1.2.0's date arithmetic as the regression
/// reference. All data is synthetic.

final requestedAt = DateTime.utc(2026, 1, 1, 12);
final resumedAt = DateTime.utc(2026, 1, 2, 12);

/// A closed freeze of [days] dates from [from].
ArcFreeze closedFreeze(LocalDate from, int days) => ArcFreeze(
  frozenFrom: from,
  resumedOn: from.addDays(days),
  requestedAt: requestedAt,
  resumedAt: resumedAt,
);

/// An open freeze from [from].
ArcFreeze openFreeze(LocalDate from) =>
    ArcFreeze(frozenFrom: from, requestedAt: requestedAt);

/// A rolling arc from [start] with [freezes]; the end date follows from the
/// closed ones, as Resume would store it.
WinterArcSession rollingArc(
  LocalDate start, {
  List<ArcFreeze> freezes = const [],
  WinterArcStatus status = WinterArcStatus.active,
  LocalDate? closedOn,
  int id = 1,
}) => WinterArcSession(
  id: id,
  kind: ArcKind.rolling92,
  startDate: start,
  endDate: WinterArcRules.endDateFor(start)
      .addDays(freezes.fold(0, (sum, f) => sum + (f.pausedDays ?? 0))),
  status: status,
  createdAt: DateTime(2026, 1, 1),
  startedAt: status == WinterArcStatus.setup ? null : DateTime(2026, 1, 1),
  participationStartDate: status == WinterArcStatus.setup ? null : start,
  freezes: freezes,
  closedOn: closedOn,
);

/// A seasonal arc of [year], joined on [joined] (null while in setup).
WinterArcSession seasonalArc(
  int year, {
  LocalDate? joined,
  WinterArcStatus status = WinterArcStatus.active,
  LocalDate? closedOn,
  int id = 1,
}) => WinterArcSession(
  id: id,
  kind: ArcKind.seasonalWinter,
  startDate: LocalDate(year, 10, 1),
  endDate: LocalDate(year, 12, 31),
  status: status,
  createdAt: DateTime(year, 9, 1),
  startedAt: joined == null ? null : DateTime(year, 10, 1),
  participationStartDate: joined,
  closedOn: closedOn,
);

/// The challenge dates of [session], found by walking the calendar one date
/// at a time from the start and skipping paused dates (independent of the
/// mapping under test): Day `n` is element `n − 1`. Stops at Day 92, or at
/// the start of an open freeze (later days have no date yet).
List<LocalDate> bruteChallengeDates(WinterArcSession session) {
  bool frozen(LocalDate d) => session.freezes.any(
    (f) =>
        !d.isBefore(f.frozenFrom) &&
        (f.resumedOn == null || d.isBefore(f.resumedOn!)),
  );
  final dates = <LocalDate>[];
  var date = session.startDate;
  while (dates.length < WinterArcRules.lengthInDays) {
    if (frozen(date)) {
      final open = session.freezes.any(
        (f) => f.resumedOn == null && !date.isBefore(f.frozenFrom),
      );
      if (open) break;
    } else {
      dates.add(date);
    }
    date = date.addDays(1);
  }
  return dates;
}

/// v1.2.0's date arithmetic, verbatim from `winter_arc_session.dart` and
/// its callers at `933960c` (before schema v7), for sessions without a
/// freeze or closing date. The regression reference: the new mapping must
/// give exactly these answers for every such session.
final class V12Arithmetic {
  const V12Arithmetic(this.s);

  final WinterArcSession s;

  int get lengthInDays => s.startDate.daysUntil(s.endDate) + 1;

  bool isParticipatingOn(LocalDate date) {
    final joined = s.participationStartDate;
    return joined != null && !date.isBefore(joined) && !date.isAfter(s.endDate);
  }

  List<LocalDate> participatingDatesThrough(LocalDate today) {
    final joined = s.participationStartDate;
    if (joined == null) return const [];
    final last = today.isBefore(s.endDate) ? today : s.endDate;
    final count = joined.daysUntil(last) + 1;
    return [for (var i = 0; i < count; i++) joined.addDays(i)];
  }

  int? get joinDayNumber => switch (s.participationStartDate) {
    null => null,
    final joined => dayNumberOf(joined),
  };

  int get participationLengthInDays =>
      s.participationStartDate!.daysUntil(s.endDate) + 1;

  bool isOverOn(LocalDate date) => date.isAfter(s.endDate);

  int dayNumberOf(LocalDate date) => s.startDate.daysUntil(date) + 1;

  /// What callers computed: `startDate.addDays(day − 1)` (ArcHistory,
  /// AchievementRules).
  LocalDate dateOfDay(int day) => s.startDate.addDays(day - 1);

  /// `HabitTrackingService._nextChallengeDay`.
  LocalDate? nextChallengeDay(LocalDate date) {
    final next = date.addDays(1);
    return positionOn(next) is ArcInProgress ? next : null;
  }

  ArcDayPosition positionOn(LocalDate date) {
    final offset = s.startDate.daysUntil(date);
    if (offset < 0) {
      return ArcNotStarted(daysUntilStart: -offset, totalDays: lengthInDays);
    }
    if (offset >= lengthInDays) {
      return ArcFinished(totalDays: lengthInDays);
    }
    return ArcInProgress(dayNumber: offset + 1, totalDays: lengthInDays);
  }
}

/// A comparable description of a position.
String describe(ArcDayPosition p) => switch (p) {
  ArcNotStarted(:final daysUntilStart, :final totalDays) =>
    'notStarted($daysUntilStart/$totalDays)',
  ArcInProgress(:final dayNumber, :final totalDays) =>
    'inProgress($dayNumber/$totalDays)',
  ArcFinished(:final totalDays) => 'finished($totalDays)',
  ArcPaused(:final lastDayNumber, :final pausedSince, :final resumesOn) =>
    'paused($lastDayNumber, $pausedSince, $resumesOn)',
  ArcEnded(:final lastDayNumber, :final closedOn) =>
    'ended($lastDayNumber, $closedOn)',
};

/// Deterministic generators of synthetic arcs.
final class ArcGenerator {
  ArcGenerator(int seed) : _random = Random(seed);

  final Random _random;

  int nextInt(int max) => _random.nextInt(max);
  bool chance(double p) => _random.nextDouble() < p;

  /// A date between 2019 and 2036, leap years and year ends included.
  LocalDate date() => LocalDate(2019, 1, 1).addDays(_random.nextInt(6574));

  /// A pause length: mostly short, sometimes very long.
  int pauseLength() => switch (_random.nextInt(10)) {
    0 => 1,
    1 => 92,
    2 => 400,
    _ => 1 + _random.nextInt(30),
  };

  /// A rolling arc without a freeze, in any status.
  WinterArcSession plainRolling() {
    final status = WinterArcStatus
        .values[_random.nextInt(3)]; // setup, active or completed
    return rollingArc(date(), status: status);
  }

  /// A seasonal arc without a freeze: setup, or joined on any season day.
  WinterArcSession plainSeasonal() {
    final year = 2019 + _random.nextInt(18);
    if (chance(0.15)) {
      return seasonalArc(year, status: WinterArcStatus.setup);
    }
    return seasonalArc(
      year,
      joined: LocalDate(year, 10, 1).addDays(_random.nextInt(92)),
      status: chance(0.5) ? WinterArcStatus.active : WinterArcStatus.completed,
    );
  }

  /// An active rolling arc with up to [maxFreezes] valid pauses, as Freeze
  /// and Resume would produce them: each starts the day after a lived day,
  /// at least one challenge day after the previous resume, and before Day
  /// 92. The last may be open.
  WinterArcSession pausedRolling({int maxFreezes = 5, bool allowOpen = true}) {
    final start = date();
    final freezes = <ArcFreeze>[];
    var day = 1; // the last challenge day lived before the next pause
    var paused = 0;
    final count = 1 + _random.nextInt(maxFreezes);
    for (var i = 0; i < count; i++) {
      if (day > 91) break; // no challenge day left to pause
      day += _random.nextInt(92 - day); // any of [day, 91]
      final from = start.addDays(day + paused); // the day after Day [day]
      final open = allowOpen && i == count - 1 && chance(0.35);
      if (open) {
        freezes.add(openFreeze(from));
        break;
      }
      final length = pauseLength();
      freezes.add(closedFreeze(from, length));
      paused += length;
      day += 1; // the resume date is the next challenge day, lived
    }
    return rollingArc(start, freezes: freezes);
  }
}
