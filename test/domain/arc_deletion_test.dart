import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

Matcher _rejected(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Rows each table holds for [sessionId].
Future<Map<String, int>> _rowCounts(AppDatabase db, int sessionId) async => {
  for (final table in [
    'habits',
    'habit_revisions',
    'daily_habit_progress_entries',
    'day_modes',
    'xp_transactions',
    'achievement_unlocks',
    'daily_reflections',
  ])
    table:
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS c FROM $table WHERE session_id = $sessionId',
                )
                .getSingle())
            .read<int>('c'),
};

Future<ArcResolution> _resolve(TestApp app) =>
    CurrentArcService(app.sessions).resolve();

/// Arc 1 completed on 30 Sep 2026 and Arc 2 completed on 31 Dec 2026, each
/// with history; reminder times saved. The clock is on 1 Jan 2027.
Future<TestApp> _twoCompletedArcs() async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 7, 1)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  await runFirstArc(app); // clock: 1 Oct 2026
  await app.reminders.update(
    (p) => p.copyWith(dailyEnabled: true, dailyTime: const ReminderTime(6, 0)),
  );
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  final arc2 = await app.winterArc.startWinterArc(); // Day 1 = 1 Oct
  await completeAll(app);
  await app.reflections.save(
    sessionId: arc2.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.good),
  );
  await app.achievements.reconcile();
  app.clock.current = DateTime(2027, 1, 1, 9); // Day 93 of Arc 2
  await app.lifecycle.reconcile();
  await app.achievements.reconcile();
  return app;
}

void main() {
  group('deleting a completed arc', () {
    test('removes the arc', () async {
      final app = await _twoCompletedArcs();
      await app.winterArc.deleteCompletedArc(1);
      expect(await app.sessions.sessionById(1), isNull);
      expect([for (final s in await app.sessions.listSessions()) s.id], [2]);
    });

    test('cascades to every row it owns: habits, revisions, progress, XP, '
        'day modes, achievements and reflections', () async {
      final app = await _twoCompletedArcs();
      final before = await _rowCounts(app.db, 1);
      for (final MapEntry(key: table, value: count) in before.entries) {
        expect(count, greaterThan(0), reason: 'fixture has $table rows');
      }
      await app.winterArc.deleteCompletedArc(1);
      expect(await _rowCounts(app.db, 1), {
        for (final table in before.keys) table: 0,
      });
    });

    test('keeps the reminder preferences (they belong to the app)', () async {
      final app = await _twoCompletedArcs();
      final prefs = await app.reminderStore.load();
      await app.winterArc.deleteCompletedArc(1);
      await app.winterArc.deleteCompletedArc(2);
      expect(await app.reminderStore.load(), prefs);
      expect(prefs.dailyTime, const ReminderTime(6, 0));
    });

    test('leaves every other arc exactly as it was', () async {
      final app = await _twoCompletedArcs();
      final arc2 = await snapshotOf(app.db, 2);
      await app.winterArc.deleteCompletedArc(1);
      expect(await snapshotOf(app.db, 2), arc2);
    });

    test(
      'deleting the latest completed arc falls back to the next latest',
      () async {
        final app = await _twoCompletedArcs();
        expect((await _resolve(app)).latestCompleted?.id, 2);
        await app.winterArc.deleteCompletedArc(2);
        final resolution = await _resolve(app);
        expect(resolution.latestCompleted?.id, 1);
        expect(AppRoutes.home(resolution), AppRoutes.arc(1));
      },
    );

    test('deleting the last arc returns to onboarding', () async {
      final app = await _twoCompletedArcs();
      await app.winterArc.deleteCompletedArc(2);
      await app.winterArc.deleteCompletedArc(1);
      final resolution = await _resolve(app);
      expect(resolution.isEmpty, isTrue);
      expect(AppRoutes.home(resolution), AppRoutes.onboarding);
    });

    test('an active arc is rejected, with nothing deleted', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.fresh);
      final active = await app.winterArc.startWinterArc();
      await completeAll(app);
      final before = await dumpOf(app.db);

      expect(
        () => app.winterArc.deleteCompletedArc(active.id),
        _rejected(DomainRule.arcNotDeletable),
      );
      // The repository checks too, inside its transaction.
      await expectLater(
        app.sessions.deleteSession(
          active.id,
          expected: WinterArcStatus.completed,
        ),
        _rejected(DomainRule.arcNotDeletable),
      );
      expect(await dumpOf(app.db), before);
    });

    test('an arc in setup is rejected by the completed-arc delete', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      final setup = await app.winterArc.beginSetup();
      await expectLater(
        app.winterArc.deleteCompletedArc(setup.id),
        _rejected(DomainRule.arcNotDeletable),
      );
      expect((await app.sessions.currentSession())?.id, setup.id);
    });

    test('an unknown arc is rejected', () async {
      final app = await _twoCompletedArcs();
      await expectLater(
        app.winterArc.deleteCompletedArc(99),
        _rejected(DomainRule.sessionNotFound),
      );
    });
  });

  group('cancelling a setup', () {
    test('deletes the setup arc and its provisional habits', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await runFirstArc(app);
      final setup = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      await app.winterArc.setHabitEnabled('english', enabled: true);
      expect((await _rowCounts(app.db, setup.id))['habits'], greaterThan(0));

      await app.winterArc.cancelSetup();
      expect(await app.sessions.sessionById(setup.id), isNull);
      expect((await _rowCounts(app.db, setup.id))['habits'], 0);
    });

    test('leaves the previous completed arc byte-for-byte unchanged and '
        'returns to its summary', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      final arc1 = await runFirstArc(app);
      final before = await snapshotOf(app.db, arc1.id);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);

      await app.winterArc.cancelSetup();
      expect(await snapshotOf(app.db, arc1.id), before);
      final resolution = await _resolve(app);
      expect(resolution.current, isNull);
      expect(AppRoutes.home(resolution), AppRoutes.arc(arc1.id));
    });

    test('a first-ever setup returns to onboarding', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await app.winterArc.beginSetup();
      await app.winterArc.cancelSetup();
      final resolution = await _resolve(app);
      expect(resolution.isEmpty, isTrue);
      expect(AppRoutes.home(resolution), AppRoutes.onboarding);
      // And a new start works as on a first install.
      final again = await app.winterArc.beginSetup();
      expect(again.status, WinterArcStatus.setup);
    });

    test('an active arc cannot be cancelled', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await app.winterArc.beginSetup();
      final active = await app.winterArc.startWinterArc();
      await expectLater(
        app.winterArc.cancelSetup(),
        _rejected(DomainRule.sessionNotInSetup),
      );
      await expectLater(
        app.sessions.deleteSession(active.id, expected: WinterArcStatus.setup),
        _rejected(DomainRule.sessionNotInSetup),
      );
      expect((await app.sessions.currentSession())?.id, active.id);
    });

    test('a completed arc cannot be cancelled', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      final arc1 = await runFirstArc(app);
      final before = await snapshotOf(app.db, arc1.id);
      await expectLater(
        app.winterArc.cancelSetup(),
        _rejected(DomainRule.noSession),
      );
      await expectLater(
        app.sessions.deleteSession(arc1.id, expected: WinterArcStatus.setup),
        _rejected(DomainRule.sessionNotInSetup),
      );
      expect(await snapshotOf(app.db, arc1.id), before);
    });
  });
}
