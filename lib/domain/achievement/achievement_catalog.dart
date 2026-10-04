import 'achievement.dart';

/// The achievement catalog, in display order: the Phase 3 set plus the
/// Phase 4 additions, grouped by theme.
///
/// Achievements are collectibles only: they never grant XP, so the XP ledger
/// keeps a single authority (`DayRules`).
abstract final class AchievementCatalog {
  static const List<AchievementDefinition> all = [
    AchievementDefinition(
      key: AchievementKey.firstRep,
      title: 'First Rep',
      description: 'Complete your first habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.firstPerfect,
      title: 'Clean Sweep',
      description: 'Earn your first Perfect Day.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak3,
      title: 'Snowball',
      description: 'Reach a 3-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak7,
      title: 'Cold Front',
      description: 'Reach a 7-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.perfect3,
      title: 'Three Perfect Days',
      description: 'Earn 3 Perfect Days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.perfect10,
      title: 'Ten Clean Sweeps',
      description: 'Earn 10 Perfect Days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.minimumComplete,
      title: 'Still Moving',
      description: 'Fully complete a Minimum Day.',
    ),
    AchievementDefinition(
      key: AchievementKey.minimum3,
      title: 'Adaptable',
      description: 'Fully complete 3 Minimum Days.',
    ),
    AchievementDefinition(
      key: AchievementKey.level2,
      title: 'Getting Stronger',
      description: 'Reach Level 2.',
    ),
    AchievementDefinition(
      key: AchievementKey.level3,
      title: 'Momentum',
      description: 'Reach Level 3.',
    ),
    AchievementDefinition(
      key: AchievementKey.level5,
      title: 'Stronger Every Day',
      description: 'Reach Level 5.',
    ),
    AchievementDefinition(
      key: AchievementKey.firstReflection,
      title: 'Looking Inward',
      description: 'Save your first reflection.',
    ),
    AchievementDefinition(
      key: AchievementKey.reflections7,
      title: 'Seven Check-ins',
      description: "Reflect on 7 days. They don't need to be in a row.",
    ),
    AchievementDefinition(
      key: AchievementKey.halfway,
      title: 'Midwinter',
      description: 'Reach Day 46, the middle of the Arc.',
    ),
    AchievementDefinition(
      key: AchievementKey.summit,
      title: 'Summit',
      description: 'Complete the 92-day Winter Arc.',
    ),
  ];

  static AchievementDefinition of(AchievementKey key) =>
      all.firstWhere((d) => d.key == key);
}
