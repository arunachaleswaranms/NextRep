import '../../core/time/local_date.dart';
import 'achievement.dart';

/// Persistence boundary for achievement unlocks.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class AchievementRepository {
  /// Every stored unlock of [sessionId]. Unknown keys are skipped.
  Future<List<AchievementUnlock>> unlocks(int sessionId);

  /// Atomically brings the stored unlocks of [sessionId] in line with
  /// [earned], everything the history currently earns:
  ///
  /// * stores each achievement of [earned] that is not unlocked yet;
  /// * removes each unlock dated [today] whose key is not in [earned];
  /// * never touches an unlock dated before (or after) [today], or one
  ///   whose key this version doesn't know.
  ///
  /// Never writes a key twice: an already-unlocked key is left unchanged
  /// (the first unlock wins), and the (session, key) uniqueness of the
  /// store backs this up. Running it again with the same input changes
  /// nothing.
  Future<UnlockChanges> reconcileUnlocks(
    int sessionId,
    List<EarnedAchievement> earned, {
    required LocalDate today,
    required DateTime at,
  });
}
