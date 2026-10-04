import 'habit.dart';
import 'habit_template.dart';

export 'habit_template.dart';

/// The bundled habit templates, in picker order. Code only: nothing is
/// downloaded, nothing is stored.
///
/// Ids are stable and shared with every earlier arc: `workout`, `water`,
/// `learning`, `english`, `no_junk_food` and `meditation` are the Phase 1
/// starter ids. `journal` and `sleep_before` are new in Phase 6.
///
/// The legacy `sleep_on_time` habit (a done / not-done "Sleep Before
/// Target" from Phases 1–5) isn't offered any more, but it isn't migrated
/// either: earlier arcs keep it exactly as it was, and Reuse Last Setup
/// copies it as it is. `sleep_before` is a new id because it is a
/// different habit type, and one id must never mean two types across arcs.
abstract final class HabitTemplateCatalog {
  static final List<HabitTemplate> all = [
    const HabitTemplate(
      id: 'workout',
      title: 'Workout',
      type: HabitType.duration,
      target: 30,
      minimumTarget: 10,
      unit: 'min',
      iconKey: 'workout',
      enabledByDefault: true,
      starter: true,
      description: 'Move your body every day.',
    ),
    const HabitTemplate(
      id: 'water',
      title: 'Water Intake',
      type: HabitType.count,
      target: 8,
      minimumTarget: 3,
      unit: 'glasses',
      iconKey: 'water',
      enabledByDefault: true,
      starter: true,
      description: 'Glasses of water through the day.',
    ),
    const HabitTemplate(
      id: 'learning',
      title: 'Learning / Skills',
      type: HabitType.duration,
      target: 20,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'learning',
      enabledByDefault: true,
      starter: true,
      description: 'Read, study or practise a skill.',
    ),
    const HabitTemplate(
      id: 'english',
      title: 'English Practice',
      type: HabitType.duration,
      target: 10,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'english',
      enabledByDefault: false,
      starter: true,
      description: 'A few minutes of language practice.',
    ),
    const HabitTemplate(
      id: 'no_junk_food',
      title: 'No Junk Food',
      type: HabitType.binary,
      target: 1,
      minimumTarget: 1,
      iconKey: 'no_junk_food',
      enabledByDefault: true,
      starter: true,
      description: 'A clean day of eating.',
    ),
    HabitTemplate(
      id: 'sleep_before',
      title: 'Sleep Before Target',
      type: HabitType.timeBefore,
      target: NightTime(23, 30).value,
      minimumTarget: NightTime(23, 30).value,
      iconKey: 'sleep',
      enabledByDefault: false,
      starter: true,
      description: 'Each morning, log when you went to bed last night.',
    ),
    const HabitTemplate(
      id: 'meditation',
      title: 'Meditation',
      type: HabitType.duration,
      target: 10,
      minimumTarget: 5,
      unit: 'min',
      iconKey: 'meditation',
      enabledByDefault: false,
      starter: true,
      description: 'Sit quietly and breathe.',
    ),
    const HabitTemplate(
      id: 'journal',
      title: 'Journal',
      type: HabitType.binary,
      target: 1,
      minimumTarget: 1,
      iconKey: 'journal',
      enabledByDefault: true,
      description: 'Write a few lines about your day.',
    ),
  ];

  /// The template with [id], or null.
  static HabitTemplate? byId(String id) {
    for (final template in all) {
      if (template.id == id) return template;
    }
    return null;
  }
}
