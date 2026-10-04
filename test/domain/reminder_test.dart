import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/reminder/reminder_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/builders.dart';
import '../support/fakes.dart';

void main() {
  group('ReminderPlanner', () {
    const both = ReminderPreferences(
      dailyEnabled: true,
      dailyTime: ReminderTime(8, 30),
      reflectionEnabled: true,
      reflectionTime: ReminderTime(21, 15),
    );

    test('plans nothing without an active arc or with everything off', () {
      final now = DateTime(2026, 10, 1, 7);
      expect(
        ReminderPlanner.plan(preferences: both, active: null, now: now),
        isEmpty,
      );
      expect(
        ReminderPlanner.plan(
          preferences: ReminderPreferences.defaults,
          active: activeSession(),
          now: now,
        ),
        isEmpty,
      );
    });

    test('one reminder per kind and arc day, at the local wall-clock time, '
        'from now on', () {
      // Day 1 at 09:00: today's daily reminder (08:30) has passed.
      final plan = ReminderPlanner.plan(
        preferences: both,
        active: activeSession(),
        now: DateTime(2026, 10, 1, 9),
      );
      final daily = plan.where((r) => r.kind == ReminderKind.daily).toList();
      final evening = plan
          .where((r) => r.kind == ReminderKind.reflection)
          .toList();
      expect(daily.first.at, DateTime(2026, 10, 2, 8, 30));
      expect(daily, hasLength(ReminderPlanner.horizonDays - 1));
      expect(evening.first.at, DateTime(2026, 10, 1, 21, 15));
      expect(evening, hasLength(ReminderPlanner.horizonDays));
      expect(plan.map((r) => r.id).toSet(), hasLength(plan.length));
      expect(daily.first.title, 'Winter Arc · Day 2');
      expect(daily.first.body, 'Your Winter Arc is waiting.');
      expect(daily.first.payload, 'today');
      expect(evening.first.title, 'How did today go?');
      expect(evening.first.payload, 'journal');
    });

    test('never plans past the arc\'s last day', () {
      // Day 90 of the arc: only Day 90–92 are left.
      final plan = ReminderPlanner.plan(
        preferences: both,
        active: activeSession(),
        now: DateTime(2026, 12, 29, 6),
      );
      expect(plan.map((r) => r.at.day).toSet(), {29, 30, 31});
      expect(plan.every((r) => !r.at.isAfter(DateTime(2027))), isTrue);
    });

    test('a completed arc gets nothing', () {
      expect(
        ReminderPlanner.plan(
          preferences: both,
          active: activeSession().copyWith(status: WinterArcStatus.completed),
          now: DateTime(2026, 10, 5),
        ),
        isEmpty,
      );
    });
  });

  group('ReminderService', () {
    late TestApp app;

    setUp(() {
      app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 7)));
    });
    tearDown(() => app.db.close());

    Future<void> startArc() async {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
    }

    test('reminders are off by default and nothing is scheduled', () async {
      await startArc();
      expect(await app.reminders.preferences(), ReminderPreferences.defaults);
      expect(ReminderPreferences.defaults.dailyEnabled, isFalse);
      expect(ReminderPreferences.defaults.reflectionEnabled, isFalse);
      expect(await app.reminders.reconcile(), isEmpty);
      expect(app.scheduler.pending, isEmpty);
      expect(app.scheduler.permissionRequests, 0);
    });

    test('turning the daily reminder on asks for permission, persists, '
        'and schedules', () async {
      await startArc();
      final prefs = ReminderPreferences.defaults.copyWith(dailyEnabled: true);
      expect(await app.reminders.update((_) => prefs), ReminderUpdate.saved);
      expect(app.scheduler.permissionRequests, 1);
      expect(await app.reminderStore.load(), prefs);
      expect(app.scheduler.pending.map((r) => r.kind).toSet(), {
        ReminderKind.daily,
      });
      // 08:00 today is still ahead at 07:00.
      expect(app.scheduler.pending.first.at, DateTime(2026, 10, 1, 8));
    });

    test('turning it off cancels it', () async {
      await startArc();
      final on = ReminderPreferences.defaults.copyWith(dailyEnabled: true);
      await app.reminders.update((_) => on);
      expect(app.scheduler.pending, isNotEmpty);
      await app.reminders.update((_) => on.copyWith(dailyEnabled: false));
      expect(app.scheduler.pending, isEmpty);
      expect((await app.reminderStore.load()).dailyEnabled, isFalse);
    });

    test('two quick edits both land, neither overwrites the other', () async {
      await startArc();
      // Flipped before the first save finished, as two fast taps would.
      final first = app.reminders.update((p) => p.copyWith(dailyEnabled: true));
      final second = app.reminders.update(
        (p) => p.copyWith(reflectionEnabled: true),
      );
      expect(await Future.wait([first, second]), [
        ReminderUpdate.saved,
        ReminderUpdate.saved,
      ]);
      final stored = await app.reminderStore.load();
      expect(stored.dailyEnabled, isTrue);
      expect(stored.reflectionEnabled, isTrue);
      expect(app.scheduler.pending.map((r) => r.kind).toSet(), {
        ReminderKind.daily,
        ReminderKind.reflection,
      });
    });

    test('the reflection reminder persists and schedules on its own', () async {
      await startArc();
      final prefs = ReminderPreferences.defaults.copyWith(
        reflectionEnabled: true,
      );
      await app.reminders.update((_) => prefs);
      expect((await app.reminderStore.load()).reflectionEnabled, isTrue);
      expect(app.scheduler.pending.map((r) => r.kind).toSet(), {
        ReminderKind.reflection,
      });
      expect(app.scheduler.pending.first.at, DateTime(2026, 10, 1, 21));
    });

    test('changing the time reschedules at the new local time', () async {
      await startArc();
      final on = ReminderPreferences.defaults.copyWith(dailyEnabled: true);
      await app.reminders.update((_) => on);
      await app.reminders.update(
        (_) => on.copyWith(dailyTime: const ReminderTime(6, 45)),
      );
      // 06:45 today has passed at 07:00, so the first is tomorrow.
      expect(app.scheduler.pending.first.at, DateTime(2026, 10, 2, 6, 45));
      expect(
        app.scheduler.pending.every((r) => r.at.hour == 6 && r.at.minute == 45),
        isTrue,
      );
      // Permission was only asked for when first turned on.
      expect(app.scheduler.permissionRequests, 1);
    });

    test(
      'no active arc means no reminders, whatever the preferences',
      () async {
        final on = ReminderPreferences.defaults.copyWith(
          dailyEnabled: true,
          reflectionEnabled: true,
        );
        // Before any arc, and while one is in setup.
        await app.reminders.update((_) => on);
        expect(app.scheduler.pending, isEmpty);
        await app.winterArc.beginSetup();
        expect(await app.reminders.reconcile(), isEmpty);
        expect(app.scheduler.pending, isEmpty);
        // The preference is kept for when an arc runs.
        expect((await app.reminderStore.load()).dailyEnabled, isTrue);
      },
    );

    test('a completed arc cancels its reminders; a new active arc brings '
        'them back', () async {
      final on = ReminderPreferences.defaults.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
      );
      await app.reminders.update((_) => on);
      await runFirstArc(app); // leaves the clock on 1 Oct, arc completed
      expect(await app.reminders.reconcile(), isEmpty);
      expect(app.scheduler.pending, isEmpty);

      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      expect(await app.reminders.reconcile(), isEmpty); // setup only
      final arc2 = await app.winterArc.startWinterArc();
      final plan = await app.reminders.reconcile();
      expect(plan, isNotEmpty);
      // Started at 09:00: today's 08:00 nudge has passed, tonight's
      // reflection prompt hasn't.
      final daily = plan.firstWhere((r) => r.kind == ReminderKind.daily);
      expect(daily.title, 'Winter Arc · Day 2');
      expect(daily.at, DateTime(2026, 10, 2, 8));
      final evening = plan.firstWhere((r) => r.kind == ReminderKind.reflection);
      expect(evening.body, 'Take 20 seconds to reflect on Day 1.');
      expect(
        plan.every((r) => !r.at.isBefore(arc2.startDate.toLocalDateTime())),
        isTrue,
      );
      expect(app.scheduler.pending, plan);
    });

    test(
      'a denied permission keeps the reminder off and the app working',
      () async {
        final denied = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, 10, 1, 7)),
          scheduler: FakeReminderScheduler(grant: false),
        );
        addTearDown(denied.db.close);
        await denied.winterArc.beginSetup();
        await denied.winterArc.startWinterArc();
        final on = ReminderPreferences.defaults.copyWith(dailyEnabled: true);
        expect(
          await denied.reminders.update((_) => on),
          ReminderUpdate.permissionDenied,
        );
        expect(await denied.reminderStore.load(), ReminderPreferences.defaults);
        expect(denied.scheduler.pending, isEmpty);
        // Asked once per attempt by the user, never on its own.
        await denied.reminders.reconcile();
        expect(denied.scheduler.permissionRequests, 1);
        // Everything else still works.
        await completeAll(denied);
        expect((await denied.tracking.today()).isPerfect, isTrue);
      },
    );
  });
}
