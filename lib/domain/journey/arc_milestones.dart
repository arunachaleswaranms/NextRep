import '../winter_arc/winter_arc_session.dart';

/// Visual milestones of the Winter Arc world, unlocked by challenge-day
/// position alone.
///
/// They drive what the winter scene shows (camp, ridge, aurora, summit). They
/// are decoration only: no business rule (completion, XP, streaks, levels,
/// achievements) reads them, and missing days never hold the world back.
enum ArcMilestone {
  /// Day 1: the frozen trail begins.
  frozenTrail(1),

  /// Day 7: the first camp and its warm light.
  firstCamp(7),

  /// Day 14: the forest camp grows.
  forestCamp(14),

  /// Day 30: the mountain ridge becomes visible.
  ridge(30),

  /// Day 45: the aurora begins to appear.
  aurora(45),

  /// Day 60: the high ridge, with the summit clearer.
  highRidge(60),

  /// Day 75: the summit shelter starts to glow.
  summitShelter(75),

  /// Day 92: the summit is fully revealed.
  summit(WinterArcRules.lengthInDays);

  const ArcMilestone(this.day);

  /// First challenge day on which this milestone is reached.
  final int day;

  /// The latest milestone reached on [dayNumber]. Days before Day 1 give
  /// [frozenTrail] and days after the arc give [summit], so the result never
  /// leaves the arc.
  static ArcMilestone forDay(int dayNumber) {
    var reached = frozenTrail;
    for (final milestone in values) {
      if (dayNumber >= milestone.day) reached = milestone;
    }
    return reached;
  }

  /// Whether this milestone is reached by [dayNumber].
  bool reachedBy(int dayNumber) => dayNumber >= day;

  /// The milestone after this one, or null at the [summit].
  ArcMilestone? get next =>
      index + 1 < values.length ? values[index + 1] : null;
}

/// Visual chapters of the Journey path. Every challenge day belongs to
/// exactly one chapter; the day number stays authoritative.
enum JourneyChapter {
  frozenForest(1, 14),
  firstAscent(15, 30),
  ridge(31, 45),
  auroraPass(46, 60),
  highMountain(61, 75),
  summitApproach(76, WinterArcRules.lengthInDays);

  const JourneyChapter(this.firstDay, this.lastDay);

  final int firstDay;
  final int lastDay;

  int get length => lastDay - firstDay + 1;

  bool contains(int dayNumber) => dayNumber >= firstDay && dayNumber <= lastDay;

  /// The chapter of [dayNumber], clamped to the arc.
  static JourneyChapter forDay(int dayNumber) {
    for (final chapter in values) {
      if (dayNumber <= chapter.lastDay) return chapter;
    }
    return values.last;
  }
}
