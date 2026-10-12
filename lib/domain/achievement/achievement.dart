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
  level5('level_5'),

  // Catalog v3 (Phase 10C).
  streak14('streak_14'),
  streak30('streak_30'),
  streak50('streak_50'),
  perfect25('perfect_25'),
  minimum7('minimum_7'),
  reflections14('reflections_14'),
  reflections30('reflections_30'),
  day14('day_14'),
  day60('day_60'),
  day75('day_75'),
  noJunk7('no_junk_7'),
  noJunk30('no_junk_30'),
  noJunk50('no_junk_50'),
  workout30('workout_30'),
  water30('water_30'),
  learning30('learning_30'),
  sleep14('sleep_before_14');

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

/// The theme an achievement belongs to, for grouping the collection.
/// Display metadata only: never persisted.
enum AchievementCategory {
  progress('Progress'),
  consistency('Consistency'),
  resilience('Resilience'),
  habitMastery('Habit Mastery'),
  reflection('Reflection'),
  journey('Journey');

  const AchievementCategory(this.label);

  final String label;
}

/// Display data of an achievement. The criteria live in `AchievementRules`.
final class AchievementDefinition {
  const AchievementDefinition({
    required this.key,
    required this.category,
    required this.title,
    required this.description,
  });

  final AchievementKey key;
  final AchievementCategory category;
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

/// A persisted unlock, at most one per session and key.
///
/// An unlock dated before today is permanent. One dated today is
/// provisional while the day can still change: if today's history stops
/// earning it (an undone completion, a Minimum Day returned to full
/// targets), reconciliation removes it again.
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

/// What one reconciliation changed.
final class UnlockChanges {
  const UnlockChanges({this.unlocked = const [], this.revoked = const []});

  /// Newly stored unlocks, in the order earned.
  final List<AchievementUnlock> unlocked;

  /// Today's unlocks that history no longer earns, now removed.
  final List<AchievementUnlock> revoked;

  bool get isEmpty => unlocked.isEmpty && revoked.isEmpty;
}

/// What one catalog backfill stored (`AchievementService.backfillCatalog`).
final class CatalogBackfill {
  const CatalogBackfill({
    this.celebratable = const UnlockChanges(),
    this.historical = const {},
  });

  /// The only changes ever celebrated: the active arc's, as a normal
  /// reconciliation reports them, or, with nothing unfinished, the Summit
  /// that the latest completed arc's close-out stored. Empty while a new
  /// arc is in setup. Never another unlock of a completed arc.
  final UnlockChanges celebratable;

  /// Unlocks newly stored for completed arcs, by session id. Stored
  /// silently.
  final Map<int, List<AchievementUnlock>> historical;

  bool get isEmpty => celebratable.isEmpty && historical.isEmpty;
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

  /// [entries] by category, in category order; empty categories are left
  /// out. Within a category, entries keep their display order.
  List<(AchievementCategory, List<AchievementStatus>)> get groups => [
    for (final category in AchievementCategory.values)
      if ([
            for (final e in entries)
              if (e.definition.category == category) e,
          ]
          case final members when members.isNotEmpty)
        (category, members),
  ];

  /// 1-based challenge day of [date].
  int dayNumberOf(LocalDate date) => startDate.daysUntil(date) + 1;
}
