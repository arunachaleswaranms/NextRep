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
/// (day records, streak marks, the XP ledger by date, the arc's
/// participating dates) and the dates that have a reflection. Days before
/// the user joined a seasonal arc are not part of the history, so nothing
/// can be earned on them. Nothing here reads UI state or
/// storage, and past challenge days are immutable, so the result for a past
/// date never changes; only today can add or drop an achievement (an
/// unlock dated today is removed again if today stops earning it).
abstract final class AchievementRules {
  static const int snowballStreak = 3;
  static const int coldFrontStreak = 7;
  static const int twoWeeksStreak = 14;
  static const int coldDisciplineStreak = 30;
  static const int ironWinterStreak = 50;
  static const int perfectDaysForTrio = 3;
  static const int perfectDaysForTen = 10;
  static const int perfectDaysForQuarterCentury = 25;
  static const int minimumDaysForAdaptable = 3;
  static const int minimumDaysForBendDontBreak = 7;
  static const int reflectionsForCheckIns = 7;
  static const int reflectionsForTwoWeeks = 14;
  static const int reflectionsForKnowYourself = 30;

  /// The challenge day that marks the middle of the arc (16 November in a
  /// season).
  static const int midwinterDay = 46;
  static const int firstChapterDay = 14;
  static const int auroraDay = 60;
  static const int finalApproachDay = 75;

  /// Stable ids of the built-in habits that have their own achievements.
  /// Matched by id only: a renamed built-in habit still counts, a custom
  /// habit with the same name doesn't, and the legacy `sleep_on_time`
  /// habit is not `sleep_before`.
  static const String noJunkFoodId = 'no_junk_food';
  static const String workoutId = 'workout';
  static const String waterId = 'water';
  static const String learningId = 'learning';
  static const String sleepBeforeId = 'sleep_before';

  static const int habitMasteryDays = 30;
  static const int restRhythmDays = 14;

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

    // Progress.
    earn(AchievementKey.firstRep, firstRep);
    earn(AchievementKey.level2, _firstAtLevel(levelDates, 2));
    earn(AchievementKey.level3, _firstAtLevel(levelDates, 3));
    earn(AchievementKey.level5, _firstAtLevel(levelDates, 5));

    // Consistency.
    earn(AchievementKey.firstPerfect, perfectDates.firstOrNull);
    for (final (key, length) in const [
      (AchievementKey.streak3, snowballStreak),
      (AchievementKey.streak7, coldFrontStreak),
      (AchievementKey.streak14, twoWeeksStreak),
      (AchievementKey.streak30, coldDisciplineStreak),
      (AchievementKey.streak50, ironWinterStreak),
    ]) {
      earn(key, _firstHabitStreak(history, length));
    }
    earn(AchievementKey.perfect3, _nth(perfectDates, perfectDaysForTrio));
    earn(AchievementKey.perfect10, _nth(perfectDates, perfectDaysForTen));
    earn(
      AchievementKey.perfect25,
      _nth(perfectDates, perfectDaysForQuarterCentury),
    );

    // Resilience.
    earn(AchievementKey.minimumComplete, minimumDates.firstOrNull);
    earn(AchievementKey.minimum3, _nth(minimumDates, minimumDaysForAdaptable));
    earn(
      AchievementKey.minimum7,
      _nth(minimumDates, minimumDaysForBendDontBreak),
    );

    // Habit mastery: runs and totals of one built-in habit, with the same
    // completion (DayRecord) and streak (ArcHistory.habitMarks) semantics
    // as everywhere else.
    for (final (key, length) in const [
      (AchievementKey.noJunk7, coldFrontStreak),
      (AchievementKey.noJunk30, coldDisciplineStreak),
      (AchievementKey.noJunk50, ironWinterStreak),
    ]) {
      earn(key, _firstStreakOf(history, noJunkFoodId, length));
    }
    for (final (key, habitId, days) in const [
      (AchievementKey.workout30, workoutId, habitMasteryDays),
      (AchievementKey.water30, waterId, habitMasteryDays),
      (AchievementKey.learning30, learningId, habitMasteryDays),
      (AchievementKey.sleep14, sleepBeforeId, restRhythmDays),
    ]) {
      earn(key, _nthCompletedDay(history, habitId, days));
    }

    // Reflection: only which dates have a reflection, never what it says.
    final reflections = context.reflectionDates;
    earn(AchievementKey.firstReflection, reflections.firstOrNull);
    earn(
      AchievementKey.reflections7,
      _nth(reflections, reflectionsForCheckIns),
    );
    earn(
      AchievementKey.reflections14,
      _nth(reflections, reflectionsForTwoWeeks),
    );
    earn(
      AchievementKey.reflections30,
      _nth(reflections, reflectionsForKnowYourself),
    );

    // Journey.
    for (final (key, day) in const [
      (AchievementKey.day14, firstChapterDay),
      (AchievementKey.halfway, midwinterDay),
      (AchievementKey.day60, auroraDay),
      (AchievementKey.day75, finalApproachDay),
    ]) {
      earn(key, _participatedMilestone(history, day));
    }
    // Summit: the arc ran to its close. A seasonal arc joined late earns it
    // too: it was completed through 31 December.
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
      final date = _firstStreakOf(history, habit.id, length);
      if (date != null && (first == null || date.isBefore(first))) {
        first = date;
      }
    }
    return first;
  }

  /// The date on which a run of habit [habitId] first reached [length]
  /// days, or null (also when the arc has no such habit).
  static LocalDate? _firstStreakOf(
    ArcHistory history,
    String habitId,
    int length,
  ) {
    final index = StreakRules.firstReaching(
      history.habitMarks(habitId),
      length,
    );
    return index == null ? null : history.elapsedDates[index];
  }

  /// The [n]th date on which habit [habitId] was complete. Days on which it
  /// wasn't enabled don't apply; the day's record decides completion
  /// (effective target, Minimum Day, goal changes).
  static LocalDate? _nthCompletedDay(
    ArcHistory history,
    String habitId,
    int n,
  ) => _nth([
    for (final date in history.elapsedDates)
      if (history.recordOn(date).entryFor(habitId)?.progress.completed ?? false)
        date,
  ], n);

  /// Challenge day [dayNumber] itself, once it has started, and only if
  /// the user took part that day: joining a season later never awards a
  /// milestone retroactively.
  static LocalDate? _participatedMilestone(ArcHistory history, int dayNumber) {
    final date = history.session.startDate.addDays(dayNumber - 1);
    return history.session.isParticipatingOn(date) &&
            !date.isAfter(history.today)
        ? date
        : null;
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
