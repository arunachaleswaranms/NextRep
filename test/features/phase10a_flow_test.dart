import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';

import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 10A: a Minimum Day can return to full targets while it is still
/// today, from the activation snackbar or from the Minimum Day banner.
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
}
