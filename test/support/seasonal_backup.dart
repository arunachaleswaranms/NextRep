import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'arcs.dart';
import 'fakes.dart';

/// The custom habit of [seasonalSource].
const pagesId = 'custom_0000000000000000000000000000beef';

final class _FixedIds implements HabitIdGenerator {
  @override
  String next() => pagesId;
}

/// Phase 6 data, through the real services:
///
/// * Arc 1: a completed rolling arc (see [runFirstArc]).
/// * Arc 2: this year's Seasonal Winter Arc, reusing Arc 1's habits plus
///   Sleep Before Target (goal 01:00) and a custom "Pages" count habit,
///   joined on 15 Oct (Day 15).
///   * 15 Oct: bedtime 00:45 (done), Pages complete, a reflection.
///   * The sleep goal moves to 00:30 from 16 Oct.
///   * 16 Oct: bedtime 00:45 (logged, late: not done).
/// * Reminder times saved and on.
///
/// Leaves the clock on 16 Oct 2026 at 21:00.
Future<TestApp> seasonalSource() async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 7, 1)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  await runFirstArc(app);
  final service = WinterArcService(
    sessions: app.sessions,
    habits: app.habits,
    clock: app.clock,
    ids: _FixedIds(),
  );
  app.clock.current = DateTime(2026, 10, 15, 8);
  await service.startNewArc(
    NewArcBaseline.reuseLast,
    kind: ArcKind.seasonalWinter,
  );
  await service.setHabitEnabled('sleep_before', enabled: true);
  await service.editSetupHabit(
    'sleep_before',
    HabitDraft(
      title: 'Sleep Before Target',
      type: HabitType.timeBefore,
      iconKey: 'sleep',
      target: NightTime(1, 0).value,
    ),
  );
  await service.addCustomHabit(
    const HabitDraft(
      title: 'Pages',
      type: HabitType.count,
      iconKey: 'learning',
      target: 3,
      minimumTarget: 1,
      unit: 'pages',
    ),
  );
  final arc = await service.startWinterArc();

  Future<void> bedtime(int h, int m) => app.tracking.perform(
    habitId: 'sleep_before',
    action: HabitAction.setTime,
    time: NightTime(h, m),
    date: app.clock.today(),
  );

  await bedtime(0, 45);
  await completeHabit(app, pagesId);
  await app.reflections.save(
    sessionId: arc.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Synthetic win'),
  );
  await app.tracking.editHabit(
    habitId: 'sleep_before',
    edit: HabitEdit(target: NightTime(0, 30).value),
    date: app.clock.today(),
  );
  app.clock.current = DateTime(2026, 10, 16, 8);
  await bedtime(0, 45);
  await app.achievements.reconcile();
  await app.reminders.update(
    (_) => const ReminderPreferences(
      dailyEnabled: true,
      dailyTime: ReminderTime(7, 15),
      reflectionEnabled: true,
      reflectionTime: ReminderTime(22, 30),
    ),
  );
  app.clock.current = DateTime(2026, 10, 16, 21);
  return app;
}
