import 'habit.dart';

/// A predefined habit offered during setup. Templates live in code
/// ([HabitTemplateCatalog]); they are never stored. Adding one creates an
/// ordinary [Habit] whose id is the template's stable [id], so the same
/// habit is recognised across arcs (Insights, Reuse Last Setup).
final class HabitTemplate {
  const HabitTemplate({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.minimumTarget,
    required this.iconKey,
    required this.enabledByDefault,
    this.starter = false,
    this.unit,
    this.description,
  });

  /// Stable habit id. Never reused for a different kind of habit.
  final String id;
  final String title;
  final HabitType type;

  /// Normal target (a normalized [NightTime] value for a clock-time habit).
  final int target;

  /// Target on a Minimum Day: the essential version of the habit. Equal to
  /// [target] for a clock-time habit.
  final int minimumTarget;
  final String? unit;
  final String iconKey;

  /// Whether the habit starts switched on when seeded into a fresh setup.
  final bool enabledByDefault;

  /// Seeded into every fresh setup ([StarterHabits]).
  final bool starter;

  /// One line for the template picker.
  final String? description;

  Habit toHabit({
    required int sortOrder,
    required DateTime createdAt,
    bool? enabled,
  }) => Habit(
    id: id,
    title: title,
    type: type,
    target: target,
    minimumTarget: minimumTarget,
    unit: unit,
    iconKey: iconKey,
    enabled: enabled ?? enabledByDefault,
    sortOrder: sortOrder,
    createdAt: createdAt,
  );
}
