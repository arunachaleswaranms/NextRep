import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_form_sheet.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/new_arc/new_arc_controller.dart';
import 'package:nextrep/features/new_arc/new_arc_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';
import 'package:nextrep/features/today/widgets/time_before_tile.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

Widget _app(AppDatabase db, FakeClock clock) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
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

/// Scrolls the first scrollable until [finder] is on screen, then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await clearCelebrations(tester);
  await _tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
}

/// Enters [hour]:[minute] in the open time picker (24-hour text input).
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

/// Scrolls the open bottom sheet until [finder] is on screen.
Future<void> _revealInSheet(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

Finder _setupTile(String title) => find.widgetWithText(HabitToggleTile, title);

FilledButton _startButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  setUp(() {
    // Predictable time pickers: 24-hour text entry.
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .alwaysUse24HourFormatTestValue =
        true;
  });
  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAlwaysUse24HourTestValue(),
  );

  group('choosing an Arc', () {
    testWidgets('a new user can choose Rolling', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 5, 10, 9))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("Let's Begin"));
      expect(find.byType(NewArcScreen), findsOneWidget);
      expect(find.text('Choose your Arc'), findsOneWidget);
      // May: the season can only be previewed.
      expect(find.text('Preseason opens September 1'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Seasonal Winter Arc\.')),
        findsOneWidget,
      );
      await _tap(tester, find.text('Seasonal Winter Arc'));
      expect(find.byType(NewArcScreen), findsOneWidget, reason: 'disabled');

      await _tap(tester, find.text('Rolling 92-Day Arc'));
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(find.text('Rolling 92-Day'), findsOneWidget);
      expect(_startButton(tester, 'Start Winter Arc').onPressed, isNotNull);
      await _shutDown(tester);
    });

    testWidgets('preseason: Seasonal is set up for 1 Oct and cannot start '
        'early', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 9, 10, 9))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("Let's Begin"));
      expect(
        find.text('Preseason · the season starts October 1'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Seasonal Winter Arc'));
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(find.text('Seasonal · 1 Oct – 31 Dec 2026'), findsOneWidget);
      expect(
        find.text('Preseason. The season starts October 1.'),
        findsOneWidget,
      );
      final start = _startButton(tester, 'Join Seasonal Winter Arc');
      expect(start.onPressed, isNull);
      expect(
        find.text('Season starts October 1. Your setup is saved until then.'),
        findsOneWidget,
      );
      await _shutDown(tester);
    });

    testWidgets('in season: a late join opens Today on the season day', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 10, 15, 9))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("Let's Begin"));
      expect(find.text('In season · 2026'), findsOneWidget);
      await _tap(tester, find.text('Seasonal Winter Arc'));
      expect(
        find.textContaining('The season is on Day 15 of 92'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Join Seasonal Winter Arc'));
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Day 15 of 92'), findsOneWidget);
      expect(find.text('Day 1 of 92'), findsNothing);
      expect(find.text('Seasonal Winter Arc · joined Day 15'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('a returning user picks the Arc kind, then reuse or fresh', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 7, 1));
      final app = TestApp(db, clock);
      await runFirstArc(app); // a rolling arc, completed on 1 Oct
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await _tapVisible(tester, find.text('Start New Arc'));
      expect(find.text('New Winter Arc'), findsOneWidget);
      await _tap(tester, find.text('Seasonal Winter Arc'));
      // The baseline is a separate choice.
      expect(find.text('Reuse last setup'), findsOneWidget);
      expect(find.text('Start fresh'), findsOneWidget);
      expect(find.text('October 1 – December 31, 2026.'), findsOneWidget);
      await _tap(tester, find.text('Reuse last setup'));
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(find.text('Seasonal · 1 Oct – 31 Dec 2026'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget, reason: 'reused habits');
      await _shutDown(tester);
    });
  });

  testWidgets('a preseason setup left open becomes joinable on resume '
      'on 1 Oct', (tester) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 9, 30, 22));
    await TestApp(
      db,
      clock,
    ).winterArc.startNewArc(NewArcBaseline.fresh, kind: ArcKind.seasonalWinter);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    expect(_startButton(tester, 'Join Seasonal Winter Arc').onPressed, isNull);

    clock.current = DateTime(2026, 10, 1, 7);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(
      _startButton(tester, 'Join Seasonal Winter Arc').onPressed,
      isNotNull,
    );
    expect(find.textContaining('The season starts today'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('if the reusable habits cannot load, New Arc says so instead '
      'of treating the user as new', (tester) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 4, 9));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          ambientMotionProvider.overrideWithValue(false),
          reusableHabitsProvider.overrideWith(
            (ref) => throw const PersistenceFailure('read failed'),
          ),
        ],
        retry: (_, _) => null,
        child: const NextRepApp(),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text("Let's Begin"));
    expect(find.byType(NewArcScreen), findsOneWidget);
    expect(find.text('Rolling 92-Day Arc'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await _shutDown(tester);
  });

  group('Habit Setup v2', () {
    late AppDatabase db;
    late FakeClock clock;

    setUp(() async {
      db = memoryDatabase();
      clock = FakeClock(DateTime(2026, 10, 4, 9));
      await TestApp(db, clock).winterArc.beginSetup();
    });
    tearDown(() => db.close());

    Future<void> openAddHabit(WidgetTester tester) =>
        _tapVisible(tester, find.text('Add Habit'));

    testWidgets('Add Habit offers templates and Create your own', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await openAddHabit(tester);
      expect(find.text('TEMPLATES'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Water Intake template.*already added')),
        findsOneWidget,
      );
      expect(
        find.text('Count · Goal 8 glasses · Minimum 3 glasses'),
        findsOneWidget,
      );
      await _revealInSheet(tester, find.text('Journal'));
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Done / not done · Daily'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Create your own'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Create your own'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('remove a habit, then add Sleep Before Target back as a '
        'clock-time habit', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      final options = find.byTooltip('Options for Sleep Before Target');
      await _tapVisible(tester, options);
      await _tap(tester, find.text('Remove'));
      expect(_setupTile('Sleep Before Target'), findsNothing);
      expect(find.text('Sleep Before Target removed'), findsOneWidget);

      await openAddHabit(tester);
      final template = find.bySemanticsLabel(
        RegExp(r'^Sleep Before Target template'),
      );
      await _revealInSheet(tester, template);
      await _tap(tester, template);
      expect(find.text('Sleep Before Target added'), findsOneWidget);
      await tester.scrollUntilVisible(
        _setupTile('Sleep Before Target'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: _setupTile('Sleep Before Target'),
          matching: find.text('Before 23:30'),
        ),
        findsOneWidget,
      );
      final habits = await TestApp(db, clock).winterArc.setupHabits();
      expect(
        habits.singleWhere((h) => h.id == 'sleep_before').type,
        HabitType.timeBefore,
      );
      await _shutDown(tester);
    });

    testWidgets('the custom form follows the type and picks a goal time', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await openAddHabit(tester);
      await tester.scrollUntilVisible(
        find.text('Create your own'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await _tap(tester, find.text('Create your own'));

      Finder inForm(String text) => find.descendant(
        of: find.byType(HabitFormSheet),
        matching: find.text(text),
      );
      // Done / not done (default): no numbers.
      expect(inForm('Daily goal'), findsNothing);
      expect(inForm('Goal: before'), findsNothing);

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Count'));
      expect(inForm('Daily goal'), findsOneWidget);
      expect(inForm('Minimum Day goal'), findsOneWidget);
      expect(inForm('Unit (e.g. pages, glasses)'), findsOneWidget);

      await _tap(tester, find.widgetWithText(ChoiceChip, 'Before a time'));
      expect(inForm('Minimum Day goal'), findsNothing);
      expect(inForm('Goal: before'), findsOneWidget);
      expect(inForm('23:00'), findsOneWidget);
      await _tap(tester, find.text('Goal: before'));
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await _pickTime(tester, 22, 15);
      expect(inForm('22:15'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Phone off',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add habit'));
      await _tap(tester, find.text('Add habit'));
      expect(find.text('Phone off added'), findsOneWidget);
      final habits = await TestApp(db, clock).winterArc.setupHabits();
      final phone = habits.singleWhere((h) => h.title == 'Phone off');
      expect(phone.type, HabitType.timeBefore);
      expect(phone.target, NightTime(22, 15).value);
      expect(SetupHabitRules.isCustomId(phone.id), isTrue);
      await _shutDown(tester);
    });

    testWidgets('at 12 habits Add Habit is disabled, with the reason', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final service = TestApp(db, clock).winterArc;
      for (var i = 0; i < 5; i++) {
        await service.addCustomHabit(
          HabitDraft(
            title: 'Extra $i',
            type: HabitType.binary,
            iconKey: 'star',
          ),
        );
      }
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining("You've reached 12 habits"),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add Habit'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining("You've reached 12 habits"), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Add Habit, unavailable')),
        findsOneWidget,
      );
      await _shutDown(tester);
    });
  });

  group('Today: a clock-time habit', () {
    late AppDatabase db;
    late FakeClock clock;

    /// A rolling arc on 4 Oct with Water and Sleep Before Target (goal
    /// 23:30) on.
    setUp(() async {
      db = memoryDatabase();
      clock = FakeClock(DateTime(2026, 10, 4, 8));
      final app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      for (final h in await app.winterArc.setupHabits()) {
        await app.winterArc.setHabitEnabled(
          h.id,
          enabled: h.id == 'water' || h.id == 'sleep_before',
        );
      }
      await app.winterArc.startWinterArc();
    });
    tearDown(() => db.close());

    Finder sleepCard() => find.byType(TimeBeforeHabitTile);

    testWidgets('not logged → logged on time → changed to late → cleared', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        sleepCard(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Goal · before 23:30'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Sleep Before Target, not logged, goal before 23:30'),
        ),
        findsOneWidget,
      );

      // Log last night's bedtime: on time.
      await _tap(tester, sleepCard());
      expect(find.text('When did you go to bed last night?'), findsOneWidget);
      await _pickTime(tester, 23, 10);
      expect(find.text('Last night · 23:10'), findsOneWidget);
      expect(
        find.text('Sleep Before Target complete · +15 XP'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Last night 23:10, .*Done')),
        findsOneWidget,
      );

      // Change it: after the goal. Kept, but not done; XP is revoked.
      await clearCelebrations(tester);
      await _tap(tester, sleepCard());
      await _pickTime(tester, 0, 10);
      expect(find.text('Last night · 00:10'), findsOneWidget);
      expect(find.text('After the goal'), findsOneWidget);
      expect(find.text('Sleep Before Target marked not done'), findsOneWidget);
      final app = TestApp(db, clock);
      expect((await app.tracking.today()).totalXp, 0);

      // Clear it.
      await _tap(tester, find.byTooltip('Clear Sleep Before Target time'));
      expect(find.text('Sleep Before Target time cleared'), findsOneWidget);
      expect(find.textContaining('Last night ·'), findsNothing);
      // Undo brings 00:10 back.
      await _tap(tester, find.text('Undo'));
      expect(find.text('Last night · 00:10'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('a daytime pick is refused with a hint', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        sleepCard(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, sleepCard());
      await _pickTime(tester, 14, 0);
      expect(find.text('Pick a time between 18:00 and 05:59.'), findsOneWidget);
      expect(find.text('Goal · before 23:30'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('2× text: setup, Add Habit and the clock card stay usable', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(db, clock);
      await app.tracking.perform(
        habitId: 'sleep_before',
        action: HabitAction.setTime,
        time: NightTime(0, 40),
        date: clock.today(),
      );
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        sleepCard(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Last night · 00:40'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shutDown(tester);

      // A new setup at 2× (the old arc completes first).
      final setupDb = memoryDatabase();
      addTearDown(setupDb.close);
      await TestApp(setupDb, clock).winterArc.beginSetup();
      await tester.pumpWidget(_app(setupDb, clock));
      await tester.pumpAndSettle();
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      await _tapVisible(tester, find.text('Add Habit'));
      expect(find.text('TEMPLATES'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });
  });

  group('seasonal history', () {
    testWidgets('the Journey shows the days before joining as neutral', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 10, 15));
      await joinSeason(TestApp(db, clock), DateTime(2026, 10, 15));
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await _openTab(tester, 'Journey');
      expect(find.byType(JourneyScreen), findsOneWidget);
      expect(find.text('Day 15 of 92'), findsOneWidget);
      expect(find.textContaining('Joined on Day 15.'), findsOneWidget);
      final notJoined = find.bySemanticsLabel(
        'Day 14. Before you joined this Seasonal Winter Arc.',
      );
      await tester.scrollUntilVisible(
        notJoined,
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(notJoined, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Day 14, Missed')), findsNothing);
      await _tap(tester, notJoined);
      expect(
        find.text('Before you joined this Seasonal Winter Arc.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'You joined on Day 15. Earlier season days are not counted '
          'against you.',
        ),
        findsOneWidget,
      );
      expect(find.text('Habits complete'), findsNothing, reason: 'read-only');
      await _shutDown(tester);
    });

    testWidgets('the seasonal summary separates the season from '
        'participation, and History names both kinds', (tester) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 7, 1));
      final app = TestApp(db, clock);
      await runFirstArc(app); // rolling, 1 Jul – 30 Sep
      await joinSeason(app, DateTime(2026, 10, 15));
      await completeAll(app);
      clock.current = DateTime(2027, 1, 1, 9);
      await app.lifecycle.reconcile();

      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('SEASONAL WINTER ARC COMPLETE'), findsOneWidget);
      expect(find.text('92-day season'), findsOneWidget);
      expect(find.text('1 Oct – 31 Dec 2026'), findsOneWidget);
      expect(find.text('Joined Day 15 · 78 days participated'), findsOneWidget);
      // Consistency counts the 78 participated days: 1 full day → 1%.
      expect(find.bySemanticsLabel('Consistency: 1%'), findsOneWidget);

      await _tapVisible(tester, find.text('Arc History'));
      expect(find.text('SEASONAL WINTER ARC · 2026'), findsOneWidget);
      expect(find.text('ROLLING WINTER ARC'), findsOneWidget);
      expect(find.text('Joined Day 15'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Seasonal Winter Arc · 2026, 1 Oct – 31 Dec 2026, '
            r'completed\. Joined Day 15',
          ),
        ),
        findsOneWidget,
      );
      await _shutDown(tester);
    });
  });
}
