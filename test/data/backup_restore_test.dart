import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

/// Arc 1 completed (see [runFirstArc]: revisions, a Minimum Day, XP,
/// unlocks, a reflection) and Arc 2 running since 2 Oct with progress, a
/// reflection and both reminders on (07:15 and 22:30). The clock is on
/// 2 Oct 2026 at 21:00.
Future<TestApp> _source() async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 7, 1)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  await runFirstArc(app);
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  app.clock.current = DateTime(2026, 10, 2, 20);
  final arc2 = await app.winterArc.startWinterArc();
  await completeHabit(app, 'water');
  await app.reflections.save(
    sessionId: arc2.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.okay, win: 'Back on the trail'),
  );
  await app.achievements.reconcile();
  await app.reminders.update(
    (_) => const ReminderPreferences(
      dailyEnabled: true,
      dailyTime: ReminderTime(7, 15),
      reflectionEnabled: true,
      reflectionTime: ReminderTime(22, 30),
    ),
  );
  app.clock.current = DateTime(2026, 10, 2, 21);
  return app;
}

/// An empty app on the same day, with its own scheduler.
TestApp _empty(FakeClock clock) {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(clock.now()),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  return app;
}

Future<void> _restoreInto(TestApp target, Uint8List bytes) async =>
    target.backup.restore(await target.backup.inspect(bytes));

Map<String, dynamic> _dataOf(Uint8List bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['data']
        as Map<String, dynamic>;

void main() {
  group('round trip', () {
    late TestApp source;
    late TestApp target;
    late Map<String, List<String>> before;
    late Map<String, List<String>> after;

    setUp(() async {
      source = await _source();
      final bytes = (await source.backup.export()).bytes;
      target = _empty(source.clock);
      await _restoreInto(target, bytes);
      before = await dumpOf(source.db);
      after = await dumpOf(target.db);
    });

    void expectSame(String table) {
      expect(before[table], isNotEmpty, reason: 'fixture covers $table');
      expect(after[table], before[table], reason: table);
    }

    test('a completed arc round-trips', () async {
      final arc1 = await target.sessions.sessionById(1);
      expect(arc1?.status, WinterArcStatus.completed);
      expect(
        await snapshotOf(target.db, 1),
        hasLength((await snapshotOf(source.db, 1)).length),
      );
      final summary = await target.history.card(1);
      final original = await source.history.card(1);
      expect(summary.summary.totalXp, original.summary.totalXp);
      expect(summary.summary.perfectDays, original.summary.perfectDays);
      expect(summary.reflectionCount, 1);
    });

    test('an active arc round-trips and keeps tracking', () async {
      final arc2 = await target.sessions.currentSession();
      expect(arc2?.id, 2);
      expect(arc2?.status, WinterArcStatus.active);
      final today = await target.tracking.today();
      expect(today.session.id, 2);
      expect(
        today.entries
            .firstWhere((e) => e.habit.id == 'water')
            .progress
            .completed,
        isTrue,
      );
      await target.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: target.clock.today(),
        sessionId: 2,
      );
      expect((await target.tracking.today()).totalXp, greaterThan(15));
    });

    test('multiple arcs round-trip', () => expectSame('sessions'));
    test('habits round-trip', () => expectSame('habits'));
    test('habit revisions round-trip', () => expectSame('revisions'));
    test('Minimum Days round-trip', () => expectSame('modes'));
    test('progress round-trips', () => expectSame('progress'));
    test('the XP ledger round-trips', () => expectSame('xp'));
    test('achievements round-trip', () => expectSame('achievements'));
    test('reflections round-trip', () => expectSame('reflections'));

    test('reminder times round-trip but both reminders restore off', () async {
      final prefs = await target.reminderStore.load();
      expect(prefs.dailyTime, const ReminderTime(7, 15));
      expect(prefs.reflectionTime, const ReminderTime(22, 30));
      expect(prefs.dailyEnabled, isFalse);
      expect(prefs.reflectionEnabled, isFalse);
      expect(
        await target.reminders.reconcile(),
        isEmpty,
        reason: 'nothing gets scheduled after a restore',
      );
    });

    test('restored session ids and references stay coherent', () async {
      expect(after, {
        ...before,
        'reminders': after['reminders'], // off by design, compared above
      });
      // Every per-arc read still finds its own data.
      expect((await target.reflections.journalFor(1)).count, 1);
      expect((await target.reflections.journalFor(2)).count, 1);
      expect(
        (await target.achievements.boardFor(1)).unlockedCount,
        (await source.achievements.boardFor(1)).unlockedCount,
      );
      expect((await target.tracking.journeyFor(1)).days, hasLength(92));
      // A new arc after the restored ones gets a fresh id.
      target.clock.current = DateTime(2027, 1, 2, 9); // after Arc 2
      await target.lifecycle.reconcile();
      final arc3 = await target.winterArc.startNewArc(NewArcBaseline.fresh);
      expect(arc3.id, greaterThan(2));
    });

    test('the restored ArcResolution is right', () async {
      final resolution = await CurrentArcService(target.sessions).resolve();
      expect(resolution.active?.id, 2);
      expect(resolution.latestCompleted?.id, 1);
      expect(AppRoutes.home(resolution), AppRoutes.today);
    });

    test('exporting again after the restore gives the same data', () async {
      final first = (await source.backup.export()).bytes;
      final second = (await target.backup.export()).bytes;
      expect(
        BackupCodec.canonicalJson(_dataOf(second)),
        BackupCodec.canonicalJson(_dataOf(first)),
      );
      expect(second, first, reason: 'same clock: byte-identical');
    });
  });

  test('an empty app exports and restores an empty backup', () async {
    final app = _empty(FakeClock(DateTime(2026, 10, 4, 9)));
    final export = await app.backup.export();
    expect(export.summary.isEmpty, isTrue);
    expect(export.fileName, 'nextrep-backup-2026-10-04.nextrep');
    await _restoreInto(app, export.bytes);
    expect((await CurrentArcService(app.sessions).resolve()).isEmpty, isTrue);
  });

  test('restore into an empty app, then the app routes home', () async {
    final source = await _source();
    final target = _empty(source.clock);
    final bytes = (await source.backup.export()).bytes;
    expect(
      AppRoutes.home(await CurrentArcService(target.sessions).resolve()),
      AppRoutes.onboarding,
    );
    await _restoreInto(target, bytes);
    expect(
      AppRoutes.home(await CurrentArcService(target.sessions).resolve()),
      AppRoutes.today,
    );
  });

  test(
    'a completed-only backup boots to the latest completed summary',
    () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await runFirstArc(app);
      final bytes = (await app.backup.export()).bytes;
      final target = _empty(app.clock);
      await _restoreInto(target, bytes);
      expect(
        AppRoutes.home(await CurrentArcService(target.sessions).resolve()),
        AppRoutes.arc(1),
      );
    },
  );

  test(
    'existing data is replaced only by restore, never by inspecting',
    () async {
      final source = await _source();
      final bytes = (await source.backup.export()).bytes;

      // The target has its own, different arc.
      final target = _empty(source.clock);
      await target.winterArc.beginSetup();
      await target.winterArc.startWinterArc();
      await completeAll(target);
      final original = await dumpOf(target.db);

      final backup = await target.backup.inspect(bytes);
      expect(backup.summary.arcCount, 2);
      expect(await dumpOf(target.db), original, reason: 'inspect only reads');
      expect((await target.backup.current()).arcCount, 1);

      await target.backup.restore(backup);
      final restored = await dumpOf(target.db, renumberSessions: true);
      final expected = await dumpOf(source.db, renumberSessions: true);
      for (final table in expected.keys.where((t) => t != 'reminders')) {
        expect(restored[table], expected[table], reason: table);
      }
    },
  );

  test('restored arcs never reuse an id this device has used, so stale '
      'writes for the old arcs find nothing', () async {
    final source = await _source(); // arcs 1 and 2
    final bytes = (await source.backup.export()).bytes;
    final target = await _source(); // its own arcs 1 and 2
    final staleToday = await target.tracking.today(); // arc 2, on screen

    await _restoreInto(target, bytes);
    final ids = [for (final s in await target.sessions.listSessions()) s.id];
    expect(ids, [4, 3], reason: 'shifted past ids 1 and 2, order kept');
    expect(await target.sessions.sessionById(2), isNull);

    // Writes still aimed at the old arc 2 are rejected, never applied to
    // the restored data.
    final before = await dumpOf(target.db);
    await expectLater(
      target.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: staleToday.date,
        sessionId: staleToday.session.id,
      ),
      throwsA(isA<DomainFailure>()),
    );
    await expectLater(
      target.sessions.updateSession(
        staleToday.session.copyWith(status: WinterArcStatus.completed),
      ),
      throwsA(isA<PersistenceFailure>()),
    );
    expect(await dumpOf(target.db), before);
  });

  test('a backup that fails validation changes nothing', () async {
    final source = await _source();
    final bytes = Uint8List.fromList((await source.backup.export()).bytes);
    final target = await _source();
    final original = await dumpOf(target.db);
    bytes[bytes.length - 10] ^= 0x20; // damage
    await expectLater(
      target.backup.inspect(bytes),
      throwsA(isA<BackupFailure>()),
    );
    expect(await dumpOf(target.db), original);
    expect(target.scheduler.pending, isNotEmpty, reason: 'reminders kept');
  });

  test('a failed database insert rolls back everything; the original data '
      'survives', () async {
    final source = await _source();
    final backup = await source.backup.inspect(
      (await source.backup.export()).bytes,
    );

    final target = await _source();
    // Make the target different from the backup, so a partial restore
    // would show.
    target.clock.current = DateTime(2026, 10, 3, 9);
    await completeAll(target);
    final original = await dumpOf(target.db);
    final scheduled = target.scheduler.cancelCalls;

    // The last table written by a restore refuses inserts.
    await target.db.customStatement(
      'CREATE TEMP TRIGGER fail_restore BEFORE INSERT ON daily_reflections '
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    Object? error;
    try {
      await target.backup.restore(backup);
    } catch (e) {
      error = e;
    }
    expect(error, isA<PersistenceFailure>());
    // Private text never reaches the failure (SQLite quotes bound values).
    expect(error.toString(), isNot(contains('Back on the trail')));
    expect(error.toString(), isNot(contains('Showed up')));

    await target.db.customStatement('DROP TRIGGER fail_restore');
    expect(await dumpOf(target.db), original, reason: 'rolled back');
    expect(target.scheduler.cancelCalls, scheduled, reason: 'not restored');
    expect((await target.tracking.today()).completion.isFull, isTrue);
  });

  test('restore cancels pending reminders and leaves both off', () async {
    final source = await _source();
    final bytes = (await source.backup.export()).bytes;
    final target = await _source(); // reminders on and scheduled
    expect(target.scheduler.pending, isNotEmpty);
    final cancels = target.scheduler.cancelCalls;

    final outcome = await target.backup.restore(
      await target.backup.inspect(bytes),
    );
    expect(outcome.remindersCleared, isTrue);
    expect(target.scheduler.cancelCalls, cancels + 1);
    expect(target.scheduler.pending, isEmpty);
    final prefs = await target.reminderStore.load();
    expect(prefs.anyEnabled, isFalse);
  });

  test('a backup without saved reminder times restores the defaults', () async {
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
    addTearDown(app.db.close);
    await runFirstArc(app);
    final bytes = (await app.backup.export()).bytes;
    expect(_dataOf(bytes)['reminders'], isNull);
    final target = await _source();
    await _restoreInto(target, bytes);
    expect(await target.reminderStore.load(), ReminderPreferences.defaults);
  });
}
