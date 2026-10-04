import 'habit.dart';
import 'habit_template_catalog.dart';

/// The habits seeded into every fresh setup: the catalogue's starter
/// templates, in catalogue order. The user can switch them on and off,
/// delete them and add more before starting.
abstract final class StarterHabits {
  static final List<HabitTemplate> all = [
    for (final template in HabitTemplateCatalog.all)
      if (template.starter) template,
  ];

  static List<Habit> seed(DateTime createdAt) => [
    for (final (index, template) in all.indexed)
      template.toHabit(sortOrder: index, createdAt: createdAt),
  ];
}
