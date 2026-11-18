import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/arc_refresh.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/domain/journey/arc_weeks.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/review/weekly_review_controller.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';
import '../support/review_fakes.dart';

/// Phase 12B: the Weekly Review provider (spec §§ 9, 10; PHASE_12A § D7):
/// one session lookup and one `loadArc` per load, no write of any kind
/// (no close-out, no achievement sync), refresh on the Arc and day
/// signals, failure and retry, results bound to their Arc. Real Drift
/// repositories behind counting wrappers; all data synthetic.

void main() {
  late AppDatabase db;
  late TestApp app;
  late CountingProgressRepository progress;
  late CountingSessionRepository sessions;
  late ProviderContainer container;
  final wed = LocalDate(2026, 10, 7);

  setUp(() {
    db = memoryDatabase();
    app = TestApp(db, FakeClock(DateTime(2026, 10, 7, 9)));
    progress = CountingProgressRepository(
      DriftProgressRepository(db, app.clock),
    );
    sessions = CountingSessionRepository(DriftWinterArcRepository(db));
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(app.clock),
        progressRepositoryProvider.overrideWithValue(progress),
        winterArcRepositoryProvider.overrideWithValue(sessions),
      ],
      retry: (_, _) => null,
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<WinterArcSession> lived(int days, {LocalDate? start}) async {
    final first = start ?? wed;
    at(app, first);
    if (await app.sessions.latestSession() == null) {
      await app.winterArc.beginSetup();
    } else {
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    }
    final arc = await app.winterArc.startWinterArc();
    for (var d = 0; d < days; d++) {
      at(app, first.addDays(d));
      await completeAll(app);
    }
    return arc;
  }

  /// Loads the review source for [sessionId] and keeps it alive.
  Future<WeeklyReviewSource> load([int? sessionId]) {
    container.listen(weeklyReviewSourceProvider(sessionId), (_, _) {});
    return container.read(weeklyReviewSourceProvider(sessionId).future);
  }

  void reset() {
    progress
      ..loadArcCalls = 0
      ..loadedSessions.clear();
    sessions.reads = 0;
  }

  test('one snapshot per load: one loadArc, the session lookups and nothing '
      'else; every week computed from it reads nothing more', () async {
    final arc = await lived(10);
    reset();
    final before = await snapshotAll(db);

    final source = await load();
    expect(progress.loadArcCalls, 1);
    expect(progress.loadedSessions, [arc.id]);
    expect(sessions.reads, 2, reason: 'current + latest finished');
    for (final week in source.weeks.reviewableWeeks) {
      final review = source.review(week);
      expect(review.days, hasLength(7));
    }
    expect(progress.loadArcCalls, 1, reason: 'no per-week or per-day query');
    expect(progress.otherReads, 0);
    expect(progress.writes, 0);
    expect(sessions.writes, 0);
    expect(await snapshotAll(db), before);
  });

  test(
    'a historical Arc: one lookup by id and one loadArc, bound to it',
    () async {
      final first = await runFirstArc(app);
      final second = await lived(3, start: LocalDate(2026, 10, 2));
      reset();
      final source = await load(first.id);
      expect(source.history.session.id, first.id);
      expect(progress.loadedSessions, [first.id]);
      expect(sessions.reads, 1);
      final other = await load(second.id);
      expect(other.history.session.id, second.id);
      expect(progress.loadArcCalls, 2);
    },
  );

  test(
    'never closes out an Arc that is over, never syncs achievements',
    () async {
      final arc = await lived(2);
      at(app, WinterArcRules.endDateFor(wed).addDays(3)); // the Arc is over
      final before = await snapshotAll(db);
      reset();
      final source = await load();
      expect(source.weeks.defaultWeek, 13);
      expect(source.history.session.status, WinterArcStatus.active);
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.active,
      );
      expect(await snapshotAll(db), before, reason: 'no close-out, no unlocks');
      expect(progress.loadArcCalls, 1, reason: 'no second loadArc from a sync');
      expect(sessions.writes, 0);
    },
  );

  test('re-reads on the Arc refresh signal and on a day change', () async {
    await lived(3);
    reset();
    await load();
    expect(progress.loadArcCalls, 1);

    container.read(arcRefreshProvider.notifier).changed();
    await container.read(weeklyReviewSourceProvider(null).future);
    expect(progress.loadArcCalls, 2);

    at(app, wed.addDays(3));
    container.read(dayChangedProvider.notifier).changed();
    final next = await container.read(weeklyReviewSourceProvider(null).future);
    expect(progress.loadArcCalls, 3);
    expect(next.history.today, wed.addDays(3));
  });

  test(
    'a failed read surfaces as an error; retry recovers; nothing written',
    () async {
      await lived(3);
      final before = await snapshotAll(db);
      progress.failNextLoads = 1;
      container.listen(weeklyReviewSourceProvider(null), (_, _) {});
      await expectLater(
        container.read(weeklyReviewSourceProvider(null).future),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(container.read(weeklyReviewSourceProvider(null)).hasError, isTrue);
      container.invalidate(weeklyReviewSourceProvider(null));
      final source = await container.read(
        weeklyReviewSourceProvider(null).future,
      );
      expect(source.weeks.defaultWeek, 1);
      expect(await snapshotAll(db), before);
    },
  );

  test(
    'a superseded load never wins: the latest snapshot is the value',
    () async {
      await lived(3);
      container.listen(weeklyReviewSourceProvider(null), (_, _) {});
      final stale = container.read(weeklyReviewSourceProvider(null).future);
      at(app, wed.addDays(8));
      container.read(dayChangedProvider.notifier).changed();
      final fresh = await container.read(
        weeklyReviewSourceProvider(null).future,
      );
      await stale.catchError((Object _) => fresh);
      final value = container.read(weeklyReviewSourceProvider(null)).value!;
      expect(value.history.today, wed.addDays(8));
      expect(value.weeks.week(2).status, ArcWeekStatus.inProgress);
    },
  );
}
