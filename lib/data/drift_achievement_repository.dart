import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/local_date.dart';
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
  Future<UnlockChanges> reconcileUnlocks(
    int sessionId,
    List<EarnedAchievement> earned, {
    required LocalDate today,
    required DateTime at,
  }) => guardPersistence(
    'reconcile achievements',
    // Drift runs transactions one at a time, so no other write can slip in
    // between reading the stored unlocks and changing them.
    () => _db.transaction(() async {
      final earnedKeys = {for (final e in earned) e.key};
      final rows = await _rows(sessionId);
      final revoked = [
        for (final row in rows)
          if (row.unlockedOn == today)
            if (AchievementKey.fromId(row.achievementKey) case final key?)
              if (!earnedKeys.contains(key))
                AchievementUnlock(
                  key: key,
                  unlockedOn: row.unlockedOn,
                  unlockedAt: row.unlockedAt,
                ),
      ];
      if (revoked.isNotEmpty) {
        await (_db.delete(_db.achievementUnlocks)..where(
              (a) =>
                  a.sessionId.equals(sessionId) &
                  a.unlockedOn.equalsValue(today) &
                  a.achievementKey.isIn([for (final u in revoked) u.key.id]),
            ))
            .go();
      }
      final kept = {for (final row in rows) row.achievementKey}
        ..removeAll([for (final u in revoked) u.key.id]);
      final unlocked = [
        for (final e in earned)
          if (!kept.contains(e.key.id))
            AchievementUnlock(
              key: e.key,
              unlockedOn: e.earnedOn,
              unlockedAt: at,
            ),
      ];
      for (final unlock in unlocked) {
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
      return UnlockChanges(unlocked: unlocked, revoked: revoked);
    }),
  );

  Future<List<AchievementUnlockRow>> _rows(int sessionId) =>
      (_db.select(_db.achievementUnlocks)
            ..where((a) => a.sessionId.equals(sessionId))
            ..orderBy([(a) => OrderingTerm.asc(a.unlockedAt)]))
          .get();
}
