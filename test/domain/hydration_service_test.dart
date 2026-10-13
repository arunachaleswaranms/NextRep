import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_reminder_preferences_repository.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reminder/hydration_planner.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/reminder/reminder_service.dart';

import '../support/fakes.dart';

/// Hydration Coach through the real services and Drift storage: what is
/// pending after each change the user can make.
void main() {
  late TestApp app;
  late FakeReminderScheduler scheduler;

  // Day 1 is Thu 1 Oct 2026; the clock starts at 07:00, before the window.
  Future<void> startArc({Future<void> Function()? setup, DateTime? at}) async {
    scheduler = FakeReminderScheduler(granted: true);
    app = TestApp(
      memoryDatabase(),
      FakeClock(at ?? DateTime(2026, 10, 1, 7)),
      scheduler: scheduler,
    );
    addTearDown(app.db.close);
    await app.winterArc.beginSetup();
    await setup?.call();
    await app.winterArc.startWinterArc();
  }

  Future<ReminderUpdate> enableHydration({
    HydrationMode mode = HydrationMode.balanced,
  }) => app.reminders.update(
    (p) => p.copyWith(hydrationEnabled: true, hydrationMode: mode),
  );

  LocalDate today() => app.clock.today();

  List<PlannedReminder> hydrationToday() => [
    for (final r in scheduler.pending)
      if (r.kind == ReminderKind.hydration &&
          LocalDate.fromDateTime(r.at) == today())
        r,
  ];

  List<PlannedReminder> hydration() => [
    for (final r in scheduler.pending)
      if (r.kind == ReminderKind.hydration) r,
  ];

  Future<void> water(HabitAction action, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await app.tracking.perform(
        habitId: 'water',
        action: action,
        date: today(),
      );
    }
    // What the app does after every persisted change to the arc.
    await app.reminders.reconcile();
  }

  List<HydrationCheckpoint> checkpoints(LocalDate date, int target) =>
      HydrationPlanner.checkpointsFor(
        date: date,
        target: target,
        mode: HydrationMode.balanced,
        window: HydrationWindow.defaults,
      );

  group('turning it on', () {
    test('off by default: nothing hydration-related is pending', () async {
      await startArc();
      await app.reminders.reconcile();
      expect(scheduler.pending, isEmpty);
      expect((await app.reminderStore.load()).hydrationEnabled, isFalse);
    });

    test('on asks for permission, then plans 7 days against Water', () async {
      await startArc();
      scheduler.granted = false;
      expect(await enableHydration(), ReminderUpdate.saved);
      expect(scheduler.permissionRequests, 1);
      expect(hydration(), hasLength(7 * 4));
      expect(hydrationToday(), hasLength(4));
    });

    test('permission denied: nothing saved, nothing pending, the app works, '
        'and the style and hours can still be set', () async {
      await startArc();
      scheduler
        ..granted = false
        ..grant = false;
      expect(await enableHydration(), ReminderUpdate.permissionDenied);
      expect((await app.reminderStore.load()).hydrationEnabled, isFalse);
      expect(scheduler.pending, isEmpty);

      final window = HydrationWindow(
        const ReminderTime(9, 0),
        const ReminderTime(21, 0),
      );
      expect(
        await app.reminders.update(
          (p) => p.copyWith(
            hydrationMode: HydrationMode.gentle,
            hydrationWindow: window,
          ),
        ),
        ReminderUpdate.saved,
      );
      expect(scheduler.permissionRequests, 1, reason: 'no second prompt');
      final stored = await app.reminderStore.load();
      expect(stored.hydrationMode, HydrationMode.gentle);
      expect(stored.hydrationWindow, window);
      expect(stored.hydrationEnabled, isFalse);
    });

    test('settings survive a restart', () async {
      await startArc();
      final window = HydrationWindow(
        const ReminderTime(7, 30),
        const ReminderTime(22, 0),
      );
      await app.reminders.update(
        (p) => p.copyWith(
          hydrationEnabled: true,
          hydrationMode: HydrationMode.supportive,
          hydrationWindow: window,
        ),
      );
      final reloaded = await DriftReminderPreferencesRepository(app.db).load();
      expect(reloaded.hydrationEnabled, isTrue);
      expect(reloaded.hydrationMode, HydrationMode.supportive);
      expect(reloaded.hydrationWindow, window);
    });

    test('each mode caps the day', () async {
      await startArc();
      for (final (mode, count) in [
        (HydrationMode.gentle, 3),
        (HydrationMode.balanced, 4),
        (HydrationMode.supportive, 5),
      ]) {
        await enableHydration(mode: mode);
        expect(hydrationToday(), hasLength(count), reason: mode.name);
      }
    });

    test(
      'turning it off removes every hydration nudge and nothing else',
      () async {
        await startArc();
        await app.reminders.update(
          (p) => p.copyWith(dailyEnabled: true, hydrationEnabled: true),
        );
        expect(hydration(), isNotEmpty);
        await app.reminders.update((p) => p.copyWith(hydrationEnabled: false));
        expect(hydration(), isEmpty);
        expect(
          scheduler.pending.where((r) => r.kind == ReminderKind.daily),
          hasLength(ReminderPlanner.horizonDays),
        );
      },
    );
  });

  group('logging Water', () {
    test('ahead of pace suppresses, complete clears today, an undo below '
        'the target brings future checkpoints back', () async {
      await startArc();
      await enableHydration();
      expect(hydrationToday(), hasLength(4));

      await water(HabitAction.increment, times: 5);
      // 5 of 8 meets the first two checkpoints (2 and 4).
      expect(hydrationToday().map((r) => r.id), [302, 303]);

      await water(HabitAction.increment, times: 3);
      expect(hydrationToday(), isEmpty, reason: 'target complete');
      expect(hydration(), hasLength(6 * 4), reason: 'tomorrow on');

      await water(HabitAction.decrement, times: 4);
      // 4 of 8: the 6- and 8-glass checkpoints are behind pace again.
      expect(hydrationToday().map((r) => r.id), [302, 303]);
    });

    test('a checkpoint within 45 minutes of a log is skipped', () async {
      final first = checkpoints(LocalDate(2026, 10, 1), 8).first.at;
      await startArc(at: first.subtract(const Duration(minutes: 20)));
      await enableHydration();
      expect(hydrationToday().first.id, 300);

      await water(HabitAction.increment);
      expect(hydrationToday().map((r) => r.id), [301, 302, 303]);

      // An hour later the same log no longer counts as recent, but the
      // checkpoint has passed by then and is never recreated.
      app.clock.advance(const Duration(hours: 1));
      await app.reminders.reconcile();
      expect(hydrationToday().map((r) => r.id), [301, 302, 303]);
    });

    test(
      'progress XP and achievements are the ordinary habit path only',
      () async {
        await startArc();
        final xpBefore = await app.progress.totalXp(1);
        await enableHydration();
        await app.reminders.reconcile();
        expect(await app.progress.totalXp(1), xpBefore);
        expect(await app.achievementStore.unlocks(1), isEmpty);
      },
    );
  });

  group('Minimum Day', () {
    test('8 normal, 3 minimum, 3 logged: Minimum Day completes it, and '
        'returning to full targets brings checkpoints back; no progress is '
        'lost', () async {
      await startArc();
      await enableHydration();
      await water(HabitAction.increment, times: 3);
      expect(hydrationToday().map((r) => r.id), [301, 302, 303]);

      await app.tracking.activateMinimumDay(date: today());
      await app.reminders.reconcile();
      expect(hydrationToday(), isEmpty);

      await app.tracking.returnToFullTargets(date: today());
      await app.reminders.reconcile();
      expect(hydrationToday().map((r) => r.id), [301, 302, 303]);
      final progress = await app.progress.progressOn(1, today());
      expect(progress.singleWhere((p) => p.habitId == 'water').currentValue, 3);
    });
  });

  group('habit edits', () {
    test('a new Water goal applies from the next challenge day', () async {
      await startArc();
      await enableHydration();
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 2, minimumTarget: 1),
        date: today(),
      );
      await app.reminders.reconcile();
      final perDay = <LocalDate, int>{};
      for (final r in hydration()) {
        final date = LocalDate.fromDateTime(r.at);
        perDay[date] = (perDay[date] ?? 0) + 1;
      }
      expect(perDay[today()], 4, reason: 'today keeps its goal');
      for (var i = 1; i < 7; i++) {
        expect(perDay[today().addDays(i)], 2);
      }
    });

    test(
      'Water turned off from tomorrow: today only; back on: resumes',
      () async {
        await startArc();
        await enableHydration();
        await app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(enabled: false),
          date: today(),
        );
        await app.reminders.reconcile();
        expect(hydration().map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
          today(),
        });

        app.clock.current = DateTime(2026, 10, 3, 7);
        await app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(enabled: true),
          date: today(),
        );
        await app.reminders.reconcile();
        expect(hydration().map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
          for (var i = 1; i < 7; i++) today().addDays(i),
        });
      },
    );

    test('renamed to "Morning Hydration", Water still counts', () async {
      await startArc();
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(title: 'Morning Hydration'),
        date: today(),
      );
      expect(
        await app.reminders.hydrationAvailability(),
        HydrationAvailability.available,
      );
      await enableHydration();
      expect(hydration(), hasLength(7 * 4));
    });
  });

  group('arcs without the built-in Water habit', () {
    test('a custom habit called "Water" is not Water', () async {
      await startArc(
        setup: () async {
          await app.winterArc.deleteSetupHabit('water');
          await app.winterArc.addCustomHabit(
            const HabitDraft(
              title: 'Water',
              type: HabitType.count,
              iconKey: 'water',
              target: 8,
              minimumTarget: 3,
              unit: 'glasses',
            ),
          );
        },
      );
      expect(
        await app.reminders.hydrationAvailability(),
        HydrationAvailability.noBuiltInWater,
      );
      await enableHydration();
      expect(hydration(), isEmpty);
    });

    test('no arc running', () async {
      scheduler = FakeReminderScheduler(granted: true);
      app = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 10, 1, 7)),
        scheduler: scheduler,
      );
      addTearDown(app.db.close);
      expect(
        await app.reminders.hydrationAvailability(),
        HydrationAvailability.noActiveArc,
      );
      await enableHydration();
      expect(scheduler.pending, isEmpty);
    });
  });

  group('the calendar', () {
    test('local midnight moves "today" to the new date', () async {
      await startArc();
      await enableHydration();
      final tomorrow = today().addDays(1);
      final planned = [
        for (final r in hydration())
          if (LocalDate.fromDateTime(r.at) == tomorrow) r.at,
      ];
      app.clock.current = DateTime(2026, 10, 2, 0, 0, 1);
      await app.reminders.reconcile();
      expect(hydrationToday().map((r) => r.id), [300, 301, 302, 303]);
      expect(hydrationToday().map((r) => r.at), planned);
      expect(
        hydration().map((r) => LocalDate.fromDateTime(r.at)).toSet(),
        hasLength(7),
      );
    });

    test('nothing once the arc is over', () async {
      await startArc();
      await enableHydration();
      app.clock.current = DateTime(2026, 12, 31, 7);
      await app.reminders.reconcile();
      expect(hydration().map((r) => LocalDate.fromDateTime(r.at)).toSet(), {
        LocalDate(2026, 12, 31),
      });
      app.clock.current = DateTime(2027, 1, 1, 7);
      await app.lifecycle.reconcile();
      await app.reminders.reconcile();
      expect(scheduler.pending, isEmpty);
    });
  });

  group('restore', () {
    test('keeps the hours and style, turns Hydration Coach off, and '
        'schedules nothing', () async {
      await startArc();
      final window = HydrationWindow(
        const ReminderTime(6, 45),
        const ReminderTime(19, 15),
      );
      await app.reminders.update(
        (p) => p.copyWith(
          dailyEnabled: true,
          reflectionEnabled: true,
          hydrationEnabled: true,
          hydrationMode: HydrationMode.gentle,
          hydrationWindow: window,
        ),
      );
      expect(hydration(), isNotEmpty);
      final bytes = (await app.backup.export()).bytes;

      final outcome = await app.backup.restore(await app.backup.inspect(bytes));
      expect(outcome.remindersCleared, isTrue);
      expect(scheduler.pending, isEmpty);
      final restored = await app.reminderStore.load();
      expect(restored.dailyEnabled, isFalse);
      expect(restored.reflectionEnabled, isFalse);
      expect(restored.hydrationEnabled, isFalse);
      expect(restored.hydrationMode, HydrationMode.gentle);
      expect(restored.hydrationWindow, window);
      // The app's next reconciliation still plans nothing.
      await app.reminders.reconcile();
      expect(scheduler.pending, isEmpty);
    });
  });
}
