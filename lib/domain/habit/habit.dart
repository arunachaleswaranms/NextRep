import 'habit_config.dart';

/// How a habit's daily progress is measured. Persisted by [name].
enum HabitType {
  /// Done / not done. Target is always 1.
  binary,

  /// A whole-number quantity, e.g. glasses of water.
  count,

  /// Minutes spent.
  duration;

  /// Amount added or removed by one increment / decrement.
  int get step => switch (this) {
    HabitType.binary => 1,
    HabitType.count => 1,
    HabitType.duration => 5,
  };

  bool get isNumeric => this != HabitType.binary;
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
       assert(type != HabitType.binary || target == 1, 'binary target is 1');

  /// Stable key, unique within a session (e.g. `water`).
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

  Habit copyWith({bool? enabled, String? title}) => Habit(
    id: id,
    title: title ?? this.title,
    type: type,
    target: target,
    minimumTarget: minimumTarget,
    unit: unit,
    iconKey: iconKey,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder,
    createdAt: createdAt,
  );
}
