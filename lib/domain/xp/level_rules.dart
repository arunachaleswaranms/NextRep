/// Level progression, derived purely from total XP.
///
/// The XP ledger is the only persisted truth; levels are never stored, so
/// this curve can be replaced without a data migration.
abstract final class LevelRules {
  /// XP needed to go from one level to the next.
  static const int xpPerLevel = 250;

  /// `1 + totalXp ~/ xpPerLevel`. 0 XP is level 1.
  static int levelFor(int totalXp) =>
      1 + (totalXp < 0 ? 0 : totalXp) ~/ xpPerLevel;

  /// XP at which [level] begins.
  static int xpAtStartOf(int level) => (level - 1) * xpPerLevel;

  static LevelProgress progressFor(int totalXp) {
    final xp = totalXp < 0 ? 0 : totalXp;
    final level = levelFor(xp);
    return LevelProgress(
      level: level,
      totalXp: xp,
      levelStartXp: xpAtStartOf(level),
      nextLevelXp: xpAtStartOf(level + 1),
    );
  }

  /// The highest level reached by going from [beforeXp] to [afterXp], or
  /// null if no level boundary was crossed upwards.
  static int? levelUp({required int beforeXp, required int afterXp}) {
    final before = levelFor(beforeXp);
    final after = levelFor(afterXp);
    return after > before ? after : null;
  }
}

/// Where a total XP value sits within its level.
final class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.totalXp,
    required this.levelStartXp,
    required this.nextLevelXp,
  });

  final int level;
  final int totalXp;

  /// Total XP at which [level] began.
  final int levelStartXp;

  /// Total XP at which the next level begins.
  final int nextLevelXp;

  /// XP earned since reaching [level].
  int get xpIntoLevel => totalXp - levelStartXp;

  /// XP the current level spans (start to next level).
  int get xpForLevel => nextLevelXp - levelStartXp;

  /// XP still needed for the next level.
  int get xpToNextLevel => nextLevelXp - totalXp;

  /// `0.0..1.0` progress towards the next level.
  double get ratio => xpIntoLevel / xpForLevel;
}
