import 'achievement.dart';

/// The achievement catalog, in display order: grouped by
/// [AchievementCategory], in category order. The Phase 3 set, the Phase 4
/// additions and the Phase 10C additions (activity milestones and longer
/// runs) live side by side; only the persisted [AchievementKey.id]s are
/// fixed, the order is presentation.
///
/// Achievements are collectibles only: they never grant XP, so the XP ledger
/// keeps a single authority (`DayRules`).
abstract final class AchievementCatalog {
  static const List<AchievementDefinition> all = [
    // Progress.
    AchievementDefinition(
      key: AchievementKey.firstRep,
      category: AchievementCategory.progress,
      title: 'First Rep',
      description: 'Complete your first habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.level2,
      category: AchievementCategory.progress,
      title: 'Getting Stronger',
      description: 'Reach Level 2.',
    ),
    AchievementDefinition(
      key: AchievementKey.level3,
      category: AchievementCategory.progress,
      title: 'Momentum',
      description: 'Reach Level 3.',
    ),
    AchievementDefinition(
      key: AchievementKey.level5,
      category: AchievementCategory.progress,
      title: 'Stronger Every Day',
      description: 'Reach Level 5.',
    ),

    // Consistency.
    AchievementDefinition(
      key: AchievementKey.firstPerfect,
      category: AchievementCategory.consistency,
      title: 'Clean Sweep',
      description: 'Earn your first Perfect Day.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak3,
      category: AchievementCategory.consistency,
      title: 'Snowball',
      description: 'Reach a 3-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak7,
      category: AchievementCategory.consistency,
      title: 'Cold Front',
      description: 'Reach a 7-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak14,
      category: AchievementCategory.consistency,
      title: 'Two Weeks Strong',
      description: 'Reach a 14-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak30,
      category: AchievementCategory.consistency,
      title: 'Cold Discipline',
      description: 'Reach a 30-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.streak50,
      category: AchievementCategory.consistency,
      title: 'Iron Winter',
      description: 'Reach a 50-day streak on any habit.',
    ),
    AchievementDefinition(
      key: AchievementKey.perfect3,
      category: AchievementCategory.consistency,
      title: 'Three Perfect Days',
      description: 'Earn 3 Perfect Days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.perfect10,
      category: AchievementCategory.consistency,
      title: 'Ten Clean Sweeps',
      description: 'Earn 10 Perfect Days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.perfect25,
      category: AchievementCategory.consistency,
      title: 'Quarter Century',
      description: 'Earn 25 Perfect Days in total.',
    ),

    // Resilience.
    AchievementDefinition(
      key: AchievementKey.minimumComplete,
      category: AchievementCategory.resilience,
      title: 'Still Moving',
      description: 'Fully complete a Minimum Day.',
    ),
    AchievementDefinition(
      key: AchievementKey.minimum3,
      category: AchievementCategory.resilience,
      title: 'Adaptable',
      description: 'Fully complete 3 Minimum Days.',
    ),
    AchievementDefinition(
      key: AchievementKey.minimum7,
      category: AchievementCategory.resilience,
      title: "Bend, Don't Break",
      description: 'Fully complete 7 Minimum Days.',
    ),

    // Habit mastery: tied to a built-in habit by its stable id.
    AchievementDefinition(
      key: AchievementKey.noJunk7,
      category: AchievementCategory.habitMastery,
      title: 'Clean Week',
      description: 'Reach a 7-day No Junk Food streak.',
    ),
    AchievementDefinition(
      key: AchievementKey.noJunk30,
      category: AchievementCategory.habitMastery,
      title: 'Intentional Month',
      description: 'Reach a 30-day No Junk Food streak.',
    ),
    AchievementDefinition(
      key: AchievementKey.noJunk50,
      category: AchievementCategory.habitMastery,
      title: 'Deep Discipline',
      description: 'Reach a 50-day No Junk Food streak.',
    ),
    AchievementDefinition(
      key: AchievementKey.workout30,
      category: AchievementCategory.habitMastery,
      title: 'Built by Reps',
      description: 'Complete your Workout goal on 30 days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.water30,
      category: AchievementCategory.habitMastery,
      title: 'Hydration Rhythm',
      description: 'Meet your own Water Intake goal on 30 days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.learning30,
      category: AchievementCategory.habitMastery,
      title: 'Always Learning',
      description: 'Complete your Learning / Skills goal on 30 days in total.',
    ),
    AchievementDefinition(
      key: AchievementKey.sleep14,
      category: AchievementCategory.habitMastery,
      title: 'Rest Rhythm',
      description: 'Meet your Sleep Before Target on 14 days in total.',
    ),

    // Reflection.
    AchievementDefinition(
      key: AchievementKey.firstReflection,
      category: AchievementCategory.reflection,
      title: 'Looking Inward',
      description: 'Save your first reflection.',
    ),
    AchievementDefinition(
      key: AchievementKey.reflections7,
      category: AchievementCategory.reflection,
      title: 'Seven Check-ins',
      description: "Reflect on 7 days. They don't need to be in a row.",
    ),
    AchievementDefinition(
      key: AchievementKey.reflections14,
      category: AchievementCategory.reflection,
      title: 'Two Weeks Inward',
      description: "Reflect on 14 days. They don't need to be in a row.",
    ),
    AchievementDefinition(
      key: AchievementKey.reflections30,
      category: AchievementCategory.reflection,
      title: 'Know Yourself',
      description: "Reflect on 30 days. They don't need to be in a row.",
    ),

    // Journey.
    AchievementDefinition(
      key: AchievementKey.day14,
      category: AchievementCategory.journey,
      title: 'First Chapter',
      description: 'Reach Day 14 of your Arc.',
    ),
    AchievementDefinition(
      key: AchievementKey.halfway,
      category: AchievementCategory.journey,
      title: 'Midwinter',
      description: 'Reach Day 46, the middle of the Arc.',
    ),
    AchievementDefinition(
      key: AchievementKey.day60,
      category: AchievementCategory.journey,
      title: 'Aurora',
      description: 'Reach Day 60 of your Arc.',
    ),
    AchievementDefinition(
      key: AchievementKey.day75,
      category: AchievementCategory.journey,
      title: 'Final Approach',
      description: 'Reach Day 75 of your Arc.',
    ),
    AchievementDefinition(
      key: AchievementKey.summit,
      category: AchievementCategory.journey,
      title: 'Summit',
      description: 'Complete the 92-day Winter Arc.',
    ),
  ];

  static AchievementDefinition of(AchievementKey key) =>
      all.firstWhere((d) => d.key == key);
}
