import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/achievement/achievement.dart';
import '../domain/achievement/achievement_repository.dart';
import 'persistence_guard.dart';

final class DriftAchievementRepository implements AchievementRepository {
  const DriftAchievementRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<AchievementUnlock>> unlocks(int sessionId) =>
      guardPersistence('load achievements', () async {
        final rows = await _rows(sessionId);
        return [
          for (final row in rows)
            if (AchievementKey.fromId(row.achievementKey) case final key?)
              AchievementUnlock(
                key: key,
                unlockedOn: row.unlockedOn,
                unlockedAt: row.unlockedAt,
              ),
        ];
      });

  @override
  Future<List<AchievementUnlock>> unlockNew(
    int sessionId,
    List<EarnedAchievement> earned, {
    required DateTime at,
  }) => guardPersistence(
    'unlock achievements',
    // Drift runs transactions one at a time, so no other unlock can slip in
    // between reading the stored keys and inserting the missing ones.
    () => _db.transaction(() async {
      if (earned.isEmpty) return const <AchievementUnlock>[];
      final stored = {
        for (final row in await _rows(sessionId)) row.achievementKey,
      };
      final fresh = [
        for (final e in earned)
          if (!stored.contains(e.key.id))
            AchievementUnlock(
              key: e.key,
              unlockedOn: e.earnedOn,
              unlockedAt: at,
            ),
      ];
      for (final unlock in fresh) {
        // The (session_id, achievement_key) primary key makes a duplicate a
        // no-op even if this ever ran twice.
        await _db
            .into(_db.achievementUnlocks)
            .insert(
              AchievementUnlocksCompanion.insert(
                sessionId: sessionId,
                achievementKey: unlock.key.id,
                unlockedOn: unlock.unlockedOn,
                unlockedAt: unlock.unlockedAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      return fresh;
    }),
  );

  Future<List<AchievementUnlockRow>> _rows(int sessionId) =>
      (_db.select(_db.achievementUnlocks)
            ..where((a) => a.sessionId.equals(sessionId))
            ..orderBy([(a) => OrderingTerm.asc(a.unlockedAt)]))
          .get();
}
