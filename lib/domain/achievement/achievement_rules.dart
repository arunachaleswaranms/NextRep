import '../../core/time/local_date.dart';
import '../progress/arc_history.dart';
import '../progress/streak_rules.dart';
import '../xp/level_rules.dart';
import 'achievement.dart';
import 'achievement_catalog.dart';

/// The persisted facts of one arc that achievements are decided from.
///
/// Built by the caller from storage, so [AchievementRules] stays pure and
/// never reads a database itself.
final class AchievementContext {
  AchievementContext({
    required this.history,
    Iterable<LocalDate> reflectionDates = const [],
  }) : reflectionDates = _withinArc(history, reflectionDates);

  final ArcHistory history;

  /// Dates of the arc that have a saved reflection, oldest first. Dates
  /// outside the arc's elapsed days are ignored.
  final List<LocalDate> reflectionDates;

  static List<LocalDate> _withinArc(
    ArcHistory history,
    Iterable<LocalDate> dates,
  ) {
    final elapsed = history.elapsedDates.toSet();
    return {
      for (final d in dates)
        if (elapsed.contains(d)) d,
    }.toList()..sort();
  }
}

/// Pure rules deciding which achievements the stored history qualifies for,
/// and on which challenge date each was first earned.
///
/// Everything is derived from the [AchievementContext]: the [ArcHistory]
/// (day records, streak marks, the XP ledger by date, the arc's dates) and
/// the dates that have a reflection. Nothing here reads UI state or
/// storage, and past challenge days are immutable, so the result for a past
/// date never changes; only today can add (or, before it is persisted,
/// drop) an achievement.
abstract final class AchievementRules {
  static const int snowballStreak = 3;
  static const int coldFrontStreak = 7;
  static const int perfectDaysForTrio = 3;
  static const int perfectDaysForTen = 10;
  static const int minimumDaysForAdaptable = 3;
  static const int reflectionsForCheckIns = 7;

  /// The challenge day that marks the middle of the arc.
  static const int midwinterDay = 46;

  /// Every achievement currently earned, in catalog order.
  static List<EarnedAchievement> evaluate(AchievementContext context) {
    final history = context.history;
    final dates = history.elapsedDates;
    final earned = <AchievementKey, LocalDate>{};
    void earn(AchievementKey key, LocalDate? on) {
      if (on != null) earned[key] = on;
    }

    LocalDate? firstRep;
    final minimumDates = <LocalDate>[];
    final perfectDates = <LocalDate>[];
    final levelDates = <int, LocalDate>{};
    var xp = 0;
    for (final date in dates) {
      final record = history.recordOn(date);
      if (firstRep == null && record.entries.any((e) => e.progress.completed)) {
        firstRep = date;
      }
      if (record.isPerfect) perfectDates.add(date);
      if (record.isMinimumComplete) minimumDates.add(date);
      // XP amounts are positive, so the running total only grows and the
      // final total equals the session total.
      xp += history.records.xpByDate[date] ?? 0;
      levelDates.putIfAbsent(LevelRules.levelFor(xp), () => date);
    }

    earn(AchievementKey.firstRep, firstRep);
    earn(AchievementKey.firstPerfect, perfectDates.firstOrNull);
    earn(AchievementKey.streak3, _firstHabitStreak(history, snowballStreak));
    earn(AchievementKey.streak7, _firstHabitStreak(history, coldFrontStreak));
    earn(AchievementKey.perfect3, _nth(perfectDates, perfectDaysForTrio));
    earn(AchievementKey.perfect10, _nth(perfectDates, perfectDaysForTen));
    earn(AchievementKey.minimumComplete, minimumDates.firstOrNull);
    earn(AchievementKey.minimum3, _nth(minimumDates, minimumDaysForAdaptable));
    earn(AchievementKey.level2, _firstAtLevel(levelDates, 2));
    earn(AchievementKey.level3, _firstAtLevel(levelDates, 3));
    earn(AchievementKey.level5, _firstAtLevel(levelDates, 5));
    final reflections = context.reflectionDates;
    earn(AchievementKey.firstReflection, reflections.firstOrNull);
    earn(
      AchievementKey.reflections7,
      _nth(reflections, reflectionsForCheckIns),
    );
    earn(
      AchievementKey.halfway,
      dates.length >= midwinterDay ? dates[midwinterDay - 1] : null,
    );
    earn(
      AchievementKey.summit,
      history.isOver ? history.session.endDate : null,
    );

    return [
      for (final definition in AchievementCatalog.all)
        if (earned[definition.key] case final on?)
          EarnedAchievement(key: definition.key, earnedOn: on),
    ];
  }

  /// The [n]th date of [dates] (1-based), or null if there are fewer.
  static LocalDate? _nth(List<LocalDate> dates, int n) =>
      dates.length >= n ? dates[n - 1] : null;

  /// The earliest date on which any habit's run reached [length] days.
  static LocalDate? _firstHabitStreak(ArcHistory history, int length) {
    LocalDate? first;
    for (final habit in history.records.habits.habits) {
      final index = StreakRules.firstReaching(
        history.habitMarks(habit.id),
        length,
      );
      if (index == null) continue;
      final date = history.elapsedDates[index];
      if (first == null || date.isBefore(first)) first = date;
    }
    return first;
  }

  /// The first date on which the running XP total reached [level] or more.
  static LocalDate? _firstAtLevel(Map<int, LocalDate> firstDateAt, int level) {
    LocalDate? first;
    for (final MapEntry(key: reached, value: date) in firstDateAt.entries) {
      if (reached >= level && (first == null || date.isBefore(first))) {
        first = date;
      }
    }
    return first;
  }
}
