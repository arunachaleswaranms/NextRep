import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';
import 'package:nextrep/features/today/widgets/time_before_tile.dart';

import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 10A: a Minimum Day can return to full targets while it is still
/// today, from the activation snackbar or from the Minimum Day banner; and
/// Sleep Before Target reads as last night's bedtime, counted for today.
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

void _textScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Unmounts the app and lets pending snackbar / celebration timers expire.
Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
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

Finder get _returnAction =>
    find.widgetWithText(TextButton, 'Return to full targets');

Finder get _confirmReturn => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, 'Return to full targets'),
);

void main() {
  group('Minimum Day: return to full targets', () {
    late AppDatabase db;
    late FakeClock clock;
    late TestApp app;

    Future<void> act(String habitId, HabitAction action, int times) async {
      for (var i = 0; i < times; i++) {
        await app.tracking.perform(
          habitId: habitId,
          action: action,
          date: clock.today(),
        );
      }
    }

    Future<List<DayMode>> storedModes() async => [
      for (final row in await db.select(db.dayModes).get()) row.mode,
    ];

    /// A rolling arc on 1 Oct with the four default habits: Water 4 / 8 and
    /// Workout 15 / 30 min, both above their minimums (3, 10 min).
    setUp(() async {
      db = memoryDatabase();
      clock = FakeClock(DateTime(2026, 10, 1, 9));
      app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      await act('water', HabitAction.increment, 4);
      await act('workout', HabitAction.increment, 3);
    });
    tearDown(() => db.close());

    testWidgets('activation offers Undo, which returns to full targets '
        'through the persisted transition', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();

      await reveal(tester, find.text('Having a rough day?'));
      await _tap(tester, find.text('Having a rough day?'));
      await tester.ensureVisible(find.text('Switch to Minimum Day'));
      await _tap(tester, find.text('Switch to Minimum Day'));

      expect(find.text('Minimum Day'), findsOneWidget); // banner
      expect(find.text('4 / 3 glasses'), findsOneWidget);
      expect(find.text('Minimum Day activated'), findsOneWidget);
      final undo = find.widgetWithText(SnackBarAction, 'Undo');
      expect(undo, findsOneWidget);
      expect(await storedModes(), [DayMode.minimum]);
      expect((await app.tracking.today()).totalXp, 2 * 15);

      await _tap(tester, undo);
      expect(find.text('Back to full targets'), findsOneWidget);
      expect(find.text('Minimum Day'), findsNothing);
      expect(find.text('MINIMUM'), findsNothing);
      // Full targets, progress kept exactly.
      expect(find.text('4 / 8 glasses'), findsOneWidget);
      expect(find.text('15 / 30 min'), findsOneWidget);
      expect(await storedModes(), [DayMode.normal]);
      final today = await app.tracking.today();
      expect(today.mode, DayMode.normal);
      expect(today.totalXp, 0);
      expect(find.text('0 XP'), findsWidgets);
      // A normal day again: Minimum Day is offered again.
      await reveal(tester, find.text('Having a rough day?'));
      expect(find.text('Having a rough day?'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('Undo after the day rolled over never changes yesterday', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Having a rough day?'));
      await _tap(tester, find.text('Having a rough day?'));
      await tester.ensureVisible(find.text('Switch to Minimum Day'));
      await _tap(tester, find.text('Switch to Minimum Day'));

      clock.current = DateTime(2026, 10, 2, 0, 1);
      await _tap(tester, find.widgetWithText(SnackBarAction, 'Undo'));
      expect(
        find.text("It's a new day — Today has been refreshed."),
        findsOneWidget,
      );
      expect(find.text('Day 2 of 92'), findsOneWidget);
      final history = await app.tracking.history();
      expect(history.recordOn(clock.today().addDays(-1)).mode, DayMode.minimum);
      expect(await storedModes(), [DayMode.minimum]);
      await _shutDown(tester);
    });

    testWidgets('the banner action confirms first; Cancel changes nothing', (
      tester,
    ) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);

      expect(_returnAction, findsOneWidget);
      await _tap(tester, _returnAction);
      expect(find.text('Return to full targets?'), findsOneWidget);
      expect(find.textContaining('Your progress stays'), findsOneWidget);
      expect(find.textContaining('may become incomplete'), findsOneWidget);
      expect(find.textContaining('XP will be adjusted'), findsOneWidget);

      await _tap(tester, find.text('Cancel'));
      expect(find.text('Return to full targets?'), findsNothing);
      expect(find.text('Minimum Day'), findsOneWidget);
      expect(await storedModes(), [DayMode.minimum]);

      await _tap(tester, _returnAction);
      await _tap(tester, _confirmReturn);
      expect(find.text('Minimum Day'), findsNothing);
      expect(_returnAction, findsNothing);
      expect(find.text('4 / 8 glasses'), findsOneWidget);
      expect(find.text('15 / 30 min'), findsOneWidget);
      expect(await storedModes(), [DayMode.normal]);
      expect((await app.tracking.today()).totalXp, 0);
      await _shutDown(tester);
    });

    testWidgets('rapid taps open one dialog and apply one transition', (
      tester,
    ) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);

      await tester.tap(_returnAction);
      await tester.tap(_returnAction, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(_confirmReturn);
      await tester.tap(_confirmReturn, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Back to full targets'), findsOneWidget);
      expect(await storedModes(), [DayMode.normal]);
      final ledger = await db.select(db.xpTransactions).get();
      expect(ledger, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('2x text: the banner action and the dialog fit a phone', (
      tester,
    ) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      await _setPhoneSize(tester);
      _textScale(tester, 2);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);

      await reveal(tester, _returnAction);
      expect(tester.takeException(), isNull);
      final button = tester.getSize(_returnAction);
      expect(button.height, greaterThanOrEqualTo(48));
      await _tap(tester, _returnAction);
      expect(tester.takeException(), isNull);
      expect(_confirmReturn, findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await _tap(tester, _confirmReturn);
      expect(tester.takeException(), isNull);
      expect(await storedModes(), [DayMode.normal]);
      await _shutDown(tester);
    });

    testWidgets('a past Minimum Day stays read-only', (tester) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      clock.current = DateTime(2026, 10, 2, 9);
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);

      expect(find.text('Day 2 of 92'), findsOneWidget);
      expect(find.text('Minimum Day'), findsNothing);
      expect(_returnAction, findsNothing);

      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Journey'),
        ),
      );
      await _tap(tester, find.bySemanticsLabel(RegExp(r'^Day 1\.')));
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Return to full targets'), findsNothing);
      expect(await storedModes(), [DayMode.minimum]);
      await _shutDown(tester);
    });
  });

  group("Sleep Before: last night's bedtime", () {
    late AppDatabase db;
    late FakeClock clock;
    late TestApp app;

    Finder card(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(TimeBeforeHabitTile),
    );

    Finder inCard(String title, Finder finder) =>
        find.descendant(of: card(title), matching: finder);

    const explain = CustomSemanticsAction(label: BedtimeExplanation.question);

    /// A rolling arc on 4 Oct with Sleep Before Target (goal 23:30) and a
    /// custom clock-time habit "Phone Down" (goal 22:00, with the sleep
    /// icon too), and nothing else.
    setUp(() async {
      // Predictable time pickers: 24-hour text entry.
      TestWidgetsFlutterBinding.ensureInitialized()
              .platformDispatcher
              .alwaysUse24HourFormatTestValue =
          true;
      db = memoryDatabase();
      clock = FakeClock(DateTime(2026, 10, 4, 8));
      app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      for (final h in await app.winterArc.setupHabits()) {
        await app.winterArc.setHabitEnabled(
          h.id,
          enabled: h.id == 'sleep_before',
        );
      }
      await app.winterArc.addCustomHabit(
        HabitDraft(
          title: 'Phone Down',
          type: HabitType.timeBefore,
          iconKey: 'sleep',
          target: NightTime(22, 0).value,
        ),
      );
      await app.winterArc.startWinterArc();
    });
    tearDown(() async {
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
          .clearAlwaysUse24HourTestValue();
      await db.close();
    });

    testWidgets('the card says last night, counted for today; a custom '
        'clock-time habit keeps neutral wording', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, card('Phone Down'));

      // Not logged yet.
      final sleep = card('Sleep Before Target');
      expect(
        inCard('Sleep Before Target', find.text("Last night's bedtime")),
        findsOneWidget,
      );
      expect(
        inCard('Sleep Before Target', find.text('Goal · before 23:30')),
        findsOneWidget,
      );
      expect(
        inCard(
          'Sleep Before Target',
          find.text("Tap to log it for today's check-in"),
        ),
        findsOneWidget,
      );
      // The custom habit: no sleep-specific copy, no explanation.
      expect(inCard('Phone Down', find.textContaining('night')), findsNothing);
      expect(inCard('Phone Down', find.textContaining('today')), findsNothing);
      expect(
        inCard('Phone Down', find.byTooltip(BedtimeExplanation.question)),
        findsNothing,
      );
      final custom = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Phone Down, ')))
          .getSemanticsData();
      expect(custom.label, startsWith('Phone Down, not logged, goal before'));
      expect(custom.label, isNot(contains('night')));
      expect(
        custom.customSemanticsActionIds ?? const <int>[],
        isNot(contains(CustomSemanticsAction.getIdentifier(explain))),
      );

      // Log last night's bedtime: 22:48, before the goal.
      await _tap(tester, sleep);
      expect(find.text('When did you go to bed last night?'), findsOneWidget);
      await _pickTime(tester, 22, 48);
      expect(
        inCard(
          'Sleep Before Target',
          find.text("Last night's bedtime · 22:48"),
        ),
        findsOneWidget,
      );
      expect(
        inCard('Sleep Before Target', find.text('Goal met')),
        findsOneWidget,
      );
      expect(find.text("Tap to log it for today's check-in"), findsNothing);
      final node = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Sleep Before Target, ')))
          .getSemanticsData();
      expect(
        node.label,
        "Sleep Before Target, last night's bedtime 22:48, goal before 23:30, "
        "Goal met, counts toward today's check-in, 1 day streak",
      );
      // Recorded for today (4 Oct), never for yesterday.
      final rows = await db.select(db.dailyHabitProgressEntries).get();
      expect(rows.single.habitId, 'sleep_before');
      expect(rows.single.date, clock.today());

      // The custom habit logs as "Logged", whatever its icon.
      await clearCelebrations(tester);
      await _tap(tester, card('Phone Down'));
      expect(find.text('What time was it?'), findsOneWidget);
      await _pickTime(tester, 21, 30);
      expect(inCard('Phone Down', find.text('Logged · 21:30')), findsOneWidget);
      expect(inCard('Phone Down', find.text('Goal met')), findsNothing);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('"Why does this count for today?" works by touch and by '
        'screen reader', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, card('Sleep Before Target'));

      final info = find.byTooltip(BedtimeExplanation.question);
      expect(info, findsOneWidget);
      final size = tester.getSize(
        find.ancestor(of: info, matching: find.byType(IconButton)),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await _tap(tester, info);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(BedtimeExplanation.question), findsOneWidget);
      expect(
        find.textContaining('Your sleep ended this morning'),
        findsOneWidget,
      );
      expect(
        find.textContaining("belongs to today's check-in"),
        findsOneWidget,
      );
      // Explaining never logs anything or opens the picker.
      expect(find.text('When did you go to bed last night?'), findsNothing);
      await _tap(tester, find.text('Got it'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(await db.select(db.dailyHabitProgressEntries).get(), isEmpty);

      // A screen reader reaches it as an action of the card.
      final node = find.semantics.byLabel(RegExp('^Sleep Before Target, '));
      final data = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Sleep Before Target, ')))
          .getSemanticsData();
      expect(
        data.label,
        "Sleep Before Target, last night's bedtime not logged, goal before "
        "23:30, counts toward today's check-in",
      );
      expect(data.hint, 'Double tap to log a time');
      tester.semantics.customAction(node, explain);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your sleep ended this morning'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Got it'));
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('a renamed Sleep Before keeps its name and its copy', (
      tester,
    ) async {
      await app.tracking.editHabit(
        habitId: 'sleep_before',
        edit: const HabitEdit(title: 'Lights Out'),
        date: clock.today(),
      );
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, card('Lights Out'));
      expect(find.text('Sleep Before Target'), findsNothing);
      expect(
        inCard('Lights Out', find.text("Last night's bedtime")),
        findsOneWidget,
      );
      expect(
        inCard('Lights Out', find.byTooltip(BedtimeExplanation.question)),
        findsOneWidget,
      );
      final habits = await db.select(db.habits).get();
      expect(
        habits.singleWhere((h) => h.id == 'sleep_before').title,
        'Lights Out',
      );
      await _shutDown(tester);
    });

    testWidgets('2x text: the card and the explanation fit a phone', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      _textScale(tester, 2);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, card('Sleep Before Target'));
      expect(tester.takeException(), isNull);
      expect(find.text("Last night's bedtime"), findsOneWidget);

      await _tap(tester, find.byTooltip(BedtimeExplanation.question));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Got it'));
      await _tap(tester, find.text('Got it'));

      await app.tracking.perform(
        habitId: 'sleep_before',
        action: HabitAction.setTime,
        time: NightTime(23, 50),
        date: clock.today(),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await reveal(tester, card('Sleep Before Target'));
      expect(find.text("Last night's bedtime · 23:50"), findsOneWidget);
      expect(find.text('After the goal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });

    testWidgets('a past day stays read-only', (tester) async {
      await app.tracking.perform(
        habitId: 'sleep_before',
        action: HabitAction.setTime,
        time: NightTime(23, 10),
        date: clock.today(),
      );
      clock.current = DateTime(2026, 10, 5, 8);
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      // Today is a new, empty check-in; yesterday's record stays where it
      // was and can't be reached from Today.
      await reveal(tester, card('Sleep Before Target'));
      expect(find.text("Last night's bedtime"), findsOneWidget);
      expect(find.textContaining('23:10'), findsNothing);
      await expectLater(
        app.tracking.perform(
          habitId: 'sleep_before',
          action: HabitAction.setTime,
          time: NightTime(22, 0),
          date: LocalDate(2026, 10, 4),
        ),
        throwsA(
          isA<DomainFailure>().having(
            (f) => f.rule,
            'rule',
            DomainRule.staleDay,
          ),
        ),
      );
      final history = await app.tracking.history();
      expect(
        history
            .recordOn(LocalDate(2026, 10, 4))
            .entryFor('sleep_before')!
            .progress
            .currentValue,
        NightTime(23, 10).value,
      );
      await _shutDown(tester);
    });
  });

  testWidgets('setup describes Sleep Before as a morning check-in', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 4, 9));
    final app = TestApp(db, clock);
    await app.winterArc.beginSetup();
    await app.winterArc.addCustomHabit(
      HabitDraft(
        title: 'Phone Down',
        type: HabitType.timeBefore,
        iconKey: 'sleep',
        target: NightTime(22, 0).value,
      ),
    );
    await _setPhoneSize(tester);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();

    const copy = 'Morning check-in · counts toward the day you wake up';
    Finder tile(String title) => find.widgetWithText(HabitToggleTile, title);
    await reveal(tester, tile('Phone Down'));
    expect(
      find.descendant(
        of: tile('Sleep Before Target'),
        matching: find.text(copy),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile('Phone Down'), matching: find.text(copy)),
      findsNothing,
    );
    expect(find.text(copy), findsOneWidget);
    await _shutDown(tester);
  });
}
