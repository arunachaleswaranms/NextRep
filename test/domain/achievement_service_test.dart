import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_achievement_repository.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_repository.dart';
import 'package:nextrep/domain/achievement/achievement_service.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';

import '../support/fakes.dart';

/// Real services over a real SQLite database. Default habits: workout
/// (30 min), water (8), learning (20 min), no_junk_food (binary).
void main() {
  late TestApp app;
  final day1 = LocalDate(2026, 10, 1);

  Future<void> act(String habitId, HabitAction action, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await app.tracking.perform(
        habitId: habitId,
        action: action,
        date: app.clock.today(),
      );
    }
  }

  Future<void> completeAll() async {
    await act('workout', HabitAction.increment, times: 6);
    await act('water', HabitAction.increment, times: 8);
    await act('learning', HabitAction.increment, times: 4);
    await act('no_junk_food', HabitAction.complete);
  }

  Future<List<AchievementUnlockRow>> rows() =>
      app.db.select(app.db.achievementUnlocks).get();

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 7)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  test('nothing is unlocked before an arc starts or before progress', () async {
    final fresh = TestApp(memoryDatabase(), app.clock);
    addTearDown(fresh.db.close);
    expect(await fresh.achievements.reconcile(), isEmpty);
    expect(await fresh.achievements.board(), isNull);
    await fresh.winterArc.beginSetup();
    expect(await fresh.achievements.reconcile(), isEmpty);

    expect(await app.achievements.reconcile(), isEmpty);
    final board = (await app.achievements.board())!;
    expect(board.total, 10);
    expect(board.unlockedCount, 0);
  });

  test('a newly earned achievement is persisted exactly once', () async {
    await act('no_junk_food', HabitAction.complete);
    app.clock.advance(const Duration(hours: 2));

    final first = await app.achievements.reconcile();
    expect(first.map((u) => u.key), [AchievementKey.firstRep]);
    expect(first.single.unlockedOn, day1);
    expect(first.single.unlockedAt, DateTime(2026, 10, 1, 9));

    // Reconciling again, or undoing the habit, never unlocks it twice and
    // never takes it away.
    expect(await app.achievements.reconcile(), isEmpty);
    await act('no_junk_food', HabitAction.undoCompletion);
    expect(await app.achievements.reconcile(), isEmpty);
    final stored = await rows();
    expect(stored, hasLength(1));
    expect(stored.single.achievementKey, 'first_rep');
    expect(stored.single.unlockedAt, DateTime(2026, 10, 1, 9));
  });

  test('multiple achievements unlock together, in catalog order', () async {
    await completeAll();
    final unlocked = await app.achievements.reconcile();
    expect(unlocked.map((u) => u.key), [
      AchievementKey.firstRep,
      AchievementKey.firstPerfect,
    ]);
    final board = (await app.achievements.board())!;
    expect(board.unlockedCount, 2);
    expect(
      board.entries.where((e) => e.unlocked).map((e) => e.definition.title),
      ['First Rep', 'Clean Sweep'],
    );
    expect(board.dayNumberOf(board.entries.first.unlock!.unlockedOn), 1);
  });

  test(
    'a missed reconciliation is repaired later with the earned date',
    () async {
      // Day 1 and 2 are perfect, but reconciliation never ran (e.g. it
      // failed after the habit commits).
      await completeAll();
      app.clock.current = DateTime(2026, 10, 2, 7);
      await completeAll();
      app.clock.current = DateTime(2026, 10, 3, 8);
      await act('no_junk_food', HabitAction.complete);

      final repaired = await app.achievements.reconcile();
      expect(
        {for (final u in repaired) u.key: u.unlockedOn},
        {
          AchievementKey.firstRep: day1,
          AchievementKey.firstPerfect: day1,
          AchievementKey.streak3: LocalDate(2026, 10, 3),
        },
      );
      expect(
        repaired.every((u) => u.unlockedAt == DateTime(2026, 10, 3, 8)),
        isTrue,
      );
    },
  );

  test('a failed reconciliation leaves the habit action committed', () async {
    final broken = AchievementService(
      sessions: app.sessions,
      progress: app.progress,
      achievements: _FailingAchievements(),
      clock: app.clock,
    );
    await act('no_junk_food', HabitAction.complete);
    await expectLater(broken.reconcile(), throwsA(isA<PersistenceFailure>()));
    expect((await app.tracking.today()).totalXp, 15);

    // The next successful run heals it.
    expect(
      (await app.achievements.reconcile()).single.key,
      AchievementKey.firstRep,
    );
  });

  test('the store never writes a key twice, even if asked to', () async {
    final store = DriftAchievementRepository(app.db);
    final earned = [
      EarnedAchievement(key: AchievementKey.halfway, earnedOn: day1),
    ];
    final at = DateTime(2026, 10, 1, 10);
    expect(await store.unlockNew(1, earned, at: at), hasLength(1));
    expect(
      await store.unlockNew(1, earned, at: at.add(const Duration(days: 1))),
      isEmpty,
    );
    final stored = await store.unlocks(1);
    expect(stored.single.unlockedAt, at);

    // Unknown keys written by a newer version are ignored, not fatal.
    await app.db
        .into(app.db.achievementUnlocks)
        .insert(
          AchievementUnlocksCompanion.insert(
            sessionId: 1,
            achievementKey: 'from_the_future',
            unlockedOn: day1,
            unlockedAt: at,
          ),
        );
    expect(await store.unlocks(1), hasLength(1));
  });

  group('across restart', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nextrep_p3_ach_');
      file = File('${dir.path}/nextrep.sqlite');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'unlocks persist and reconciliation does not duplicate them',
      () async {
        var run = TestApp(AppDatabase(NativeDatabase(file)), app.clock);
        await run.winterArc.beginSetup();
        await run.winterArc.startWinterArc();
        await run.tracking.perform(
          habitId: 'no_junk_food',
          action: HabitAction.complete,
          date: day1,
        );
        expect(await run.achievements.reconcile(), hasLength(1));
        await run.db.close();

        run = TestApp(AppDatabase(NativeDatabase(file)), app.clock);
        addTearDown(run.db.close);
        expect(await run.achievements.reconcile(), isEmpty);
        final board = (await run.achievements.board())!;
        expect(board.unlockedCount, 1);
        expect(
          await run.db.select(run.db.achievementUnlocks).get(),
          hasLength(1),
        );
      },
    );
  });
}

final class _FailingAchievements implements AchievementRepository {
  @override
  Future<List<AchievementUnlock>> unlocks(int sessionId) async => const [];

  @override
  Future<List<AchievementUnlock>> unlockNew(
    int sessionId,
    List<EarnedAchievement> earned, {
    required DateTime at,
  }) async => throw const PersistenceFailure('disk full');
}
