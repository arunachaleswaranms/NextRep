import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_arc_activity_repository.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/arc_clock_guard.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

/// Every row of every table, for "nothing was written" checks.
Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          row.data,
      ],
  };
}

Future<void> _addFreeze(
  AppDatabase db,
  int sessionId,
  LocalDate from, {
  LocalDate? resumedOn,
}) => db
    .into(db.arcFreezes)
    .insert(
      ArcFreezesCompanion.insert(
        sessionId: sessionId,
        frozenFrom: from,
        resumedOn: Value(resumedOn),
        requestedAt: DateTime(2026, 1, 1),
        resumedAt: Value(resumedOn == null ? null : DateTime(2026, 1, 2)),
      ),
    );

Future<void> _setEnd(AppDatabase db, int sessionId, LocalDate end) =>
    (db.update(db.winterArcSessions)..where((s) => s.id.equals(sessionId)))
        .write(WinterArcSessionsCompanion(endDate: Value(end)));

void main() {
  late AppDatabase db;
  late TestApp app;
  // Day 1 of the arcs below.
  final start = LocalDate(2027, 3, 1);

  setUp(() {
    db = memoryDatabase();
    app = TestApp(db, FakeClock(DateTime(2027, 3, 1, 9)));
  });
  tearDown(() => db.close());

  Future<WinterArcSession> started() async {
    await app.winterArc.beginSetup();
    return app.winterArc.startWinterArc();
  }

  group('sessions carry their freezes and closing date', () {
    test('a v1.2-style arc has no freeze and no closing date', () async {
      final arc = await started();
      final loaded = (await app.sessions.sessionById(arc.id))!;
      expect(loaded.freezes, isEmpty);
      expect(loaded.closedOn, isNull);
      expect(loaded.endDate, WinterArcRules.endDateFor(start));
    });

    test('freezes are loaded oldest first by every lookup', () async {
      final arc = await started();
      await _addFreeze(db, arc.id, LocalDate(2027, 3, 20));
      await _addFreeze(
        db,
        arc.id,
        LocalDate(2027, 3, 5),
        resumedOn: LocalDate(2027, 3, 8),
      );
      await _setEnd(db, arc.id, WinterArcRules.endDateFor(start).addDays(3));
      for (final session in [
        await app.sessions.sessionById(arc.id),
        await app.sessions.currentSession(),
        await app.sessions.latestSession(),
        (await app.sessions.listSessions()).single,
      ]) {
        expect(session!.freezes.map((f) => f.frozenFrom), [
          LocalDate(2027, 3, 5),
          LocalDate(2027, 3, 20),
        ]);
        expect(session.freezes.first.resumedOn, LocalDate(2027, 3, 8));
        expect(session.freezes.last.isOpen, isTrue);
        expect(WinterArcRules.problemWith(session), isNull);
      }
    });

    test(
      'updateSession stores the closing date; ended arcs are history',
      () async {
        final arc = await started();
        app.clock.current = DateTime(2027, 3, 5, 9);
        final ended = arc.copyWith(
          status: WinterArcStatus.ended,
          closedOn: LocalDate(2027, 3, 4),
        );
        expect(WinterArcRules.problemWith(ended), isNull);
        // Repository primitive only: no service ends an arc in Phase 12E1.
        await app.sessions.updateSession(ended);
        final loaded = (await app.sessions.sessionById(arc.id))!;
        expect(loaded.status, WinterArcStatus.ended);
        expect(loaded.closedOn, LocalDate(2027, 3, 4));
        expect(await app.sessions.currentSession(), isNull);
        expect((await app.sessions.latestCompletedSession())?.id, arc.id);
        // An ended arc is outside single_open_session: a new arc can start.
        await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
        expect(
          (await app.sessions.currentSession())?.status,
          WinterArcStatus.setup,
        );
        await expectLater(
          db.customStatement(
            "INSERT INTO winter_arc_sessions (start_date, end_date, status, "
            "created_at) VALUES ('2027-03-05', '2027-06-04', 'active', 0)",
          ),
          throwsA(anything),
          reason: 'still at most one unfinished arc',
        );
      },
    );

    test('deleting an arc removes its freezes and leaves no orphan', () async {
      final arc = await started();
      await _addFreeze(
        db,
        arc.id,
        LocalDate(2027, 3, 5),
        resumedOn: LocalDate(2027, 3, 8),
      );
      await _setEnd(db, arc.id, WinterArcRules.endDateFor(start).addDays(3));
      app.clock.current = DateTime(2027, 6, 10, 9);
      await app.lifecycle.reconcile();
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.completed,
      );
      await app.winterArc.deleteCompletedArc(arc.id);
      expect(await db.select(db.arcFreezes).get(), isEmpty);
    });

    test('the unique open-freeze index and interval check hold', () async {
      final arc = await started();
      await _addFreeze(db, arc.id, LocalDate(2027, 3, 5));
      await expectLater(
        _addFreeze(db, arc.id, LocalDate(2027, 3, 9)),
        throwsA(anything),
        reason: 'one open freeze per arc',
      );
      await expectLater(
        _addFreeze(
          db,
          arc.id,
          LocalDate(2027, 3, 2),
          resumedOn: LocalDate(2027, 3, 2),
        ),
        throwsA(anything),
        reason: 'resumed_on > frozen_from',
      );
      await expectLater(
        _addFreeze(db, 999, LocalDate(2027, 3, 2), resumedOn: start.addDays(9)),
        throwsA(anything),
        reason: 'a freeze belongs to an arc',
      );
    });
  });

  group('lifecycle close-out', () {
    test('a paused arc is never completed, however late', () async {
      final arc = await started();
      await _addFreeze(db, arc.id, LocalDate(2027, 3, 11));
      for (final now in [
        DateTime(2027, 6, 1, 9),
        DateTime(2027, 6, 2, 9),
        DateTime(2029, 1, 1, 9),
      ]) {
        app.clock.current = now;
        final reconciled = await app.lifecycle.reconcile();
        expect(reconciled?.status, WinterArcStatus.active, reason: '$now');
      }
    });

    test('a resumed arc completes the day after its new Day 92', () async {
      final arc = await started();
      await _addFreeze(
        db,
        arc.id,
        LocalDate(2027, 3, 11),
        resumedOn: LocalDate(2027, 3, 20),
      );
      await _setEnd(db, arc.id, LocalDate(2027, 6, 9));
      app.clock.current = DateTime(2027, 6, 9, 23);
      expect((await app.lifecycle.reconcile())?.status, WinterArcStatus.active);
      app.clock.current = DateTime(2027, 6, 10, 0, 1);
      expect(
        (await app.lifecycle.reconcile())?.status,
        WinterArcStatus.completed,
      );
    });

    test('an ended arc is left untouched and earns no Summit', () async {
      final arc = await started();
      await completeAll(app);
      // Its unlocks are stored while it is active; once ended, it is
      // read-only history (review finding R2).
      await app.achievements.sync();
      await app.sessions.updateSession(
        arc.copyWith(status: WinterArcStatus.ended, closedOn: start),
      );
      app.clock.current = DateTime(2027, 9, 1, 9);
      final before = await _snapshot(db);
      final home = await app.lifecycle.reconcile();
      expect(home?.status, WinterArcStatus.ended);
      expect(await _snapshot(db), before, reason: 'no write');
      final backfill = await app.achievements.backfillCatalog();
      expect(backfill.historical, isEmpty);
      expect(backfill.celebratable.isEmpty, isTrue);
      expect(await _snapshot(db), before, reason: 'no unlock written');
      final keys = {
        for (final u in await app.achievementStore.unlocks(arc.id)) u.key,
      };
      expect(keys, isNot(contains(AchievementKey.summit)));
      expect(keys, contains(AchievementKey.firstRep));
    });
  });

  group('writes on a paused date are refused (no XP, no progress)', () {
    test('tracking, Minimum Day, edits and reflections', () async {
      final arc = await started();
      await completeAll(app); // Day 1
      app.clock.current = DateTime(2027, 3, 2, 9); // Day 2
      await _addFreeze(db, arc.id, LocalDate(2027, 3, 3)); // from tomorrow
      app.clock.current = DateTime(2027, 3, 4, 9); // paused
      final before = await _snapshot(db);
      final today = await app.tracking.today();
      expect(today.isTrackable, isFalse);
      expect(today.position, isA<ArcPaused>());
      final water = today.entries.firstWhere((e) => e.habit.id == 'water');
      Future<void> refused(Future<Object?> Function() write) => expectLater(
        write(),
        throwsA(
          isA<DomainFailure>().having(
            (f) => f.rule,
            'rule',
            DomainRule.arcNotRunningToday,
          ),
        ),
      );
      await refused(
        () => app.tracking.perform(
          habitId: water.habit.id,
          action: HabitAction.increment,
          date: today.date,
        ),
      );
      await refused(() => app.tracking.activateMinimumDay(date: today.date));
      await refused(
        () => app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 9),
          date: today.date,
        ),
      );
      await expectLater(
        app.reflections.save(
          sessionId: arc.id,
          date: today.date,
          draft: const ReflectionDraft(win: 'synthetic'),
        ),
        throwsA(isA<DomainFailure>()),
      );
      expect((await app.tracking.habitSettings()).editable, isFalse);
      expect(await _snapshot(db), before, reason: 'nothing written');
    });

    test('an edit on the day before a scheduled pause is dated its first '
        'paused date (addendum AD6, F1-1)', () async {
      final arc = await started();
      app.clock.current = DateTime(2027, 3, 10, 9); // Day 10
      await _addFreeze(db, arc.id, LocalDate(2027, 3, 11));
      final outcome = await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 10),
        date: app.clock.today(),
      );
      expect(outcome.value.configFrom, LocalDate(2027, 3, 11));
      final revision = (await db.select(db.habitRevisions).get()).single;
      expect(revision.effectiveFrom, LocalDate(2027, 3, 11));
    });
  });

  group('last activity date and the clock guard service', () {
    late DriftArcActivityRepository activity;
    late ArcClockGuardService guard;

    setUp(() {
      activity = DriftArcActivityRepository(db);
      guard = ArcClockGuardService(activity: activity, clock: app.clock);
    });

    test('a pending revision for tomorrow is not activity', () async {
      final arc = await started();
      expect(await activity.lastActivityDate(arc.id), isNull);
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 10),
        date: app.clock.today(),
      );
      expect(
        (await db.select(db.habitRevisions).get()).single.effectiveFrom,
        start.addDays(1),
      );
      expect(await activity.lastActivityDate(arc.id), isNull);
      final session = (await app.sessions.sessionById(arc.id))!;
      expect((await guard.evaluate(session)).isSafe, isTrue);
    });

    test('activity dated after today (clock moved back) refuses', () async {
      final arc = await started();
      app.clock.current = DateTime(2027, 3, 2, 9);
      await completeHabit(app, 'water');
      expect(await activity.lastActivityDate(arc.id), LocalDate(2027, 3, 2));
      app.clock.current = DateTime(2027, 3, 1, 22); // back a day
      final session = (await app.sessions.sessionById(arc.id))!;
      final before = await _snapshot(db);
      final verdict = await guard.evaluate(session);
      expect(verdict, isA<ClockGuardBehind>());
      expect((verdict as ClockGuardBehind).bound, ClockGuardBound.lastActivity);
      expect(verdict.earliestSafe, LocalDate(2027, 3, 2));
      expect(await _snapshot(db), before, reason: 'evaluating writes nothing');
      app.clock.current = DateTime(2027, 3, 2, 9);
      expect((await guard.evaluate(session)).isSafe, isTrue);
    });

    test('every activity table counts; nothing else does', () async {
      final arc = await started();
      final id = arc.id;
      Future<void> raw(String sql) => db.customStatement(sql);
      await raw(
        "INSERT INTO habit_revisions (session_id, habit_id, effective_from, "
        "target, minimum_target, enabled, created_at) "
        "VALUES ($id, 'water', '2027-04-30', 9, 3, 1, 0)",
      );
      expect(await activity.lastActivityDate(id), isNull);
      for (final (sql, date) in [
        (
          "INSERT INTO day_modes VALUES ($id, '2027-03-03', 'minimum', 0)",
          '2027-03-03',
        ),
        (
          "INSERT INTO daily_reflections (session_id, date, mood, win, "
              "improvement, created_at, updated_at) "
              "VALUES ($id, '2027-03-04', 'good', NULL, NULL, 0, 0)",
          '2027-03-04',
        ),
        (
          "INSERT INTO achievement_unlocks VALUES ($id, 'first_rep', "
              "'2027-03-05', 0)",
          '2027-03-05',
        ),
        (
          "INSERT INTO xp_transactions (session_id, source_key, reason, "
              "amount, habit_id, date, created_at) VALUES ($id, "
              "'perfect_day:2027-03-06', 'perfectDay', 30, NULL, "
              "'2027-03-06', 0)",
          '2027-03-06',
        ),
        (
          "INSERT INTO daily_habit_progress_entries (session_id, habit_id, "
              "date, current_value, completed, completed_at, updated_at) "
              "VALUES ($id, 'water', '2027-03-07', 1, 0, NULL, 0)",
          '2027-03-07',
        ),
      ]) {
        await raw(sql);
        expect(await activity.lastActivityDate(id), LocalDate.parse(date));
      }
      // Another arc's activity never counts.
      expect(await activity.lastActivityDate(id + 1), isNull);
    });
  });

  group('feedback preferences storage', () {
    test('reading gives the defaults and writes nothing', () async {
      final repo = DriftFeedbackPreferencesRepository(db);
      expect(await repo.load(), FeedbackPreferences.defaults);
      expect(FeedbackPreferences.defaults.soundsEnabled, isTrue);
      expect(FeedbackPreferences.defaults.soundTheme, SoundTheme.iceCrystal);
      expect(await db.select(db.feedbackPrefs).get(), isEmpty);
    });

    test('a saved setting reads back; only known themes, one row', () async {
      final repo = DriftFeedbackPreferencesRepository(db);
      const quiet = FeedbackPreferences(
        soundsEnabled: false,
        soundTheme: SoundTheme.warmEmber,
      );
      await repo.save(quiet, at: DateTime(2027, 3, 1));
      expect(await repo.load(), quiet);
      await repo.save(
        const FeedbackPreferences(
          soundsEnabled: true,
          soundTheme: SoundTheme.summitSpark,
        ),
        at: DateTime(2027, 3, 2),
      );
      expect((await db.select(db.feedbackPrefs).get()), hasLength(1));
      for (final sql in [
        "INSERT OR REPLACE INTO feedback_preferences VALUES (1, 1, 'IceCrystal', 0)",
        "INSERT OR REPLACE INTO feedback_preferences VALUES (1, 1, 'loud', 0)",
        "INSERT INTO feedback_preferences VALUES (2, 1, 'iceCrystal', 0)",
        "INSERT OR REPLACE INTO feedback_preferences VALUES (1, 2, 'iceCrystal', 0)",
      ]) {
        await expectLater(
          db.customStatement(sql),
          throwsA(anything),
          reason: sql,
        );
      }
      expect(SoundTheme.fromName('summitSpark'), SoundTheme.summitSpark);
      expect(SoundTheme.fromName('SummitSpark'), isNull);
    });
  });
}
