import 'habit_config.dart';
import 'night_time.dart';

export 'night_time.dart';

/// How a habit's daily progress is measured. Persisted by [name], so never
/// rename values.
enum HabitType {
  /// Done / not done. Target is always 1.
  binary,

  /// A whole-number quantity, e.g. glasses of water.
  count,

  /// Minutes spent.
  duration,

  /// A clock time recorded once a day, done when it is at or before the
  /// target time (e.g. Sleep Before Target). Target and value are
  /// normalized [NightTime] values; 0 means not logged. The Minimum Day
  /// target is always the normal target.
  timeBefore;

  /// Amount added or removed by one increment / decrement of a numeric
  /// habit. A [timeBefore] habit has no steps; its pickers move in
  /// [NightTime] minutes.
  int get step => switch (this) {
    HabitType.binary => 1,
    HabitType.count => 1,
    HabitType.duration => 5,
    HabitType.timeBefore => 1,
  };

  /// Counted up and down towards a target (count, duration).
  bool get isNumeric => this == HabitType.count || this == HabitType.duration;

  /// Recorded as a clock time ([timeBefore]).
  bool get isClockTime => this == HabitType.timeBefore;

  /// Whether a day with progress [value] against effective [target] is
  /// complete. The single authority on completion for every type:
  ///
  /// * binary, count, duration: the value reached the target
  /// * timeBefore: a time was logged and it is at or before the target
  bool isCompletedBy(int value, int target) => switch (this) {
    HabitType.binary ||
    HabitType.count ||
    HabitType.duration => value >= target,
    HabitType.timeBefore => NightTime.isValidValue(value) && value <= target,
  };
}

/// A habit the user tracks during a Winter Arc session.
///
/// [target], [minimumTarget] and [enabled] are the habit's **baseline**
/// configuration: what was chosen during setup and applies from Day 1. Edits
/// made after the arc starts are stored as dated [HabitRevision]s instead, so
/// past days keep the configuration they actually had. Use
/// [HabitHistory.configOn] to get the configuration for a date.
final class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.minimumTarget,
    required this.iconKey,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    this.unit,
  }) : assert(target > 0, 'target must be positive'),
       assert(
         minimumTarget > 0 && minimumTarget <= target,
         'minimum target must be within 1..target',
       ),
       assert(type != HabitType.binary || target == 1, 'binary target is 1'),
       assert(
         type != HabitType.timeBefore ||
             (minimumTarget == target &&
                 target >= NightTime.minValue &&
                 target <= NightTime.maxValue),
         'a clock-time habit has a night-time target, also on Minimum Days',
       );

  /// Stable key, unique within a session (e.g. `water`, or
  /// `custom_<32 hex digits>` for a habit the user created). Never derived
  /// from the title.
  final String id;

  /// Display name. Renaming applies everywhere, including past days.
  final String title;
  final HabitType type;

  /// Baseline daily value at which the habit counts as completed.
  final int target;

  /// Baseline target on a Minimum Day.
  final int minimumTarget;

  /// Display unit for numeric habits (e.g. `glasses`, `min`).
  final String? unit;

  /// Presentation hint; the UI maps it to an icon.
  final String iconKey;

  /// Baseline enabled state.
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;

  HabitConfig get baseline => HabitConfig(
    target: target,
    minimumTarget: minimumTarget,
    enabled: enabled,
  );

  Habit copyWith({
    bool? enabled,
    String? title,
    int? target,
    int? minimumTarget,
    String? iconKey,
    int? sortOrder,
  }) => Habit(
    id: id,
    title: title ?? this.title,
    type: type,
    target: target ?? this.target,
    minimumTarget: minimumTarget ?? this.minimumTarget,
    unit: unit,
    iconKey: iconKey ?? this.iconKey,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
  );
}
