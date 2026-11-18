import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/review/weekly_review.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_arcs.dart';
import '../support/review_db.dart';

/// Phase 12B, PHASE_12A § L1 "XP reconciliation after date rollback" and
/// its addendum variants (spec § 12.8): a real in-memory SQLite database,
/// an injected clock, history written through the app's own tracking
/// service, then the Weekly Review read at D − 1, D and D + 1. After every
/// read the XP ledger rows and every table are compared with the state
/// right after the writes: identical, nothing duplicated, lost or awarded.
/// Also: reviews over restored format 1–4 backups. All data synthetic.

final wed = LocalDate(2026, 10, 7);
LocalDate dOf(int day) => wed.addDays(day - 1);

/// One review read at [date]: the history the provider would load, its
/// identities checked, and the database compared before and after.
Future<({ArcHistory h, Reference ref, List<WeeklyReview> reviews})> readAt(
  TestApp app,
  int sessionId,
  LocalDate date, {
  required List<XpTransactionRow> ledger,
}) async {
  at(app, date);
  final before = await snapshotAll(app.db);
  final h = await app.tracking.historyFor(sessionId);
  final ref = checkIdentities(h);
  final reviews = allReviews(h);
  // Nothing written by reading: every table, and the ledger exactly.
  expect(await snapshotAll(app.db), before);
  final rows = await xpRows(app.db);
  expect(rows, ledger, reason: 'ledger rows byte-identical');
  expect(
    rows.map((r) => (r.sessionId, r.sourceKey)).toSet(),
    hasLength(rows.length),
    reason: 'no XP duplicated',
  );
  expect(
    h.records.totalXp,
    ledger
        .where((r) => r.sessionId == sessionId)
        .fold(0, (s, r) => s + r.amount),
    reason: 'no XP lost',
  );
  return (h: h, ref: ref, reviews: reviews);
}

int xpOn(List<XpTransactionRow> ledger, LocalDate date) =>
    ledger.where((r) => r.date == date).fold(0, (s, r) => s + r.amount);

int settledOf(List<WeeklyReview> reviews) =>
    reviews.fold(0, (s, r) => s + r.xpEarned);

int todayOf(List<WeeklyReview> reviews) =>
    reviews.fold(0, (s, r) => s + (r.today?.xp ?? 0));

void main() {
  late AppDatabase db;
  late TestApp app;

  setUp(() {
    db = memoryDatabase();
    app = TestApp(db, FakeClock(DateTime(2026, 10, 7, 9)));
  });
  tearDown(() => db.close());

  /// A Rolling Arc from [start], every habit completed on Days 1..[days]
  /// through the real tracking service.
  Future<WinterArcSession> lived(LocalDate start, int days) async {
    at(app, start);
    await app.winterArc.beginSetup();
    final arc = await app.winterArc.startWinterArc();
    for (var d = 1; d <= days; d++) {
      at(app, start.addDays(d - 1));
      await completeAll(app);
    }
    return arc;
  }

  test(
    'normal active Arc: D − 1, D, D + 1 (PHASE_12A § L1 steps 1–15)',
    () async {
      final arc = await lived(wed, 3);
      final d = dOf(3);
      final ledger = await xpRows(db);
      final xpD = xpOn(ledger, d);
      expect(xpD, greaterThan(0));
      expect(ledger.where((r) => r.date == d), isNotEmpty);

      final back = await readAt(app, arc.id, d.addDays(-1), ledger: ledger);
      expect(back.ref.futureXp, xpD);
      expect(settledOf(back.reviews), xpOn(ledger, dOf(1)));
      expect(todayOf(back.reviews), xpOn(ledger, dOf(2)));

      final on = await readAt(app, arc.id, d, ledger: ledger);
      expect(todayOf(on.reviews), xpD);
      expect(on.ref.futureXp, 0);
      expect(on.reviews[0].today!.dayNumber, 3);

      final after = await readAt(app, arc.id, d.addDays(1), ledger: ledger);
      expect(
        after.reviews[0].xpEarned,
        xpOn(ledger, dOf(1)) + xpOn(ledger, dOf(2)) + xpD,
      );
      expect(todayOf(after.reviews), 0);
      expect(after.ref.futureXp, 0);
    },
  );

  test('rollback across the Day 7 / Day 8 week boundary', () async {
    final arc = await lived(wed, 8);
    final ledger = await xpRows(db);
    final xp8 = xpOn(ledger, dOf(8));
    final xpWeek1 = [for (var d = 1; d <= 7; d++) xpOn(ledger, dOf(d))]
        .fold(0, (a, b) => a + b);

    final back = await readAt(app, arc.id, dOf(7), ledger: ledger);
    expect(back.reviews[0].status, ArcWeekStatus.inProgress);
    expect(back.reviews[1].status, ArcWeekStatus.upcoming);
    expect(ArcWeeks.of(back.h.session, back.h.today).reviewableWeeks, [1]);
    expect(back.reviews[0].xpEarned, xpWeek1 - xpOn(ledger, dOf(7)));
    expect(back.reviews[0].today!.xp, xpOn(ledger, dOf(7)));
    expect(back.ref.futureXp, xp8);

    final on = await readAt(app, arc.id, dOf(8), ledger: ledger);
    expect(on.reviews[0].xpEarned, xpWeek1);
    expect(on.reviews[1].today!.xp, xp8);

    final after = await readAt(app, arc.id, dOf(9), ledger: ledger);
    expect(after.reviews[1].xpEarned, xp8);
  });

  test(
    'before the participation start: Rolling started on D and Seasonal '
    'joined on D; no reviewable week, the whole ledger future-dated',
    () async {
      final d = LocalDate(2026, 10, 18);
      final rolling = await lived(d, 1);
      var ledger = await xpRows(db);
      final back = await readAt(app, rolling.id, d.addDays(-1), ledger: ledger);
      expect(
        ArcWeeks.of(back.h.session, back.h.today).hasReviewableWeek,
        isFalse,
      );
      expect(settledOf(back.reviews), 0);
      expect(todayOf(back.reviews), 0);
      expect(back.ref.futureXp, back.h.records.totalXp);
      expect(back.h.records.totalXp, greaterThan(0));

      // The Seasonal Arc, in a database of its own.
      final seasonalDb = memoryDatabase();
      addTearDown(seasonalDb.close);
      app = TestApp(seasonalDb, FakeClock(DateTime(2026, 10, 18, 9)));
      final seasonal = await joinSeason(app, DateTime(2026, 10, 18));
      await completeAll(app);
      ledger = await xpRows(seasonalDb);
      final s = await readAt(app, seasonal.id, d.addDays(-1), ledger: ledger);
      expect(ArcWeeks.of(s.h.session, s.h.today).hasReviewableWeek, isFalse);
      expect(s.ref.futureXp, s.h.records.totalXp);
      expect(settledOf(s.reviews) + todayOf(s.reviews), 0);
    },
  );

  test('late Seasonal join: rollback inside the join week', () async {
    final seasonal = await joinSeason(app, DateTime(2026, 10, 18));
    for (final day in [18, 19, 20]) {
      at(app, LocalDate(2026, 10, day));
      await completeAll(app);
    }
    final ledger = await xpRows(db);
    final back = await readAt(
      app,
      seasonal.id,
      LocalDate(2026, 10, 19),
      ledger: ledger,
    );
    final w3 = back.reviews[2];
    expect(w3.status, ArcWeekStatus.inProgress);
    expect(w3.countedDays, 1); // 18 Oct; 15–17 Oct neutral
    expect(back.ref.futureXp, xpOn(ledger, LocalDate(2026, 10, 20)));
    expect(back.reviews[0].status, ArcWeekStatus.beforeJoining);
    final after = await readAt(
      app,
      seasonal.id,
      LocalDate(2026, 10, 22),
      ledger: ledger,
    );
    // 18–21 Oct: 21 Oct had nothing logged and is still a counted day.
    expect(after.reviews[2].countedDays, 4);
    expect(after.reviews[2].status, ArcWeekStatus.complete);
  });

  test(
    'completed Arc rolled back into it: stays completed, nothing written',
    () async {
      final arc = await runFirstArc(app); // Days 1–3 lived, closed out
      expect(arc.status, WinterArcStatus.completed);
      final ledger = await xpRows(db);
      final day1 = LocalDate(2026, 7, 1);
      final d = day1.addDays(2); // Day 3
      final xpD = xpOn(ledger, d);
      expect(xpD, greaterThan(0));

      final back = await readAt(app, arc.id, d.addDays(-1), ledger: ledger);
      expect(back.ref.futureXp, xpD);
      expect(back.h.session.status, WinterArcStatus.completed);
      final on = await readAt(app, arc.id, d, ledger: ledger);
      expect(todayOf(on.reviews), xpD);
      expect(on.reviews[0].status, ArcWeekStatus.inProgress);
      final after = await readAt(app, arc.id, d.addDays(1), ledger: ledger);
      expect(after.reviews[0].xpEarned, back.h.records.totalXp);
      final over = await readAt(
        app,
        arc.id,
        LocalDate(2026, 10, 1),
        ledger: ledger,
      );
      expect(
        over.reviews.every((r) => r.status == ArcWeekStatus.complete),
        isTrue,
      );
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.completed,
      );
    },
  );

  test('ended Arc (closedOn = D): settled on D and after; future-dated '
      'before; never Today so far', () async {
    final arc = await lived(wed, 3);
    final d = dOf(3);
    await endArc(app, arc.id, d);
    final ledger = await xpRows(db);
    final xpD = xpOn(ledger, d);

    final on = await readAt(app, arc.id, d, ledger: ledger);
    expect(settledOf(on.reviews), on.h.records.totalXp);
    expect(todayOf(on.reviews), 0);
    expect(on.reviews.every((r) => r.today == null), isTrue);
    expect(on.reviews[0].isFinalReview, isTrue);

    final back = await readAt(app, arc.id, d.addDays(-1), ledger: ledger);
    expect(back.ref.futureXp, xpD);
    expect(todayOf(back.reviews), 0);
    expect(back.reviews[0].countedDays, 2);

    final again = await readAt(app, arc.id, d, ledger: ledger);
    expect(again.reviews[0].countedDays, 3);
    final after = await readAt(app, arc.id, d.addDays(1), ledger: ledger);
    expect(settledOf(after.reviews), after.h.records.totalXp);
    expect(after.reviews[0].countedDays, 3);
  });

  test('paused Arc: before the pause, inside it, and before and after the '
      'resume', () async {
    final mar1 = LocalDate(2027, 3, 1);
    LocalDate m(int d) => LocalDate(2027, 3, d);
    final arc = await lived(mar1, 5);
    await addFreeze(db, arc.id, m(6)); // Freeze on 5 Mar: from 6 Mar
    var ledger = await xpRows(db);
    final xp5 = xpOn(ledger, m(5));

    final before = await readAt(app, arc.id, m(5), ledger: ledger);
    expect(todayOf(before.reviews), xp5);
    final inside = await readAt(app, arc.id, m(8), ledger: ledger);
    expect(todayOf(inside.reviews), 0);
    expect(inside.reviews[0].status, ArcWeekStatus.paused);
    expect(inside.reviews[0].pausedSince, m(6));
    expect(inside.reviews[0].countedDays, 5);
    expect(settledOf(inside.reviews), inside.h.records.totalXp);
    final earlier = await readAt(app, arc.id, m(4), ledger: ledger);
    expect(earlier.ref.futureXp, xp5);

    // Resume on 10 Mar, and live Day 6 there.
    await resume(app, arc.id, m(6), m(10));
    at(app, m(10));
    await completeAll(app);
    ledger = await xpRows(db);
    final xp10 = xpOn(ledger, m(10));
    expect(xpOn(ledger, m(6)) + xpOn(ledger, m(8)), 0, reason: 'no XP paused');

    final resumed = await readAt(app, arc.id, m(10), ledger: ledger);
    expect(resumed.reviews[0].status, ArcWeekStatus.inProgress);
    expect(resumed.reviews[0].today!.dayNumber, 6);
    expect(todayOf(resumed.reviews), xp10);
    final insideAfter = await readAt(app, arc.id, m(8), ledger: ledger);
    expect(insideAfter.reviews[0].status, ArcWeekStatus.paused);
    expect(insideAfter.ref.futureXp, xp10);
    final next = await readAt(app, arc.id, m(11), ledger: ledger);
    expect(next.reviews[0].countedDays, 6);
    expect(todayOf(next.reviews), 0);
  });

  group('restored backups', () {
    Future<TestApp> restored(Uint8List bytes, DateTime clock) async {
      final target = TestApp(memoryDatabase(), FakeClock(clock));
      addTearDown(target.db.close);
      await target.backup.restore(await target.backup.inspect(bytes));
      return target;
    }

    /// Reviews of every arc in [target] on [date], identities checked,
    /// with nothing written.
    Future<Map<int, List<WeeklyReview>>> reviewEvery(
      TestApp target,
      LocalDate date,
    ) async {
      at(target, date);
      final before = await snapshotAll(target.db);
      final out = <int, List<WeeklyReview>>{};
      final sessions = await target.sessions.listSessions()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      for (final s in sessions) {
        if (s.status == WinterArcStatus.setup) continue;
        final h = await target.tracking.historyFor(s.id);
        checkIdentities(h);
        out[s.id] = allReviews(h);
      }
      expect(await snapshotAll(target.db), before);
      return out;
    }

    String fingerprint(List<WeeklyReview> reviews) => [
      for (final r in reviews)
        '${r.status.name}/${r.countedDays}/${r.completedHabitDays}/'
            '${r.habitOpportunities}/${r.fullDays}/${r.perfectDays}/'
            '${r.minimumDaysChosen}/${r.minimumDaysCompleted}/${r.xpEarned}/'
            '${r.today?.xp}',
    ].join(' ');

    test('genuine format-1 and format-2 fixtures', () async {
      final v1 = await restored(
        File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync(),
        DateTime(2026, 10, 3, 10),
      );
      final r1 = await reviewEvery(v1, LocalDate(2026, 10, 3));
      expect(r1, hasLength(2));
      final completed1 = r1.values.first;
      expect(
        completed1.every((r) => r.status == ArcWeekStatus.complete),
        isTrue,
      );
      expect(completed1.fold(0, (s, r) => s + r.countedDays), 92);
      final active1 = r1.values.last;
      expect(active1[0].status, ArcWeekStatus.inProgress);
      expect(active1[0].today!.dayNumber, 3);

      final v2 = await restored(
        File('test/fixtures/v1_1_backup_v2.nextrep').readAsBytesSync(),
        DateTime(2026, 10, 16, 18),
      );
      final r2 = await reviewEvery(v2, LocalDate(2026, 10, 16));
      expect(r2, hasLength(2));
      final seasonal = r2.values.last;
      expect(seasonal[2].status, ArcWeekStatus.inProgress); // Day 16, Week 3
      // Behind the export date: its newest rows are future-dated.
      await reviewEvery(v2, LocalDate(2026, 10, 10));
    });

    test('format 4 with an ended and a paused Arc, and the same data as a '
        'format-3 file: reviews identical to the source, also on a clock '
        'behind the export', () async {
      // Source: Arc 1 ended on its Day 3; Arc 2 lived 5 days, then paused.
      final first = await lived(wed, 3);
      await endArc(app, first.id, dOf(3));
      final start2 = LocalDate(2026, 10, 12);
      at(app, start2);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final second = await app.winterArc.startWinterArc();
      for (var d = 0; d < 5; d++) {
        at(app, start2.addDays(d));
        await completeAll(app);
      }
      await addFreeze(db, second.id, start2.addDays(5));
      at(app, start2.addDays(7));
      final exported = (await app.backup.export()).bytes;
      final json = utf8.decode(exported);
      expect(json, isNot(contains('review')), reason: 'nothing serialized');
      expect(json, isNot(contains('summary')));

      for (final date in [start2.addDays(7), start2.addDays(3), dOf(2)]) {
        final source = await reviewEvery(app, date);
        final target = await restored(exported, DateTime(2026, 10, 19, 9));
        final copy = await reviewEvery(target, date);
        expect(
          [for (final r in copy.values) fingerprint(r)],
          [for (final r in source.values) fingerprint(r)],
          reason: 'on $date',
        );
      }

      // Format 3 (the v1.2 writer): format 4 without its additions, for the
      // same data minus the ended / paused state (format 3 can't hold them).
      final plainDb = memoryDatabase();
      addTearDown(plainDb.close);
      app = TestApp(plainDb, FakeClock(DateTime(2026, 10, 7, 9)));
      await lived(wed, 4);
      at(app, dOf(6));
      final v3 = _asFormat3((await app.backup.export()).bytes);
      final target3 = await restored(v3, DateTime(2026, 10, 12, 9));
      for (final date in [dOf(6), dOf(3)]) {
        final source = await reviewEvery(app, date);
        final copy = await reviewEvery(target3, date);
        expect(
          [for (final r in copy.values) fingerprint(r)],
          [for (final r in source.values) fingerprint(r)],
        );
      }
    });
  });
}

/// What a v1.2 (format-3) writer produced for the same data: format 4
/// without `feedback`, `closedOn` and `freezes`, re-checksummed. (No
/// genuine format-3 file is committed; this is the convention of
/// `test/data/backup_v4_test.dart`.)
Uint8List _asFormat3(Uint8List v4) {
  final json = jsonDecode(utf8.decode(v4)) as Map<String, dynamic>;
  json['formatVersion'] = 3;
  final data = json['data'] as Map<String, dynamic>..remove('feedback');
  for (final arc in data['arcs'] as List) {
    (arc as Map<String, dynamic>)
      ..remove('closedOn')
      ..remove('freezes');
  }
  final body = {...json}..remove('checksum');
  json['checksum'] = {
    'algorithm': 'sha256',
    'value': BackupCodec.checksumOf(body),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}
