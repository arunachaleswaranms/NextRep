import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_repository.dart';
import 'package:nextrep/domain/achievement/achievement_service.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';

import '../support/fakes.dart';

/// Phase 10A: unlocks dated before today are permanent; unlocks dated today
/// follow today's history, which can still change. Real services over a
/// real SQLite database. Default habits: workout (30 min), water (8),
/// learning (20 min), no_junk_food (binary).
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

  void goToDay(int day) =>
      app.clock.current = DateTime(2026, 10, day, 7 + day % 5);

  /// Stored unlocks by key id, with their date.
  Future<Map<String, LocalDate>> stored() async => {
    for (final row in await app.db.select(app.db.achievementUnlocks).get())
      row.achievementKey: row.unlockedOn,
  };

  Future<void> insertUnlock(String key, LocalDate on) => app.db
      .into(app.db.achievementUnlocks)
      .insert(
        AchievementUnlocksCompanion.insert(
          sessionId: 1,
          achievementKey: key,
          unlockedOn: on,
          unlockedAt: DateTime(2026, 10, 1, 6),
        ),
      );

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 7)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  test('First Rep earned today disappears when its only completion is '
      'undone, and returns exactly once when earned again', () async {
    await act('no_junk_food', HabitAction.complete);
    expect((await app.achievements.reconcile()).map((u) => u.key), [
      AchievementKey.firstRep,
    ]);

    await act('no_junk_food', HabitAction.undoCompletion);
    final undone = await app.achievements.sync();
    expect(undone.unlocked, isEmpty);
    expect(undone.revoked.map((u) => u.key), [AchievementKey.firstRep]);
    expect(await stored(), isEmpty);
    expect((await app.achievements.board())!.unlockedCount, 0);

    app.clock.advance(const Duration(hours: 2));
    await act('no_junk_food', HabitAction.complete);
    final again = await app.achievements.reconcile();
    expect(again.map((u) => u.key), [AchievementKey.firstRep]);
    expect(again.single.unlockedAt, DateTime(2026, 10, 1, 9));
    expect(await stored(), {'first_rep': day1});
  });

  test('an achievement still justified by history is kept as it was', () async {
    await act('no_junk_food', HabitAction.complete);
    await act('water', HabitAction.increment, times: 8);
    final first = (await app.achievements.reconcile()).single;
    app.clock.advance(const Duration(hours: 1));

    // Another completion still earns First Rep today.
    await act('no_junk_food', HabitAction.undoCompletion);
    final changes = await app.achievements.sync();
    expect(changes.isEmpty, isTrue);
    final kept = (await app.db.select(app.db.achievementUnlocks).get()).single;
    expect(kept.achievementKey, 'first_rep');
    expect(kept.unlockedAt, first.unlockedAt);
  });

  test('first Perfect Day earned today disappears when the Perfect Day is '
      'undone', () async {
    await completeAll();
    expect(
      (await app.achievements.reconcile()).map((u) => u.key),
      containsAll([AchievementKey.firstRep, AchievementKey.firstPerfect]),
    );

    await act('no_junk_food', HabitAction.undoCompletion);
    final changes = await app.achievements.sync();
    expect(changes.revoked.map((u) => u.key), [AchievementKey.firstPerfect]);
    expect(await stored(), {'first_rep': day1});
  });

  test('Still Moving disappears after returning to full targets', () async {
    await app.tracking.activateMinimumDay(date: day1);
    await act('workout', HabitAction.increment, times: 2);
    await act('water', HabitAction.increment, times: 3);
    await act('learning', HabitAction.increment);
    await act('no_junk_food', HabitAction.complete);
    expect(
      (await app.achievements.reconcile()).map((u) => u.key),
      containsAll([AchievementKey.firstRep, AchievementKey.minimumComplete]),
    );

    await app.tracking.returnToFullTargets(date: day1);
    final changes = await app.achievements.sync();
    expect(changes.revoked.map((u) => u.key), [AchievementKey.minimumComplete]);
    // No Junk Food is still complete at its full target.
    expect(await stored(), {'first_rep': day1});

    // Back to a Minimum Day: earned again, stored once.
    await app.tracking.activateMinimumDay(date: day1);
    expect((await app.achievements.reconcile()).map((u) => u.key), [
      AchievementKey.minimumComplete,
    ]);
    expect(await stored(), {'first_rep': day1, 'minimum_complete': day1});
  });

  test('a streak reached today disappears if today is undone', () async {
    for (final day in [1, 2, 3]) {
      goToDay(day);
      await act('no_junk_food', HabitAction.complete);
      await app.achievements.reconcile();
    }
    expect(await stored(), {
      'first_rep': day1,
      'streak_3': LocalDate(2026, 10, 3),
    });

    await act('no_junk_food', HabitAction.undoCompletion);
    final changes = await app.achievements.sync();
    expect(changes.revoked.map((u) => u.key), [AchievementKey.streak3]);
    // First Rep is from Day 1: never revoked.
    expect(await stored(), {'first_rep': day1});
  });

  test('level and Perfect Day totals reached today follow today; past '
      'unlocks and still-earned ones stay', () async {
    for (final day in [1, 2, 3]) {
      goToDay(day);
      await completeAll();
      await app.achievements.reconcile();
    }
    // 3 Perfect Days: 270 XP, level 2 on Day 3.
    final day3 = LocalDate(2026, 10, 3);
    expect(await stored(), {
      'first_rep': day1,
      'first_perfect': day1,
      'streak_3': day3,
      'perfect_3': day3,
      'level_2': day3,
    });

    await act('no_junk_food', HabitAction.undoCompletion); // 225 XP
    final changes = await app.achievements.sync();
    expect(
      changes.revoked.map((u) => u.key),
      unorderedEquals([AchievementKey.perfect3, AchievementKey.level2]),
    );
    expect(await stored(), {
      'first_rep': day1,
      'first_perfect': day1,
      'streak_3': day3, // three habits still have a 3-day run
    });
  });

  test("an unlock from an earlier date is never removed by today's "
      'reconciliation', () async {
    await act('no_junk_food', HabitAction.complete);
    await app.achievements.reconcile();
    // An earlier unlock the current history does not support (e.g. data
    // from an older rule), and an unknown key from a newer version.
    await insertUnlock('perfect_3', day1);
    goToDay(2);
    await insertUnlock('from_the_future', app.clock.today());

    expect((await app.achievements.sync()).isEmpty, isTrue);
    await act('water', HabitAction.increment);
    await act('water', HabitAction.decrement);
    expect((await app.achievements.sync()).isEmpty, isTrue);
    expect(await stored(), {
      'first_rep': day1,
      'perfect_3': day1,
      'from_the_future': LocalDate(2026, 10, 2),
    });
  });

  test('repeated reconciliation is idempotent', () async {
    await completeAll();
    await app.achievements.reconcile();
    await act('no_junk_food', HabitAction.undoCompletion);
    expect((await app.achievements.sync()).revoked, hasLength(1));
    final after = await stored();
    for (var i = 0; i < 3; i++) {
      expect((await app.achievements.sync()).isEmpty, isTrue);
      expect(await app.achievements.reconcile(), isEmpty);
    }
    expect(await stored(), after);
  });

  test(
    'a failed reconciliation changes nothing and the next run heals',
    () async {
      final broken = AchievementService(
        sessions: app.sessions,
        progress: app.progress,
        achievements: _FailingAchievements(),
        reflections: app.reflectionStore,
        clock: app.clock,
      );
      await act('no_junk_food', HabitAction.complete);
      await app.achievements.reconcile();
      await act('no_junk_food', HabitAction.undoCompletion);

      await expectLater(broken.sync(), throwsA(isA<PersistenceFailure>()));
      await expectLater(broken.reconcile(), throwsA(isA<PersistenceFailure>()));
      expect(await stored(), {'first_rep': day1});

      expect(
        (await app.achievements.sync()).revoked.single.key,
        AchievementKey.firstRep,
      );
      expect(await stored(), isEmpty);
    },
  );
}

final class _FailingAchievements implements AchievementRepository {
  @override
  Future<List<AchievementUnlock>> unlocks(int sessionId) async => const [];

  @override
  Future<UnlockChanges> reconcileUnlocks(
    int sessionId,
    List<EarnedAchievement> earned, {
    required LocalDate today,
    required DateTime at,
  }) async => throw const PersistenceFailure('disk full');
}
