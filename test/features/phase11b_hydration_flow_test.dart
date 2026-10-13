import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 11B: Hydration Coach in the Reminders settings, and its nudges
/// following Today.
Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FakeReminderScheduler? scheduler,
  Stream<String?>? taps,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    if (scheduler != null)
      reminderSchedulerProvider.overrideWithValue(scheduler),
    if (taps != null) reminderTapsProvider.overrideWithValue(taps),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _textScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _reducedMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the settings list until [finder] is visible.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openReminders(WidgetTester tester) async {
  await clearCelebrations(tester);
  await _tap(tester, find.byTooltip('Reminders'));
  expect(find.byType(ReminderSettingsScreen), findsOneWidget);
}

/// Hydration Coach's switch: the third one, after the daily reminder and
/// the evening reflection.
Finder get _hydrationSwitch => find.descendant(
  of: find.widgetWithText(SwitchListTile, 'Hydration Coach'),
  matching: find.byType(Switch),
);

Future<void> _pickTime(WidgetTester tester, int hour, int minute) async {
  await _tap(tester, find.byIcon(Icons.keyboard_outlined));
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), hour.toString().padLeft(2, '0'));
  await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
  await _tap(tester, find.text('OK'));
}

List<PlannedReminder> _hydration(FakeReminderScheduler scheduler) => [
  for (final r in scheduler.pending)
    if (r.kind == ReminderKind.hydration) r,
];

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TestApp app;
  late FakeReminderScheduler scheduler;

  /// An arc started on Thu 1 Oct 2026, the clock at 07:00 on Day 1.
  Future<void> seed({Future<void> Function()? setup}) async {
    // Predictable time pickers: 24-hour text entry.
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .alwaysUse24HourFormatTestValue =
        true;
    db = memoryDatabase();
    addTearDown(db.close);
    clock = FakeClock(DateTime(2026, 10, 1, 7));
    scheduler = FakeReminderScheduler();
    app = TestApp(db, clock, scheduler: scheduler);
    await app.winterArc.beginSetup();
    await setup?.call();
    await app.winterArc.startWinterArc();
  }

  testWidgets('the Hydration Coach section is there, off by default, and '
      'explains itself without showing times or a fixed cadence', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await seed();
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, find.text('Active hours'));

    expect(
      find.descendant(
        of: find.byType(ReminderSettingsScreen),
        matching: find.text('Hydration Coach'),
      ),
      findsNWidgets(2), // the heading and the switch
    );
    expect(tester.widget<Switch>(_hydrationSwitch).value, isFalse);
    expect(
      find.text(
        "NextRep checks your Water progress and only nudges you when "
        "you're behind the day's pace.",
      ),
      findsOneWidget,
    );
    expect(find.text('Gentle'), findsOneWidget);
    expect(find.text('Up to 3 nudges a day'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Supportive'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<HydrationMode>>(
            find.byType(RadioGroup<HydrationMode>),
          )
          .groupValue,
      HydrationMode.balanced,
    );
    // 08:00 – 20:00, in the device's clock format.
    expect(
      find.textContaining(RegExp(r'^(08:00|8:00 AM) – (20:00|8:00 PM)$')),
      findsOneWidget,
    );
    expect(find.textContaining('every'), findsNothing);
    expect(find.textContaining('Water goal'), findsNothing);
    expect(
      find.text(
        'Hydration Coach works with the built-in Water habit in your '
        'active Arc.',
      ),
      findsNothing,
    );
    expect(scheduler.pending, isEmpty);
    expect(scheduler.permissionRequests, 0, reason: 'never at startup');
    await _shutDown(tester);
  });

  testWidgets('turning it on asks for permission once and plans nudges; a '
      'denial keeps it off and says why', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, _hydrationSwitch);

    scheduler
      ..granted = false
      ..grant = false;
    await _tap(tester, _hydrationSwitch);
    expect(
      find.textContaining("Notifications weren't allowed"),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(_hydrationSwitch).value, isFalse);
    expect(scheduler.permissionRequests, 1);
    expect(_hydration(scheduler), isEmpty);
    expect((await app.reminderStore.load()).hydrationEnabled, isFalse);

    // The style can still be chosen while it is off.
    await _reveal(tester, find.text('Gentle'));
    await _tap(tester, find.text('Gentle'));
    expect(
      (await app.reminderStore.load()).hydrationMode,
      HydrationMode.gentle,
    );

    scheduler.grant = true;
    await _reveal(tester, _hydrationSwitch);
    await _tap(tester, _hydrationSwitch);
    expect(scheduler.permissionRequests, 2);
    expect(tester.widget<Switch>(_hydrationSwitch).value, isTrue);
    expect(_hydration(scheduler), hasLength(7 * 3));
    await _shutDown(tester);
  });

  testWidgets('Gentle, Balanced and Supportive change the daily maximum', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await seed();
    scheduler.granted = true;
    await app.reminders.update((p) => p.copyWith(hydrationEnabled: true));
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);

    for (final (label, mode, count) in [
      ('Supportive', HydrationMode.supportive, 5),
      ('Gentle', HydrationMode.gentle, 3),
      ('Balanced', HydrationMode.balanced, 4),
    ]) {
      await _reveal(tester, find.text(label));
      await _tap(tester, find.text(label));
      expect((await app.reminderStore.load()).hydrationMode, mode);
      final today = _hydration(scheduler)
          .where((r) => LocalDate.fromDateTime(r.at) == LocalDate(2026, 10, 1));
      expect(today, hasLength(count), reason: label);
    }
    await _shutDown(tester);
  });

  testWidgets('active hours: a valid window is saved; an invalid one is '
      'explained and nothing changes', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, find.text('Active hours'));

    await _tap(tester, find.text('Active hours'));
    expect(find.text('Active from'), findsOneWidget);
    await _pickTime(tester, 7, 30);
    expect(find.text('Active until'), findsOneWidget);
    await _pickTime(tester, 21, 0);
    expect(find.text('07:30 – 21:00'), findsOneWidget);
    expect(
      (await app.reminderStore.load()).hydrationWindow,
      HydrationWindow(const ReminderTime(7, 30), const ReminderTime(21, 0)),
    );

    // Overnight, then too short: both rejected.
    for (final (start, end) in [((22, 0), (6, 0)), ((9, 0), (16, 0))]) {
      await _tap(tester, find.text('Active hours'));
      await _pickTime(tester, start.$1, start.$2);
      await _pickTime(tester, end.$1, end.$2);
      expect(
        find.textContaining('last between 8 and 18 hours'),
        findsOneWidget,
      );
      expect(find.text('07:30 – 21:00'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ReminderSettingsScreen)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    expect(
      (await app.reminderStore.load()).hydrationWindow,
      HydrationWindow(const ReminderTime(7, 30), const ReminderTime(21, 0)),
    );

    // Cancelling the second picker saves nothing either.
    await _tap(tester, find.text('Active hours'));
    await _pickTime(tester, 6, 0);
    await _tap(tester, find.text('Cancel'));
    expect(find.text('07:30 – 21:00'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('without the built-in Water habit it explains why and can\'t '
      'be turned on, even with a custom habit called "Water"', (tester) async {
    await _setPhoneSize(tester);
    await seed(
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
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, find.text('Active hours'));
    expect(
      find.text(
        'Hydration Coach works with the built-in Water habit in your '
        'active Arc.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(_hydrationSwitch).onChanged, isNull);
    expect(scheduler.permissionRequests, 0);
    await _shutDown(tester);
  });

  testWidgets('a renamed built-in Water habit is still recognised', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await seed();
    await app.tracking.editHabit(
      habitId: 'water',
      edit: const HabitEdit(title: 'Morning Hydration'),
      date: LocalDate(2026, 10, 1),
    );
    scheduler.granted = true;
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, _hydrationSwitch);
    expect(find.textContaining('works with the built-in Water'), findsNothing);
    await _tap(tester, _hydrationSwitch);
    expect(_hydration(scheduler), hasLength(7 * 4));
    await _shutDown(tester);
  });

  testWidgets('settings survive a restart', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    scheduler.granted = true;
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    await _reveal(tester, find.text('Supportive'));
    await _tap(tester, find.text('Supportive'));
    await _reveal(tester, _hydrationSwitch);
    await _tap(tester, _hydrationSwitch);
    await _shutDown(tester);

    // A new app over the same database.
    final restarted = FakeReminderScheduler(granted: true);
    await tester.pumpWidget(_app(db, clock, scheduler: restarted));
    await tester.pumpAndSettle();
    expect(
      _hydration(restarted),
      hasLength(7 * 5),
      reason: 'launch reconciles',
    );
    await _openReminders(tester);
    await _reveal(tester, find.text('Active hours'));
    expect(tester.widget<Switch>(_hydrationSwitch).value, isTrue);
    expect(
      tester
          .widget<RadioGroup<HydrationMode>>(
            find.byType(RadioGroup<HydrationMode>),
          )
          .groupValue,
      HydrationMode.supportive,
    );
    await _shutDown(tester);
  });

  testWidgets('after a restore the settings are kept and Hydration Coach is '
      'off', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    scheduler.granted = true;
    await app.reminders.update(
      (p) => p.copyWith(
        hydrationEnabled: true,
        hydrationMode: HydrationMode.gentle,
        hydrationWindow: HydrationWindow(
          const ReminderTime(9, 0),
          const ReminderTime(21, 30),
        ),
      ),
    );
    final bytes = (await app.backup.export()).bytes;
    await app.backup.restore(await app.backup.inspect(bytes));
    expect(scheduler.pending, isEmpty);

    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    expect(scheduler.pending, isEmpty, reason: 'launch plans nothing');
    await _openReminders(tester);
    await _reveal(tester, find.text('Active hours'));
    expect(tester.widget<Switch>(_hydrationSwitch).value, isFalse);
    expect(find.text('09:00 – 21:30'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<HydrationMode>>(
            find.byType(RadioGroup<HydrationMode>),
          )
          .groupValue,
      HydrationMode.gentle,
    );
    await _shutDown(tester);
  });

  testWidgets('logging Water on Today re-plans nudges straight away, both '
      'ways', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    scheduler.granted = true;
    await app.reminders.update((p) => p.copyWith(hydrationEnabled: true));
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    List<int> todayIds() => [
      for (final r in _hydration(scheduler))
        if (LocalDate.fromDateTime(r.at) == LocalDate(2026, 10, 1)) r.id,
    ];
    expect(todayIds(), [300, 301, 302, 303]);

    final add = find.byTooltip('Add to Water Intake');
    await reveal(tester, add);
    for (var i = 0; i < 8; i++) {
      await tester.tap(add);
      await tester.pumpAndSettle();
    }
    expect(todayIds(), isEmpty, reason: 'target complete');

    await clearCelebrations(tester);
    final decrease = find.byTooltip('Decrease Water Intake');
    await reveal(tester, decrease);
    for (var i = 0; i < 4; i++) {
      await tester.tap(decrease);
      await tester.pumpAndSettle();
    }
    // 4 of 8; the log just now skips nothing here (the next checkpoint is
    // hours away), so the 6- and 8-glass checkpoints return.
    expect(todayIds(), [302, 303]);
    await _shutDown(tester);
  });

  testWidgets('a hydration notification opens Today', (tester) async {
    await _setPhoneSize(tester);
    await seed();
    final taps = StreamController<String?>.broadcast();
    addTearDown(taps.close);
    await tester.pumpWidget(_app(db, clock, taps: taps.stream));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    await _openReminders(tester);
    taps.add(ReminderKind.hydration.payload);
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(ReminderSettingsScreen), findsNothing);
    await _shutDown(tester);
  });

  testWidgets('usable at 2× text and with reduced motion', (tester) async {
    await _setPhoneSize(tester);
    _textScale(tester, 2);
    _reducedMotion(tester);
    await seed();
    scheduler.granted = true;
    await tester.pumpWidget(_app(db, clock, scheduler: scheduler));
    await tester.pumpAndSettle();
    await _openReminders(tester);
    for (final finder in [
      _hydrationSwitch,
      find.text('Gentle'),
      find.text('Supportive'),
      find.text('Active hours'),
    ]) {
      await _reveal(tester, finder);
      expect(tester.takeException(), isNull);
    }
    await _reveal(tester, find.text('Supportive'));
    await _tap(tester, find.text('Supportive'));
    await _reveal(tester, _hydrationSwitch);
    await _tap(tester, _hydrationSwitch);
    expect(tester.widget<Switch>(_hydrationSwitch).value, isTrue);
    expect(_hydration(scheduler), hasLength(7 * 5));
    // One accessible control for the hours.
    await _reveal(tester, find.text('Active hours'));
    expect(
      find.bySemanticsLabel('Active hours, 08:00 – 20:00'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _shutDown(tester);
  });
}
