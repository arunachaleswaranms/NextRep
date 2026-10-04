import '../../domain/journey/arc_milestones.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

/// What the winter scene shows, derived deterministically from the
/// challenge-day position (the world's stage) and from persisted day
/// results (how warm and lit it is).
///
/// Purely visual: nothing here feeds back into business rules, and the
/// world never holds back the user's current stage because of missed days.
final class SceneProgress {
  const SceneProgress._({
    required this.dayNumber,
    required this.totalDays,
    required this.milestone,
    required this.warmth,
    required this.recovery,
    required this.dayCompletion,
  });

  /// The scene for challenge day [dayNumber], clamped to the arc.
  ///
  /// [dayCompletion] (`0..1`), [perfect] and [minimum] describe today's
  /// persisted result and only change the light: a Perfect Day warms the
  /// world, a Minimum Day gives it a softer recovery tint.
  factory SceneProgress({
    required int dayNumber,
    int totalDays = WinterArcRules.lengthInDays,
    double dayCompletion = 0,
    bool perfect = false,
    bool minimum = false,
  }) {
    final day = dayNumber.clamp(1, totalDays);
    final completion = dayCompletion.clamp(0.0, 1.0);
    return SceneProgress._(
      dayNumber: day,
      totalDays: totalDays,
      milestone: ArcMilestone.forDay(day),
      dayCompletion: completion,
      warmth: perfect ? 1.0 : completion * 0.6,
      recovery: minimum,
    );
  }

  /// The finished arc: the summit fully revealed and warm.
  factory SceneProgress.summit() =>
      SceneProgress(dayNumber: WinterArcRules.lengthInDays, perfect: true);

  /// This scene with [warmth] instead, e.g. while the light animates
  /// towards a new value.
  SceneProgress withWarmth(double warmth) => SceneProgress._(
    dayNumber: dayNumber,
    totalDays: totalDays,
    milestone: milestone,
    warmth: warmth.clamp(0.0, 1.0),
    recovery: recovery,
    dayCompletion: dayCompletion,
  );

  /// Challenge day shown, `1..totalDays`.
  final int dayNumber;
  final int totalDays;
  final ArcMilestone milestone;

  /// Today's completed share, `0..1`.
  final double dayCompletion;

  /// How warm the light is, `0..1`: grows with today's completion and is
  /// full on a Perfect Day.
  final double warmth;

  /// Today is a Minimum Day: warm recovery tint instead of celebration.
  final bool recovery;

  /// How far along the trail, `0..1` (Day 1 is 0, the last day is 1).
  double get journey => totalDays <= 1 ? 1 : (dayNumber - 1) / (totalDays - 1);

  bool _reached(ArcMilestone m) => m.reachedBy(dayNumber);

  /// Day 7: the first camp and its warm light.
  bool get campLit => _reached(ArcMilestone.firstCamp);

  /// Day 14: the forest camp has grown.
  bool get forestCamp => _reached(ArcMilestone.forestCamp);

  /// Day 30: the mountain ridge has come out of the fog.
  bool get ridgeVisible => _reached(ArcMilestone.ridge);

  /// Day 60: the high ridge, with the summit clearer.
  bool get highRidge => _reached(ArcMilestone.highRidge);

  /// Aurora strength, `0..1`. None before Day 45, then restrained.
  double get aurora => switch (milestone) {
    ArcMilestone.frozenTrail ||
    ArcMilestone.firstCamp ||
    ArcMilestone.forestCamp ||
    ArcMilestone.ridge => 0,
    ArcMilestone.aurora => 0.55,
    ArcMilestone.highRidge => 0.7,
    ArcMilestone.summitShelter => 0.8,
    ArcMilestone.summit => 1,
  };

  /// How clearly the summit shows through the fog, `0..1`.
  double get summitReveal => switch (milestone) {
    ArcMilestone.frozenTrail => 0.25,
    ArcMilestone.firstCamp => 0.3,
    ArcMilestone.forestCamp => 0.35,
    ArcMilestone.ridge => 0.5,
    ArcMilestone.aurora => 0.6,
    ArcMilestone.highRidge => 0.75,
    ArcMilestone.summitShelter => 0.88,
    ArcMilestone.summit => 1,
  };

  /// Glow of the summit shelter, `0..1`. From Day 75; full at the summit.
  double get shelterGlow => switch (milestone) {
    ArcMilestone.summitShelter => 0.6,
    ArcMilestone.summit => 1,
    _ => 0,
  };

  /// Day 92: the summit is fully revealed.
  bool get summitRevealed => milestone == ArcMilestone.summit;

  @override
  bool operator ==(Object other) =>
      other is SceneProgress &&
      other.dayNumber == dayNumber &&
      other.totalDays == totalDays &&
      other.warmth == warmth &&
      other.recovery == recovery &&
      other.dayCompletion == dayCompletion;

  @override
  int get hashCode =>
      Object.hash(dayNumber, totalDays, warmth, recovery, dayCompletion);
}
