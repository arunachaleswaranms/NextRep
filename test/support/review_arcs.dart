import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'lifecycle_arcs.dart';

/// Phase 12B test helpers: synthetic Arc histories for the Weekly Review,
/// and an independent reference for its partitions, computed straight
/// from the definitions of ARC_MOMENTUM_SPEC §§ 12.5.1–12.5.2 (never
/// through `ArcWeeks` or `WeeklyReview`). All data is synthetic.

/// A habit with a display title, in display order [order].
Habit namedHabit(
  String id,
  String title, {
  required int order,
  bool binary = true,
  int target = 1,
  int minimum = 1,
}) => Habit(
  id: id,
  title: title,
  type: binary ? HabitType.binary : HabitType.count,
  target: binary ? 1 : target,
  minimumTarget: binary ? 1 : minimum,
  unit: binary ? null : 'u',
  iconKey: id,
  enabled: true,
  sortOrder: order,
  createdAt: DateTime(2026, 1, 1),
);

/// The five habits of the spec's worked examples (§ 4.6), in display
/// order. Completion is read from stored flags, so their types don't
/// matter to the review.
final specHabits = [
  namedHabit('water', 'Water', order: 0, binary: false, target: 8, minimum: 4),
  namedHabit(
    'workout',
    'Workout',
    order: 1,
    binary: false,
    target: 30,
    minimum: 10,
  ),
  namedHabit('reading', 'Reading', order: 2),
  namedHabit('sleep', 'Sleep Before', order: 3),
  namedHabit('junk', 'No Junk Food', order: 4),
];

/// One day's stored data: completed habit ids, partial (incomplete) values,
/// mode and ledger XP.
typedef DayData = ({
  Set<String> done,
  Map<String, int> partial,
  DayMode mode,
  int xp,
});

DayData day(
  Set<String> done, {
  Map<String, int> partial = const {},
  DayMode mode = DayMode.normal,
  int xp = 0,
}) => (done: done, partial: partial, mode: mode, xp: xp);

/// The history of [session] on [today] with [habits] and the stored [days].
ArcHistory historyOf(
  WinterArcSession session,
  LocalDate today, {
  List<Habit>? habits,
  List<HabitRevision> revisions = const [],
  Map<LocalDate, DayData> days = const {},
  Map<LocalDate, int> extraXp = const {},
}) {
  final xp = <LocalDate, int>{
    for (final MapEntry(key: date, value: d) in days.entries)
      if (d.xp > 0) date: d.xp,
  };
  for (final MapEntry(key: date, value: amount) in extraXp.entries) {
    xp[date] = (xp[date] ?? 0) + amount;
  }
  return ArcHistory(
    session: session,
    today: today,
    records: ArcRecords(
      habits: HabitHistory(habits: habits ?? specHabits, revisions: revisions),
      progress: <DailyHabitProgress>[
        for (final MapEntry(key: date, value: d) in days.entries) ...[
          for (final id in d.done)
            DailyHabitProgress(
              habitId: id,
              date: date,
              currentValue: 30,
              completed: true,
              completedAt: date.toLocalDateTime(),
            ),
          for (final MapEntry(key: id, value: value) in d.partial.entries)
            DailyHabitProgress(
              habitId: id,
              date: date,
              currentValue: value,
              completed: false,
            ),
        ],
      ],
      modes: {
        for (final MapEntry(key: date, value: d) in days.entries)
          if (d.mode == DayMode.minimum) date: DayMode.minimum,
      },
      xpByDate: xp,
      totalXp: xp.values.fold(0, (a, b) => a + b),
    ),
  );
}

/// All five spec habits done.
const allFive = {'water', 'workout', 'reading', 'sleep', 'junk'};

/// The partitions of spec § 12.5.2 and § 12.5.1 for [h], from their
/// definitions.
final class Reference {
  Reference(this.h) {
    final s = h.session;
    final t = h.today;
    elapsed = s.participatingDatesThrough(t);
    open = s.isOpenOn(t) ? {t} : const {};
    settled = [
      for (final d in elapsed)
        if (!open.contains(d)) d,
    ];
    for (final MapEntry(key: d, value: amount) in h.records.xpByDate.entries) {
      if (d.isAfter(t)) {
        futureXp += amount;
      } else if (!s.isParticipatingOn(d)) {
        otherXp += amount;
      } else if (d.isBefore(t) || s.status == WinterArcStatus.ended) {
        settledXp += amount;
      } else {
        todayXp += amount;
      }
    }
  }

  final ArcHistory h;

  /// `E(T)`.
  late final List<LocalDate> elapsed;

  /// `O(T)`.
  late final Set<LocalDate> open;

  /// `S(T)`.
  late final List<LocalDate> settled;

  int settledXp = 0;
  int todayXp = 0;
  int futureXp = 0;
  int otherXp = 0;

  bool _full(LocalDate d) =>
      h.recordOn(d).isPerfect || h.recordOn(d).isMinimumComplete;

  int get settledFull => settled.where(_full).length;
  int get openFull => open.where(_full).length;
  int get settledPerfect =>
      settled.where((d) => h.recordOn(d).isPerfect).length;
  int get openPerfect => open.where((d) => h.recordOn(d).isPerfect).length;

  ArcSummary get summary =>
      ArcSummary.fromHistory(h, achievementsUnlocked: 0, achievementsTotal: 32);
}

/// The reviews of all 13 weeks of [h].
List<WeeklyReview> allReviews(ArcHistory h) {
  final weeks = ArcWeeks.of(h.session, h.today);
  return [
    for (var w = 1; w <= ArcWeeks.count; w++)
      WeeklyReview.fromHistory(h, w, weeks: weeks),
  ];
}

/// The Journey state class that matches an Arc-week day class: the review
/// strip and the Journey must agree on every day.
bool classMatchesJourney(ArcDayClass c, JourneyDay j) => switch (c) {
  ArcDayClass.neutral => j.state == JourneyDayState.notJoined,
  ArcDayClass.notReached => j.state == JourneyDayState.notReached,
  ArcDayClass.upcoming => j.state == JourneyDayState.future,
  ArcDayClass.open => j.isToday && j.record != null,
  ArcDayClass.settled => j.state.isFinal && !j.isToday,
};

/// Deterministic generator of synthetic histories over every Arc status:
/// Rolling (with zero, one or several pauses, scheduled and open) and
/// Seasonal (late joins), active, completed and ended.
final class HistoryGenerator {
  HistoryGenerator(int seed) : _arcs = ArcGenerator(seed);

  final ArcGenerator _arcs;

  static final _habits = [
    namedHabit('a', 'Alpha', order: 0),
    namedHabit('b', 'Beta', order: 1),
    namedHabit('c', 'Gamma', order: 2),
  ];

  /// A valid started session of any status.
  WinterArcSession session() {
    while (true) {
      final candidate = _candidate();
      if (WinterArcRules.problemWith(candidate) == null) return candidate;
    }
  }

  WinterArcSession _candidate() {
    switch (_arcs.nextInt(6)) {
      case 0:
        return rollingArc(_arcs.date());
      case 1:
        return _arcs.pausedRolling();
      case 2:
        final paused = _arcs.pausedRolling(allowOpen: false);
        return paused.copyWith(status: WinterArcStatus.completed);
      case 3:
        final year = 2019 + _arcs.nextInt(18);
        return seasonalArc(
          year,
          joined: LocalDate(year, 10, 1).addDays(_arcs.nextInt(92)),
          status: _arcs.chance(0.5)
              ? WinterArcStatus.active
              : WinterArcStatus.completed,
        );
      case 4:
        final base = _arcs.chance(0.6)
            ? _arcs.pausedRolling(allowOpen: false)
            : rollingArc(_arcs.date());
        return _ended(base);
      default:
        final year = 2019 + _arcs.nextInt(18);
        final joined = LocalDate(year, 10, 1).addDays(_arcs.nextInt(92));
        return _ended(seasonalArc(year, joined: joined));
    }
  }

  /// [base] ended on one of its challenge days after its last pause.
  WinterArcSession _ended(WinterArcSession base) {
    final lastPauseEnd = base.freezes.isEmpty
        ? base.participationStart
        : base.freezes.last.resumedOn!;
    final first = base.dayNumberOf(lastPauseEnd)!;
    final dayNumber = first + _arcs.nextInt(93 - first);
    final closedOn = base.dateOfDay(dayNumber.clamp(1, 92))!;
    return base.copyWith(status: WinterArcStatus.ended, closedOn: closedOn);
  }

  /// Random stored data on every participating date of [s] (so the ledger
  /// meets invariant L), with revisions that disable and re-enable habits.
  ArcHistory history(WinterArcSession s, LocalDate today) {
    final dates = s.participatingDatesThrough(LocalDate(2100, 1, 1));
    final days = <LocalDate, DayData>{};
    for (final d in dates) {
      if (_arcs.chance(0.1)) continue; // nothing logged
      final done = {
        for (final h in _habits)
          if (_arcs.chance(0.6)) h.id,
      };
      final partial = {
        for (final h in _habits)
          if (!done.contains(h.id) && _arcs.chance(0.3)) h.id: 1,
      };
      days[d] = day(
        done,
        partial: partial,
        mode: _arcs.chance(0.2) ? DayMode.minimum : DayMode.normal,
        xp: _arcs.chance(0.8) ? 1 + _arcs.nextInt(200) : 0,
      );
    }
    final revisions = <HabitRevision>[
      if (dates.length > 10)
        HabitRevision(
          habitId: 'c',
          effectiveFrom: dates[_arcs.nextInt(dates.length)],
          config: const HabitConfig(
            target: 1,
            minimumTarget: 1,
            enabled: false,
          ),
          createdAt: DateTime(2026, 1, 1),
        ),
    ];
    return historyOf(
      s,
      today,
      habits: _habits,
      revisions: revisions,
      days: days,
    );
  }

  /// Dates to view [s] on: before the start, around every boundary, inside
  /// pauses and after the end, plus random ones.
  List<LocalDate> todays(WinterArcSession s) {
    final start = s.startDate;
    final span = s.calendarSpanInDays + 20;
    return {
      start.addDays(-2),
      start.addDays(-1),
      s.participationStart,
      s.participationStart.addDays(-1),
      for (var day = 1; day <= 92; day += 7) ?s.dateOfDay(day),
      for (var day = 7; day <= 92; day += 7) ?s.dateOfDay(day),
      ?s.dateOfDay(92),
      s.endDate,
      s.endDate.addDays(1),
      ?s.closedOn,
      ?s.closedOn?.addDays(-1),
      ?s.closedOn?.addDays(1),
      for (final f in s.freezes) ...[
        f.frozenFrom.addDays(-1),
        f.frozenFrom,
        f.frozenFrom.addDays(1),
        ?f.resumedOn,
      ],
      for (var i = 0; i < 8; i++) start.addDays(_arcs.nextInt(span) - 5),
    }.toList();
  }
}

/// Checks every identity of spec §§ 12.5.1–12.5.2 for [h] against the
/// independent [Reference], and returns it.
Reference checkIdentities(ArcHistory h) {
  final ref = Reference(h);
  final reviews = allReviews(h);
  final summary = ref.summary;
  final n = reviews.fold(0, (s, r) => s + r.countedDays);
  final f = reviews.fold(0, (s, r) => s + r.fullDays);
  final p = reviews.fold(0, (s, r) => s + r.perfectDays);
  final x = reviews.fold(0, (s, r) => s + r.xpEarned);
  final todays = [for (final r in reviews) ?r.today];
  final reason = '${h.session} on ${h.today}';

  // S(T) and O(T) partition E(T); no paused, neutral, not-reached or
  // future date is in either.
  expect(ref.settled.toSet().intersection(ref.open), isEmpty, reason: reason);
  expect({...ref.settled, ...ref.open}, ref.elapsed.toSet(), reason: reason);
  final weeklySettled = [for (final r in reviews) ...r.week.settledDates];
  expect(weeklySettled, ref.settled, reason: reason);
  expect(weeklySettled.toSet(), hasLength(weeklySettled.length));
  for (final d in weeklySettled) {
    expect(h.session.isParticipatingOn(d), isTrue, reason: reason);
    expect(d.isAfter(h.today), isFalse, reason: reason);
  }

  // Identity 1: day count.
  expect(n + ref.open.length, ref.elapsed.length, reason: reason);
  expect(n + ref.open.length, summary.daysElapsed, reason: reason);
  // Identity 2: full days and consistency.
  final fo = ref.openFull;
  expect(f, ref.settledFull, reason: reason);
  expect(f + fo, summary.fullDays, reason: reason);
  if (ref.elapsed.isNotEmpty) {
    expect(
      (100 * (f + fo)) ~/ (n + ref.open.length),
      summary.consistencyPercent,
      reason: reason,
    );
  } else {
    expect(summary.consistencyPercent, 0, reason: reason);
    for (final r in reviews) {
      expect(r.consistencyPercent, isNull, reason: reason);
    }
  }
  // Identity 3: Perfect Days.
  expect(p + ref.openPerfect, h.perfectDays.total, reason: reason);

  // XP split: A = Σ_w X(w), B = Today so far, C future, D other = 0.
  expect(x, ref.settledXp, reason: reason);
  expect(todays.fold(0, (s, t) => s + t.xp), ref.todayXp, reason: reason);
  expect(ref.otherXp, 0, reason: reason);
  expect(
    ref.settledXp + ref.todayXp + ref.futureXp + ref.otherXp,
    h.records.totalXp,
    reason: reason,
  );
  // Today so far exists exactly when today is open, in its in-progress
  // week, and never for an ended Arc.
  expect(todays, hasLength(ref.open.length), reason: reason);
  if (h.session.status == WinterArcStatus.ended) {
    expect(todays, isEmpty, reason: reason);
  }
  for (final r in reviews) {
    if (r.today != null) {
      expect(r.status, ArcWeekStatus.inProgress, reason: reason);
    }
    if (!r.week.isReviewable) {
      expect(r.countedDays, 0, reason: reason);
      expect(r.xpEarned, 0, reason: reason);
      expect(r.today, isNull, reason: reason);
    }
  }
  return ref;
}
