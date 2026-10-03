import 'habit.dart';

/// A predefined habit offered during setup.
final class HabitTemplate {
  const HabitTemplate({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.minimumTarget,
    required this.iconKey,
    required this.enabledByDefault,
    this.unit,
  });

  final String id;
  final String title;
  final HabitType type;
  final int target;

  /// Target on a Minimum Day: the essential version of the habit.
  final int minimumTarget;
  final String? unit;
  final String iconKey;
  final bool enabledByDefault;

  Habit toHabit({required int sortOrder, required DateTime createdAt}) => Habit(
    id: id,
    title: title,
    type: type,
    target: target,
    minimumTarget: minimumTarget,
    unit: unit,
    iconKey: iconKey,
    enabled: enabledByDefault,
    sortOrder: sortOrder,
    createdAt: createdAt,
  );
}

/// The starter catalogue seeded into every new session.
abstract final class StarterHabits {
  static const List<HabitTemplate> all = [
    HabitTemplate(
      id: 'workout',
      title: 'Workout',
      type: HabitType.duration,
      target: 30,
      minimumTarget: 10,
      unit: 'min',
      iconKey: 'workout',
      enabledByDefault: true,
    ),
    HabitTemplate(
      id: 'water',
      title: 'Water Intake',
      type: HabitType.count,
      target: 8,
      minimumTarget: 3,
      unit: 'glasses',
      iconKey: 'water',
      enabledByDefault: true,
    ),
    HabitTemplate(
      id: 'learning',
      title: 'Learning / Skills',
      type: HabitType.duration,
      target: 20,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'learning',
      enabledByDefault: true,
    ),
    HabitTemplate(
      id: 'english',
      title: 'English Practice',
      type: HabitType.duration,
      target: 10,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'english',
      enabledByDefault: false,
    ),
    HabitTemplate(
      id: 'no_junk_food',
      title: 'No Junk Food',
      type: HabitType.binary,
      target: 1,
      minimumTarget: 1,
      iconKey: 'no_junk_food',
      enabledByDefault: true,
    ),
    // Binary for now; a time-threshold habit type can replace it later.
    HabitTemplate(
      id: 'sleep_on_time',
      title: 'Sleep Before Target',
      type: HabitType.binary,
      target: 1,
      minimumTarget: 1,
      iconKey: 'sleep',
      enabledByDefault: false,
    ),
    HabitTemplate(
      id: 'meditation',
      title: 'Meditation / Journal',
      type: HabitType.duration,
      target: 10,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'meditation',
      enabledByDefault: false,
    ),
  ];

  static List<Habit> seed(DateTime createdAt) => [
    for (final (index, template) in all.indexed)
      template.toHabit(sortOrder: index, createdAt: createdAt),
  ];
}
