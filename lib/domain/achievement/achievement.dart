import '../../core/time/local_date.dart';

/// Every achievement of the catalog. [id] is persisted, so never change an
/// existing id; add new values instead.
enum AchievementKey {
  firstRep('first_rep'),
  firstPerfect('first_perfect'),
  streak3('streak_3'),
  streak7('streak_7'),
  perfect3('perfect_3'),
  minimumComplete('minimum_complete'),
  level2('level_2'),
  level3('level_3'),
  halfway('halfway'),
  summit('summit'),

  // Catalog v2 (Phase 4).
  firstReflection('first_reflection'),
  reflections7('reflections_7'),
  minimum3('minimum_3'),
  perfect10('perfect_10'),
  level5('level_5');

  const AchievementKey(this.id);

  /// Stable storage key, e.g. `first_rep`.
  final String id;

  /// The key stored as [id], or null for an unknown (e.g. newer) key.
  static AchievementKey? fromId(String id) {
    for (final key in values) {
      if (key.id == id) return key;
    }
    return null;
  }
}

/// Display data of an achievement. The criteria live in `AchievementRules`.
final class AchievementDefinition {
  const AchievementDefinition({
    required this.key,
    required this.title,
    required this.description,
  });

  final AchievementKey key;
  final String title;

  /// What it takes to earn it, shown whether locked or unlocked.
  final String description;
}

/// An achievement that the stored history currently qualifies for.
final class EarnedAchievement {
  const EarnedAchievement({required this.key, required this.earnedOn});

  final AchievementKey key;

  /// The challenge date on which the history first met the criteria.
  final LocalDate earnedOn;

  @override
  bool operator ==(Object other) =>
      other is EarnedAchievement &&
      other.key == key &&
      other.earnedOn == earnedOn;

  @override
  int get hashCode => Object.hash(key, earnedOn);

  @override
  String toString() => 'EarnedAchievement(${key.id}, $earnedOn)';
}

/// A persisted unlock. Written once per session and key, never changed.
final class AchievementUnlock {
  const AchievementUnlock({
    required this.key,
    required this.unlockedOn,
    required this.unlockedAt,
  });

  final AchievementKey key;

  /// The challenge date on which it was earned.
  final LocalDate unlockedOn;

  /// When the unlock was first persisted.
  final DateTime unlockedAt;
}

/// One catalog entry with its unlock, if any.
final class AchievementStatus {
  const AchievementStatus({required this.definition, this.unlock});

  final AchievementDefinition definition;
  final AchievementUnlock? unlock;

  bool get unlocked => unlock != null;
}

/// The whole catalog in display order, with what this arc has unlocked.
final class AchievementBoard {
  const AchievementBoard({required this.startDate, required this.entries});

  /// Day 1 of the arc, to express unlock dates as challenge days.
  final LocalDate startDate;
  final List<AchievementStatus> entries;

  int get total => entries.length;
  int get unlockedCount => entries.where((e) => e.unlocked).length;

  /// 1-based challenge day of [date].
  int dayNumberOf(LocalDate date) => startDate.daysUntil(date) + 1;
}
