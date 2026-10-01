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
final class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.iconKey,
    required this.enabled,
    required this.sortOrder,
    required this.createdAt,
    this.unit,
  }) : assert(target > 0, 'target must be positive'),
       assert(type != HabitType.binary || target == 1, 'binary target is 1');

  /// Stable key, unique within a session (e.g. `water`).
  final String id;
  final String title;
  final HabitType type;

  /// Daily value at which the habit counts as completed.
  final int target;

  /// Display unit for numeric habits (e.g. `glasses`, `min`).
  final String? unit;

  /// Presentation hint; the UI maps it to an icon.
  final String iconKey;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;

  Habit copyWith({bool? enabled}) => Habit(
    id: id,
    title: title,
    type: type,
    target: target,
    unit: unit,
    iconKey: iconKey,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder,
    createdAt: createdAt,
  );
}
