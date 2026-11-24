import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/journey/arc_calendar.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/domain/xp/level_rules.dart';

import 'fakes.dart';
import 'review_db.dart';

/// Phase 12H cross-screen reconciliation (ARC_MOMENTUM_SPEC §§ 4.5, 12.5;
/// addendum § L7 F3, F4). For one stored Arc on the clock's date, every
/// read model the screens show is built the way its screen builds it:
///
/// * Today: `HabitTrackingService.today()` (the home Arc only);
/// * Journey Path: `JourneyOverview` from `journeyFor`;
/// * Calendar: `ArcCalendar.of(journey)`;
/// * Weekly Review: `WeeklyReview.fromHistory` for each of the 13 weeks;
/// * Arc Summary and Arc History: `ArcHistoryService.card`;
/// * Insights: `InsightService.snapshot` (every started Arc);
/// * the XP ledger: raw `xp_transactions` rows, read with SQL.
///
/// The expected figures are computed here independently from the stored
/// session and raw rows, by the spec's definitions (`part(D)`, `S(T)`,
/// `O(T)`, groups A–D), never from the app's own partition. Then every
/// model is checked against them and against each other. The whole check
/// writes nothing (every table identical before and after).
///
/// Returns the figures, so a test can also pin exact numbers.
Future<ArcFigures> expectArcReconciles(
  TestApp app,
  int sessionId, {
  String context = '',
}) async {
  final before = await snapshotAll(app.db);
  final figures = await _reconcile(app, sessionId, context);
  expect(
    await snapshotAll(app.db),
    before,
    reason: '$context: reading every screen model wrote nothing',
  );
  return figures;
}

/// Every started Arc reconciles, and Insights equal the sum over them.
Future<List<ArcFigures>> expectAllArcsReconcile(
  TestApp app, {
  String context = '',
}) async {
  final before = await snapshotAll(app.db);
  final started = [
    for (final s in await app.sessions.listSessions())
      if (s.status != WinterArcStatus.setup) s,
  ];
  final all = [
    for (final s in started) await _reconcile(app, s.id, '$context #${s.id}'),
  ];
  final insights = await app.insights.snapshot();
  final overall = insights.overall;
  expect(overall.arcCount, started.length, reason: '$context: Insights arcs');
  expect(
    overall.completedArcs,
    started.where((s) => s.status == WinterArcStatus.completed).length,
    reason: '$context: an ended Arc is never a completed one',
  );
  int sum(int Function(ArcFigures f) of) =>
      all.fold(0, (total, f) => total + of(f));
  expect(overall.elapsedDays, sum((f) => f.elapsed), reason: '$context: days');
  expect(overall.fullDays, sum((f) => f.fullDays), reason: '$context: full');
  expect(
    overall.perfectDays,
    sum((f) => f.perfectDays),
    reason: '$context: Perfect Days',
  );
  expect(
    overall.minimumDaysCompleted,
    sum((f) => f.minimumDaysCompleted),
    reason: '$context: Minimum Days',
  );
  expect(overall.totalXp, sum((f) => f.ledgerXp), reason: '$context: XP');
  final active = started
      .where((s) => s.status == WinterArcStatus.active)
      .toList();
  expect(
    overall.activeArc?.id,
    active.isEmpty ? null : active.single.id,
    reason: '$context: Insights active Arc',
  );
  expect(
    await snapshotAll(app.db),
    before,
    reason: '$context: reading every screen model wrote nothing',
  );
  return all;
}

/// The facts of one Arc on one date, as every screen agrees on them.
final class ArcFigures {
  const ArcFigures({
    required this.status,
    required this.today,
    required this.elapsed,
    required this.settled,
    required this.open,
    required this.fullDays,
    required this.perfectDays,
    required this.minimumDaysCompleted,
    required this.consistencyPercent,
    required this.settledXp,
    required this.todayXp,
    required this.futureXp,
    required this.otherXp,
    required this.ledgerXp,
    required this.dayNumberToday,
  });

  final WinterArcStatus status;
  final LocalDate today;

  /// `|E(T)|`, `|S(T)|`, `|O(T)|`.
  final int elapsed;
  final int settled;
  final int open;
  final int fullDays;
  final int perfectDays;
  final int minimumDaysCompleted;
  final int consistencyPercent;

  /// Groups A–D of spec § 12.5.1 and the raw ledger sum.
  final int settledXp;
  final int todayXp;
  final int futureXp;
  final int otherXp;
  final int ledgerXp;

  /// The challenge day number of today, when today is a challenge date.
  final int? dayNumberToday;

  @override
  String toString() =>
      'ArcFigures($status on $today: E=$elapsed S=$settled O=$open '
      'full=$fullDays perfect=$perfectDays min=$minimumDaysCompleted '
      '$consistencyPercent% XP A=$settledXp B=$todayXp C=$futureXp '
      'D=$otherXp total=$ledgerXp day=$dayNumberToday)';
}

Future<ArcFigures> _reconcile(
  TestApp app,
  int sessionId,
  String context,
) async {
  final why = context.isEmpty ? 'arc $sessionId' : context;
  final session = (await app.sessions.sessionById(sessionId))!;
  final t = app.clock.today();
  final ended = session.status == WinterArcStatus.ended;

  // ---- The spec's sets, from the stored session alone. -----------------
  bool part(LocalDate d) => _participates(session, d);
  final elapsed = <LocalDate>[
    for (
      var d = session.startDate;
      !d.isAfter(t) && !d.isAfter(session.endDate);
      d = d.addDays(1)
    )
      if (part(d)) d,
  ];
  final openToday = part(t) && !ended;
  final settledSet = {
    for (final d in elapsed)
      if (d.isBefore(t) || (d == t && ended)) d,
  };
  final openSet = {if (openToday) t};
  expect(
    settledSet.intersection(openSet),
    isEmpty,
    reason: '$why: S and O are disjoint',
  );
  expect(
    {...settledSet, ...openSet},
    elapsed.toSet(),
    reason: '$why: S ∪ O = E',
  );

  // ---- Raw ledger rows (SQL, not the repository). ----------------------
  final ledger = await (app.db.select(
    app.db.xpTransactions,
  )..where((x) => x.sessionId.equals(sessionId))).get();
  var a = 0, b = 0, c = 0, other = 0, total = 0;
  for (final row in ledger) {
    final d = row.date;
    total += row.amount;
    if (d.isAfter(t)) {
      c += row.amount;
    } else if (!part(d)) {
      other += row.amount;
    } else if (d.isBefore(t) || ended) {
      a += row.amount;
    } else {
      b += row.amount;
    }
  }
  expect(
    other,
    0,
    reason:
        '$why: invariant L, no XP on a non-participating '
        'date (paused, before joining, after closedOn)',
  );

  // ---- Read models, built as each screen builds them. -----------------
  final history = await app.tracking.historyFor(sessionId);
  final journey = await app.tracking.journeyFor(sessionId);
  final calendar = ArcCalendar.of(journey);
  final weeks = ArcWeeks.of(history.session, history.today);
  final reviews = [
    for (var w = 1; w <= ArcWeeks.count; w++)
      WeeklyReview.fromHistory(history, w, weeks: weeks),
  ];
  final card = await app.history.card(sessionId);
  final summary = card.summary;

  // ---- History: the elapsed dates are E(T). ----------------------------
  expect(history.today, t, reason: '$why: history date');
  expect(history.elapsedDates, elapsed, reason: '$why: elapsed dates = E(T)');
  for (final d in history.elapsedDates) {
    expect(session.isFrozenOn(d), isFalse, reason: '$why: $d is paused');
    expect(session.isBeforeJoining(d), isFalse, reason: '$why: $d pre-join');
    if (session.closedOn case final closed?) {
      expect(d.isAfter(closed), isFalse, reason: '$why: $d after closedOn');
    }
  }
  expect(history.isTodayOpen, openToday, reason: '$why: openToday(s, T)');

  // ---- Weekly Review: S(T) and the XP groups. --------------------------
  final reviewSettled = <LocalDate>[
    for (final week in weeks.weeks) ...week.settledDates,
  ];
  expect(
    reviewSettled.toSet(),
    settledSet,
    reason: '$why: the weeks settle exactly S(T)',
  );
  expect(
    reviewSettled.length,
    settledSet.length,
    reason: '$why: each settled date in one week only',
  );
  for (final week in weeks.weeks) {
    if (week.settledDates.isNotEmpty) {
      expect(week.isReviewable, isTrue, reason: '$why: week ${week.number}');
    }
  }
  int sumReviews(int Function(WeeklyReview r) of) =>
      reviews.fold(0, (s, r) => s + of(r));
  final sumN = sumReviews((r) => r.countedDays);
  final fs = sumReviews((r) => r.fullDays);
  final ps = sumReviews((r) => r.perfectDays);
  final mcs = sumReviews((r) => r.minimumDaysCompleted);
  final xs = sumReviews((r) => r.xpEarned);
  expect(sumN, settledSet.length, reason: '$why: Σ N(w) = |S(T)|');
  expect(xs, a, reason: '$why: Σ X(w) = group A (settled XP)');

  final todayBlocks = [
    for (final r in reviews)
      if (r.today != null) r,
  ];
  if (openToday &&
      weeks.week(ArcWeeks.weekOf(session.dayNumberOf(t)!)).status ==
          ArcWeekStatus.inProgress) {
    expect(todayBlocks, hasLength(1), reason: '$why: one "Today so far"');
    final block = todayBlocks.single.today!;
    expect(block.date, t, reason: '$why: Today so far date');
    expect(block.xp, b, reason: '$why: Today so far XP = group B');
  } else {
    expect(todayBlocks, isEmpty, reason: '$why: no "Today so far"');
    expect(b, 0, reason: '$why: no open day, no group B');
  }

  final record = openToday ? history.recordOn(t) : null;
  final fo = (record != null && (record.isPerfect || record.isMinimumComplete))
      ? 1
      : 0;
  final po = (record != null && record.isPerfect) ? 1 : 0;
  final mco = (record != null && record.isMinimumComplete) ? 1 : 0;

  // ---- Identities 1–3 (§ 12.5.2) against Summary / History / Journey. --
  expect(sumN + openSet.length, elapsed.length, reason: '$why: identity 1');
  expect(summary.daysElapsed, elapsed.length, reason: '$why: daysElapsed');
  expect(fs + fo, summary.fullDays, reason: '$why: identity 2, full days');
  if (elapsed.isNotEmpty) {
    expect(
      (100 * (fs + fo)) ~/ (sumN + openSet.length),
      summary.consistencyPercent,
      reason: '$why: identity 2, consistency',
    );
  } else {
    expect(summary.consistencyPercent, 0, reason: '$why: no division');
  }
  expect(ps + po, history.perfectDays.total, reason: '$why: identity 3');
  expect(summary.perfectDays, history.perfectDays.total, reason: why);
  expect(journey.perfectDays.total, history.perfectDays.total, reason: why);
  expect(mcs + mco, summary.minimumDaysCompleted, reason: '$why: Min Days');

  // ---- XP everywhere is the ledger. -----------------------------------
  expect(history.records.totalXp, total, reason: '$why: loadArc total');
  expect(summary.totalXp, total, reason: '$why: Summary / History XP');
  expect(journey.level.totalXp, total, reason: '$why: Journey XP');
  expect(
    summary.level.level,
    LevelRules.progressFor(total).level,
    reason: '$why: level from the ledger',
  );

  // ---- Journey Path and Calendar: one classifier. ---------------------
  expect(journey.days, hasLength(92), reason: '$why: 92 Journey days');
  final cells = calendar.days.toList();
  expect(cells, hasLength(92), reason: '$why: 92 calendar cells');
  expect(calendar.blocks, hasLength(13), reason: '$why: 13 week blocks');
  for (final cell in cells) {
    final path = journey.days[cell.dayNumber - 1];
    expect(cell.state, path.state, reason: '$why: day ${cell.dayNumber}');
    expect(cell.date, path.date, reason: '$why: day ${cell.dayNumber} date');
    expect(cell.isToday, path.isToday, reason: why);
    if (cell.date case final d?) {
      expect(cell.isSettled, settledSet.contains(d), reason: '$why: $d');
      expect(session.isFrozenOn(d), isFalse, reason: '$why: no paused cell');
    }
    if (path.state == JourneyDayState.missed) {
      expect(cell.date, isNotNull, reason: '$why: a missed day has a date');
      expect(
        session.isFrozenOn(cell.date!),
        isFalse,
        reason: '$why: a paused date is never missed',
      );
    }
  }
  expect(
    cells.where((c) => c.isFull).length,
    fs,
    reason: '$why: calendar full days = Σ F(w)',
  );
  // `isToday` marks the current date whatever its state (a pre-join
  // season day included), except on an ended Arc; only an open day can
  // be in the `today` state.
  final todayCells = journey.days.where((d) => d.isToday).toList();
  for (final cell in todayCells) {
    expect(cell.date, t, reason: '$why: isToday is the current date');
  }
  if (openToday) {
    expect(todayCells, hasLength(1), reason: '$why: one today on the path');
  } else {
    for (final cell in todayCells) {
      expect(
        cell.state,
        JourneyDayState.notJoined,
        reason: '$why: no open day; only a pre-join date is marked',
      );
    }
    expect(
      journey.days.where((d) => d.state == JourneyDayState.today),
      isEmpty,
      reason: '$why: no day in the today state without an open day',
    );
  }
  if (ended) {
    expect(todayCells, isEmpty, reason: '$why: an ended Arc has no today');
  }
  if (ended) {
    for (final day in journey.days) {
      expect(day.state, isNot(JourneyDayState.today), reason: why);
      // Days after closedOn keep their planned dates but were never
      // reached (spec § 12.4): never missed, never counted.
      if (day.dayNumber > session.dayNumberOf(session.closedOn!)!) {
        expect(
          day.state,
          JourneyDayState.notReached,
          reason: '$why: day ${day.dayNumber} after closedOn',
        );
      }
    }
  }
  // One pause row per stored interval, after the last day lived before
  // it; "scheduled" exactly while it hasn't begun.
  expect(
    calendar.pauses.length,
    session.freezes.length,
    reason: '$why: pause rows',
  );
  for (final (i, pause) in calendar.pauses.indexed) {
    final freeze = session.freezes[i];
    expect(pause.firstDate, freeze.frozenFrom, reason: why);
    expect(
      pause.scheduled,
      freeze.isOpen && freeze.frozenFrom.isAfter(t),
      reason: '$why: pause $i scheduled',
    );
    expect(
      session.dayNumberOf(freeze.frozenFrom.addDays(-1)),
      pause.afterDay,
      reason: '$why: pause $i follows a lived challenge day',
    );
  }

  // ---- Today (the home Arc only). -------------------------------------
  final home = await app.sessions.currentSession();
  if (home?.id == sessionId && session.status == WinterArcStatus.active) {
    final todayModel = await app.tracking.today();
    expect(todayModel.date, t, reason: '$why: Today date');
    expect(todayModel.isTrackable, openToday, reason: '$why: trackable');
    if (record != null) {
      expect(
        todayModel.entries.where((e) => e.progress.completed).length,
        record.entries.where((e) => e.progress.completed).length,
        reason: '$why: Today and the review count the same habits',
      );
      expect(todayModel.isPerfect, record.isPerfect, reason: why);
    }
  }

  return ArcFigures(
    status: session.status,
    today: t,
    elapsed: elapsed.length,
    settled: settledSet.length,
    open: openSet.length,
    fullDays: fs + fo,
    perfectDays: ps + po,
    minimumDaysCompleted: mcs + mco,
    consistencyPercent: summary.consistencyPercent,
    settledXp: a,
    todayXp: b,
    futureXp: c,
    otherXp: other,
    ledgerXp: total,
    dayNumberToday: session.dayNumberOf(t),
  );
}

/// `part(D)` (spec § 12.5.1) from the stored session's fields, without
/// the app's own mapping: from the participation start to the end date,
/// not a paused date and, for an ended Arc, not after `closedOn`.
bool _participates(WinterArcSession s, LocalDate d) {
  final start = s.participationStartDate;
  if (start == null || d.isBefore(start) || d.isAfter(s.endDate)) {
    return false;
  }
  if (s.closedOn case final closed? when d.isAfter(closed)) return false;
  for (final f in s.freezes) {
    final resumed = f.resumedOn;
    if (!d.isBefore(f.frozenFrom) && (resumed == null || d.isBefore(resumed))) {
      return false;
    }
  }
  return true;
}
