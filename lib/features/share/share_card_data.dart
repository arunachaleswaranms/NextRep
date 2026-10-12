import '../../domain/achievement/achievement.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/formatting/habit_labels.dart';

// Snapshots of persisted facts for the three share cards. A card renders
// one of these and nothing else; it never decides XP, streaks, completion
// or achievements. Privacy choices are applied here, so a hidden value
// never reaches the card, its semantics, the file name or the share text.
//
// A card never carries reflection or Journal text, moods, logged clock
// times (such as last night's bedtime), reminder settings or calendar
// dates: none of them is read here. Cards and their share text carry the
// NextRep name only: no link, tracking parameter or referral identifier.

/// What the user chose to show on a Today's Progress card. Not persisted:
/// every preview starts with everything shown.
final class SharePrivacyOptions {
  const SharePrivacyOptions({
    this.habitNames = true,
    this.xpAndLevel = true,
    this.streak = true,
  });

  final bool habitNames;
  final bool xpAndLevel;
  final bool streak;

  SharePrivacyOptions copyWith({
    bool? habitNames,
    bool? xpAndLevel,
    bool? streak,
  }) => SharePrivacyOptions(
    habitNames: habitNames ?? this.habitNames,
    xpAndLevel: xpAndLevel ?? this.xpAndLevel,
    streak: streak ?? this.streak,
  );
}

/// The challenge a card belongs to, as challenge facts rather than
/// calendar dates.
final class ShareArcIdentity {
  ShareArcIdentity.of(WinterArcSession session)
    : seasonal = session.isSeasonal,
      totalDays = session.lengthInDays,
      seasonYear = session.isSeasonal ? session.startDate.year : null,
      joinDay = session.joinDayNumber ?? 1;

  final bool seasonal;
  final int totalDays;

  /// The season of a Seasonal Winter Arc (it always runs 1 Oct – 31 Dec).
  final int? seasonYear;

  /// The challenge day the user joined on: Day 1 for a rolling arc, later
  /// for a seasonal arc joined late.
  final int joinDay;

  bool get joinedLate => joinDay > 1;

  /// "Winter Arc" or "Seasonal Winter Arc".
  String get name => seasonal ? 'Seasonal Winter Arc' : 'Winter Arc';
}

/// One habit on a Today's Progress card. [title] and [iconKey] are null
/// when habit names are hidden.
final class TodayShareHabit {
  const TodayShareHabit({required this.done, this.title, this.iconKey});

  final bool done;
  final String? title;
  final String? iconKey;
}

/// A streak with an honest name: the Perfect Day streak, or the best
/// current streak of any one habit. Never an "overall" streak.
final class ShareStreak {
  const ShareStreak({required this.label, required this.days});

  /// The current Perfect Day streak if there is one, otherwise the best
  /// active habit streak, otherwise null.
  static ShareStreak? of(DaySummary summary) {
    final perfect = summary.perfectDays.streak.current;
    if (perfect > 0) {
      return ShareStreak(label: 'Perfect Day streak', days: perfect);
    }
    var best = 0;
    for (final streak in summary.habitStreaks.values) {
      if (streak.current > best) best = streak.current;
    }
    return best > 0
        ? ShareStreak(label: 'Best active habit streak', days: best)
        : null;
  }

  final String label;
  final int days;

  /// "14 days".
  String get daysLabel => '$days ${days == 1 ? 'day' : 'days'}';
}

/// Today's Progress card: the day of the arc, how many habits are done,
/// each habit's status and, if shown, level, XP and a streak.
final class TodayShareCardData {
  const TodayShareCardData({
    required this.arc,
    required this.dayLabel,
    required this.dayNumber,
    required this.completed,
    required this.total,
    required this.minimumDay,
    required this.perfectDay,
    required this.habits,
    required this.showsHabitNames,
    this.level,
    this.totalXp,
    this.streak,
  });

  factory TodayShareCardData.fromSummary(
    DaySummary summary, {
    SharePrivacyOptions privacy = const SharePrivacyOptions(),
  }) {
    final names = privacy.habitNames;
    return TodayShareCardData(
      arc: ShareArcIdentity.of(summary.session),
      dayLabel: dayTitle(summary.position),
      dayNumber: switch (summary.position) {
        ArcInProgress(:final dayNumber) => dayNumber,
        _ => null,
      },
      completed: summary.completion.completed,
      total: summary.completion.total,
      minimumDay: summary.mode.isMinimum,
      perfectDay: summary.isPerfect,
      habits: [
        for (final entry in summary.entries)
          TodayShareHabit(
            done: entry.progress.completed,
            title: names ? entry.habit.title : null,
            iconKey: names ? entry.habit.iconKey : null,
          ),
      ],
      showsHabitNames: names,
      level: privacy.xpAndLevel ? summary.level.level : null,
      totalXp: privacy.xpAndLevel ? summary.totalXp : null,
      streak: privacy.streak ? ShareStreak.of(summary) : null,
    );
  }

  final ShareArcIdentity arc;

  /// "Day 24 of 92" (or "Starts tomorrow", "Winter Arc complete").
  final String dayLabel;

  /// Today's challenge day, or null outside the arc's window.
  final int? dayNumber;
  final int completed;
  final int total;
  final bool minimumDay;

  /// Never true on a Minimum Day.
  final bool perfectDay;
  final List<TodayShareHabit> habits;
  final bool showsHabitNames;
  final int? level;
  final int? totalXp;
  final ShareStreak? streak;

  /// "WINTER ARC · DAY 24 OF 92".
  String get headline => '${arc.name} · $dayLabel'.toUpperCase();

  String get tagline => perfectDay
      ? 'Every rep counted today.'
      : minimumDay
      ? 'Showing up, even on the hard days.'
      : 'Keep showing up.';

  String get fileName => switch (dayNumber) {
    final day? => 'nextrep-day-$day.png',
    null => 'nextrep-today.png',
  };

  /// Accompanying text: the arc and day only, never habit data.
  String get shareText => switch (dayNumber) {
    final day? => 'My ${arc.name} · Day $day/${arc.totalDays} — NextRep',
    null => 'My ${arc.name} — NextRep',
  };

  /// What the card shows, for screen readers in the preview.
  String get semanticsLabel => [
    "Today's Progress card",
    '${arc.name}, $dayLabel',
    '$completed of $total habits complete',
    if (minimumDay) 'Minimum Day',
    if (perfectDay) 'Perfect Day',
    if (showsHabitNames)
      for (final habit in habits)
        '${habit.title}, ${habit.done ? 'done' : 'not done'}',
    if (level case final level?) 'Level $level',
    if (totalXp case final xp?) '$xp XP',
    if (streak case final streak?) '${streak.label} ${streak.daysLabel}',
  ].join('. ');
}

/// One goal on a My Arc card: the habit and its full (normal) target.
final class ArcShareGoal {
  const ArcShareGoal({
    required this.title,
    required this.iconKey,
    required this.target,
  });

  final String title;
  final String iconKey;

  /// "30 min", "8 glasses", "Before 23:30", "Daily goal".
  final String target;
}

/// My Arc card: the habits and goals the user is committed to.
///
/// It shows the configuration in effect today: the habits enabled today
/// with their normal targets (never Minimum Day targets, even on a Minimum
/// Day). An edit saved for tomorrow appears from tomorrow, as everywhere
/// else in the app.
final class ArcShareCardData {
  const ArcShareCardData({required this.arc, required this.goals});

  factory ArcShareCardData.fromSummary(DaySummary summary) => ArcShareCardData(
    arc: ShareArcIdentity.of(summary.session),
    goals: [
      for (final entry in summary.entries)
        ArcShareGoal(
          title: entry.habit.title,
          iconKey: entry.habit.iconKey,
          target: targetLabel(entry.habit, entry.config.target),
        ),
    ],
  );

  final ShareArcIdentity arc;
  final List<ArcShareGoal> goals;

  /// "MY 92-DAY WINTER ARC" or "MY SEASONAL WINTER ARC".
  String get headline => arc.seasonal
      ? 'MY SEASONAL WINTER ARC'
      : 'MY ${arc.totalDays}-DAY WINTER ARC';

  /// "Rolling 92-day Arc" or "Winter season 2026 · 92 days".
  String get subtitle => arc.seasonal
      ? 'Winter season ${arc.seasonYear} · ${arc.totalDays} days'
      : 'Rolling ${arc.totalDays}-day Arc';

  /// "DAY 1", or "JOINED DAY 15" for a seasonal arc joined late.
  String get startLabel =>
      arc.joinedLate ? 'JOINED DAY ${arc.joinDay}' : 'DAY 1';

  String get endLabel => 'DAY ${arc.totalDays}';

  String get tagline => "I'm committing to showing up.";

  String get fileName => 'nextrep-my-arc.png';

  String get shareText => arc.seasonal
      ? 'My Seasonal Winter Arc — NextRep'
      : 'My ${arc.totalDays}-day Winter Arc — NextRep';

  String get semanticsLabel => [
    'My Arc card',
    headline.toLowerCase(),
    subtitle,
    for (final goal in goals) '${goal.title}, ${goal.target}',
    '${startLabel.toLowerCase()} to ${endLabel.toLowerCase()}',
  ].join('. ');
}

/// Achievement card: one unlocked achievement and the challenge day it was
/// earned on.
final class AchievementShareCardData {
  const AchievementShareCardData({
    required this.key,
    required this.title,
    required this.description,
    required this.dayNumber,
  });

  /// The card for [status], or null if it is locked: only unlocked
  /// achievements can be shared.
  static AchievementShareCardData? of(
    AchievementStatus status,
    AchievementBoard board,
  ) {
    final unlock = status.unlock;
    if (unlock == null) return null;
    return AchievementShareCardData(
      key: status.definition.key,
      title: status.definition.title,
      description: status.definition.description,
      dayNumber: board.dayNumberOf(unlock.unlockedOn),
    );
  }

  final AchievementKey key;
  final String title;

  /// What it took to earn it.
  final String description;

  /// The challenge day it was unlocked on.
  final int dayNumber;

  /// "UNLOCKED · DAY 12".
  String get unlockedLabel => 'UNLOCKED · DAY $dayNumber';

  String get tagline => 'Consistency beats intensity.';

  String get fileName => 'nextrep-achievement-${shareFileSlug(title)}.png';

  String get shareText => 'Achievement unlocked: $title — NextRep';

  String get semanticsLabel => [
    'Achievement card',
    title,
    description,
    'Unlocked on Day $dayNumber',
  ].join('. ');
}

/// [value] as a safe file-name piece: lower-case ASCII letters and digits
/// joined by single hyphens, at most 40 characters ("Cold Front" →
/// "cold-front"); "card" if nothing is left.
String shareFileSlug(String value) {
  var slug = value
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  if (slug.length > 40) {
    slug = slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? 'card' : slug;
}
