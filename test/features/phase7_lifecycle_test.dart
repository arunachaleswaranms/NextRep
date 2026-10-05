import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/backup_files.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/journal/journal_screen.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 7 release hardening: the app moves to the new day while it stays
/// open, closes an arc that ended at midnight without a resume, and every
/// failure has a way forward. All dates come from the injected clock; the
/// device clock is never read or changed.
Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FakeReminderScheduler? scheduler,
  BackupFiles? files,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    if (scheduler != null)
      reminderSchedulerProvider.overrideWithValue(scheduler),
    if (files != null) backupFilesProvider.overrideWithValue(files),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets [wait] pass in the test's fake time while the clock moves with it,
/// as if the phone stayed on the screen.
Future<void> _stayOpen(
  WidgetTester tester,
  FakeClock clock,
  Duration wait,
) async {
  clock.advance(wait);
  await tester.pump(wait);
  await tester.pumpAndSettle();
}

/// A rolling arc started on 1 Jul 2026 (Day 92 is 30 Sep), with the clock
/// left at [day] [time].
Future<TestApp> _rollingArcOn(
  AppDatabase db,
  int day, {
  int hour = 23,
  int minute = 59,
  int second = 50,
}) async {
  final clock = FakeClock(DateTime(2026, 7, 1, 8));
  final app = TestApp(db, clock);
  await app.winterArc.beginSetup();
  await app.winterArc.startWinterArc();
  clock.current = DateTime(2026, 7, day, hour, minute, second);
  return app;
}

/// A system file picker that fails (e.g. the document UI is unavailable).
final class _FailingPicker implements BackupFiles {
  @override
  Future<Uint8List?> pick() async => throw StateError('picker unavailable');

  @override
  Future<bool> save(String fileName, Uint8List bytes) async => false;
}

void main() {
  group('midnight with the app open', () {
    testWidgets('Today moves to the next day without a tap or a resume', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      expect(find.text('Day 5 of 92'), findsOneWidget);

      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      expect(find.text('Day 6 of 92'), findsOneWidget);
      expect(find.text('Day 5 of 92'), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('a rolling arc that ends at midnight opens its summary', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 92); // 1 Jul + 91 = 30 Sep
      app.clock.current = DateTime(2026, 9, 30, 23, 59, 50);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      expect(find.text('Day 92 of 92'), findsOneWidget);

      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
      final arc = (await app.sessions.listSessions()).single;
      expect(arc.status, WinterArcStatus.completed);
      await _shutDown(tester);
    });

    testWidgets('a tap after midnight on Day 92 closes the arc instead of '
        'leaving a dead Today', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 92);
      app.clock.current = DateTime(2026, 9, 30, 23, 59, 50);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();

      // The date changes, but the midnight tick hasn't run yet.
      app.clock.current = DateTime(2026, 10, 1, 0, 0, 2);
      await reveal(tester, find.byTooltip('Complete No Junk Food'));
      await _tap(tester, find.byTooltip('Complete No Junk Food'));
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      // Nothing was written to the day after the arc.
      final arc = (await app.sessions.listSessions()).single;
      expect(arc.status, WinterArcStatus.completed);
      expect(
        await app.progress.progressOn(arc.id, LocalDate(2026, 10, 1)),
        isEmpty,
      );
      await _shutDown(tester);
    });

    testWidgets('the Seasonal Winter Arc closes at Dec 31 → Jan 1', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = TestApp(db, FakeClock(DateTime(2026, 10, 1, 9)));
      await joinSeason(app, DateTime(2026, 10, 10));
      app.clock.current = DateTime(2026, 12, 31, 23, 59, 50);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      expect(find.text('Day 92 of 92'), findsOneWidget);

      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('SEASONAL WINTER ARC COMPLETE'), findsOneWidget);
      // The season keeps its own dates; it never rolls into next year.
      final arc = (await app.sessions.listSessions()).single;
      expect(arc.endDate.toString(), '2026-12-31');
      await _shutDown(tester);
    });

    testWidgets('a preseason setup left open becomes joinable at Oct 1', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 9, 30, 23, 59, 50));
      final app = TestApp(db, clock);
      await app.winterArc.startNewArc(
        NewArcBaseline.fresh,
        kind: ArcKind.seasonalWinter,
      );
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      FilledButton join() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Join Seasonal Winter Arc'),
      );
      expect(join().onPressed, isNull);
      expect(
        find.text('Season starts October 1. Your setup is saved until then.'),
        findsOneWidget,
      );

      await _stayOpen(tester, clock, const Duration(seconds: 15));
      expect(join().onPressed, isNotNull);
      await _shutDown(tester);
    });

    testWidgets('a setup that outlived its season says so on Jan 1', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 9, 20, 9));
      final app = TestApp(db, clock);
      await app.winterArc.startNewArc(
        NewArcBaseline.fresh,
        kind: ArcKind.seasonalWinter,
      );
      clock.current = DateTime(2027, 1, 1, 9);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(
        find.text(
          'This season has ended. Cancel this setup to choose a new Arc.',
        ),
        findsOneWidget,
      );
      await _shutDown(tester);
    });

    testWidgets('a reflection saved just after midnight says the day moved '
        'on, not that it is read-only', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Journal'),
        ),
      );
      expect(find.byType(JournalScreen), findsOneWidget);
      await _tap(tester, find.bySemanticsLabel('Mood: Good'));

      app.clock.current = DateTime(2026, 7, 6, 0, 0, 2);
      await tester.ensureVisible(find.text('Save Reflection'));
      await _tap(tester, find.text('Save Reflection'));
      expect(find.text("It's a new day — Today has been refreshed."), findsOne);
      expect(
        find.text(
          'Past reflections are kept as they were. Only today can be edited.',
        ),
        findsNothing,
      );
      await _shutDown(tester);
    });
  });

  group('failures always have a way forward', () {
    testWidgets('an arc that is no longer on the device offers Go home', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5, hour: 9, minute: 0, second: 0);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();

      GoRouter.of(tester.element(find.byType(TodayScreen))).go('/arc/999');
      await tester.pumpAndSettle();
      expect(
        find.text('This Winter Arc is no longer on this device.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      await _tap(tester, find.text('Go home'));
      expect(find.byType(TodayScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('an unknown page shows a calm page, never exception text', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5, hour: 9, minute: 0, second: 0);
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();

      GoRouter.of(tester.element(find.byType(TodayScreen))).go('/nowhere');
      await tester.pumpAndSettle();
      expect(find.text("That page isn't available."), findsOneWidget);
      expect(find.textContaining('GoException'), findsNothing);
      expect(find.textContaining('/nowhere'), findsNothing);
      await _tap(tester, find.text('Go home'));
      expect(find.byType(TodayScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('a failing permission check still shows the reminder '
        'settings, so reminders can be turned off', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5, hour: 9, minute: 0, second: 0);
      final scheduler = FakeReminderScheduler(granted: true)
        ..failPermissionCheck = true;
      await tester.pumpWidget(_app(db, app.clock, scheduler: scheduler));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Reminders'));
      expect(find.byType(ReminderSettingsScreen), findsOneWidget);
      expect(find.text('Daily reminder'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
      await _shutDown(tester);
    });

    testWidgets('a scheduler failure after saving says the preference was '
        'saved', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5, hour: 9, minute: 0, second: 0);
      final scheduler = FakeReminderScheduler(granted: true);
      await tester.pumpWidget(_app(db, app.clock, scheduler: scheduler));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Reminders'));
      scheduler.failSchedule = true;
      await _tap(tester, find.byType(Switch).first);
      expect(
        find.textContaining("Saved. Reminders couldn't be scheduled"),
        findsOneWidget,
      );
      expect(
        (await app.reminderStore.load()).dailyEnabled,
        isTrue,
        reason: 'the preference is stored; the next launch schedules it',
      );
      await _shutDown(tester);
    });

    testWidgets('an OS-revoked permission is explained and the preference '
        'is kept', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _rollingArcOn(db, 5, hour: 9, minute: 0, second: 0);
      final scheduler = FakeReminderScheduler(granted: true);
      final services = TestApp(db, app.clock, scheduler: scheduler);
      await services.reminders.update((p) => p.copyWith(dailyEnabled: true));
      scheduler.granted = false; // revoked in system settings
      await tester.pumpWidget(_app(db, app.clock, scheduler: scheduler));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Reminders'));
      expect(
        find.textContaining(
          'Notifications are turned off for NextRep in '
          'system settings',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(scheduler.permissionRequests, 0, reason: 'never re-prompted');
      expect((await services.reminderStore.load()).dailyEnabled, isTrue);
      await _shutDown(tester);
    });

    testWidgets('a picker that fails is not blamed on the file', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 10, 5, 9));
      await tester.pumpWidget(_app(db, clock, files: _FailingPicker()));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Restore from a backup'));
      await _tap(tester, find.bySemanticsLabel(RegExp(r'^Restore Backup\.')));
      expect(find.text("Couldn't open the file"), findsOneWidget);
      expect(find.text("Can't use this file"), findsNothing);
      expect(find.textContaining('picker unavailable'), findsNothing);
      await _tap(tester, find.text('OK'));
      await _shutDown(tester);
    });
  });
}
