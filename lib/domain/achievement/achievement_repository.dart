import 'achievement.dart';

/// Persistence boundary for achievement unlocks.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class AchievementRepository {
  /// Every stored unlock of [sessionId]. Unknown keys are skipped.
  Future<List<AchievementUnlock>> unlocks(int sessionId);

  /// Atomically stores the achievements of [earned] that [sessionId] has not
  /// unlocked yet, and returns exactly those, in the order given.
  ///
  /// Never writes a key twice: already-unlocked keys are left unchanged (the
  /// first unlock wins), and the (session, key) uniqueness of the store
  /// backs this up.
  Future<List<AchievementUnlock>> unlockNew(
    int sessionId,
    List<EarnedAchievement> earned, {
    required DateTime at,
  });
}
