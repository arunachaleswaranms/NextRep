import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/journey/widgets/journey_marker.dart';

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

/// Unmounts the app and lets pending snackbar / celebration timers expire.
Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _onboardAndStart(WidgetTester tester) async {
  await tester.tap(find.text("Let's Begin"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rolling 92-Day Arc'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start Winter Arc'));
  await tester.pumpAndSettle();
}

Future<void> _tapTimes(WidgetTester tester, Finder finder, int times) async {
  await reveal(tester, finder);
  for (var i = 0; i < times; i++) {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}

/// Completes the four default habits, No Junk Food last.
Future<void> _completeAll(WidgetTester tester) async {
  await _tapTimes(tester, find.byTooltip('Add to Workout'), 6);
  await _tapTimes(tester, find.byTooltip('Add to Water Intake'), 8);
  await _tapTimes(tester, find.byTooltip('Add to Learning / Skills'), 4);
  await _tapTimes(tester, find.byTooltip('Complete No Junk Food'), 1);
}

Finder get _navBar => find.byType(NavigationBar);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: _navBar, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  final clock = FakeClock(DateTime(2026, 10, 1, 9));

  testWidgets('onboarding and setup are outside the tab shell', (tester) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();

    expect(find.text("Let's Begin"), findsOneWidget);
    expect(_navBar, findsNothing);
    await tester.tap(find.text("Let's Begin"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rolling 92-Day Arc'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your habits'), findsOneWidget);
    expect(_navBar, findsNothing);

    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(_navBar, findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Today ↔ Journey switch, keep state, and stay in sync', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await _openTab(tester, 'Journey');
    expect(find.text('JOURNEY'), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.byType(JourneyMarker), findsWidgets);
    expect(find.bySemanticsLabel('Day 1, Today, today'), findsOneWidget);

    // Journey keeps its scroll position across tab switches. The path
    // climbs upwards: dragging down moves towards the summit.
    final journeyScroll = find.byType(Scrollable).last;
    await tester.drag(journeyScroll, const Offset(0, 300));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(journeyScroll).position.pixels;
    expect(offset, greaterThan(0));

    await _openTab(tester, 'Today');
    expect(find.text("Today's habits"), findsOneWidget);
    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();

    await _openTab(tester, 'Journey');
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels,
      offset,
    );
    // Journey re-read the persisted change made on Today.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Day 1, Today, today'));
    await tester.pumpAndSettle();
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Normal Day'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Perfect Day: celebration, +30, undo revokes, redo restores', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await _completeAll(tester);
    expect(find.text('PERFECT DAY'), findsWidgets); // card + badge
    expect(find.text('+30 XP bonus'), findsOneWidget);
    expect(find.text('🔥 Perfect streak: 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // card auto-dismisses
    await tester.pumpAndSettle();
    expect(find.text('+30 XP bonus'), findsNothing);
    // Then the achievement earned by the same commit (First Rep was
    // celebrated earlier, when Workout was completed).
    expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
    expect(find.text('Clean Sweep'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('90 XP'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Having a rough day?'), findsNothing);

    await reveal(tester, find.byTooltip('Undo No Junk Food'));
    await tester.tap(find.byTooltip('Undo No Junk Food'));
    await tester.pumpAndSettle();
    expect(
      find.text('No Junk Food marked not done · Perfect Day bonus removed'),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('45 XP'), findsOneWidget);
    expect(find.text('PERFECT DAY'), findsNothing);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('90 XP'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Minimum Day needs confirmation, then shows reduced goals', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final dir = Directory.systemTemp.createTempSync('nextrep_min_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/nextrep.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);
    await _tapTimes(tester, find.byTooltip('Add to Water Intake'), 2);

    // Opening the explanation and backing out changes nothing.
    await reveal(tester, find.text('Having a rough day?'));
    await tester.tap(find.text('Having a rough day?'));
    await tester.pumpAndSettle();
    expect(find.text('Today can be smaller.'), findsOneWidget);
    expect(find.text('8 glasses  →  3 glasses'), findsOneWidget);
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('MINIMUM DAY'), findsNothing);
    expect(find.text('2 / 8 glasses'), findsOneWidget);

    await tester.tap(find.text('Having a rough day?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Switch to Minimum Day'));
    await tester.tap(find.text('Switch to Minimum Day'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum Day'), findsOneWidget); // banner
    expect(find.text('Keep moving, even if today is smaller.'), findsOneWidget);
    expect(find.text('2 / 3 glasses'), findsOneWidget); // progress kept
    expect(find.text('0 / 10 min'), findsOneWidget);
    expect(find.text('MINIMUM'), findsWidgets);
    expect(find.text('Having a rough day?'), findsNothing);

    // Persisted: relaunch on the same file.
    await _shutDown(tester);
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    expect(_navBar, findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('MINIMUM DAY'), findsOneWidget);
    expect(find.text('2 / 3 glasses'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('habit goal edits are saved now and apply from tomorrow', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await reveal(tester, find.text('Edit habits'));
    await tester.tap(find.text('Edit habits'));
    await tester.pumpAndSettle();
    expect(find.text('Your habits'), findsOneWidget);
    expect(_navBar, findsNothing); // full-screen over the shell
    expect(find.text('8 glasses · Minimum 3 glasses'), findsOneWidget);

    await tester.tap(find.text('Water Intake'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase Daily goal'));
    await tester.tap(find.byTooltip('Increase Daily goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Today keeps its goal; the new one is shown as pending.
    expect(find.text('8 glasses · Minimum 3 glasses'), findsOneWidget);
    expect(
      find.text('From tomorrow: 10 glasses · Minimum 3 glasses'),
      findsOneWidget,
    );
    expect(find.text('Saved. Applies from tomorrow.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_navBar, findsOneWidget);
    expect(find.text('0 / 8 glasses'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('closing the editor while a save is in flight is safe', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await reveal(tester, find.text('Edit habits'));
    await tester.tap(find.text('Edit habits'));
    await tester.pumpAndSettle();
    // Turn Water off and leave before the commit has finished.
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('Water Intake'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_navBar, findsOneWidget);
    // The edit was stored even though the editor was already gone. It turns
    // Water off from tomorrow, so today still tracks it.
    final revision = (await db.select(db.habitRevisions).get()).single;
    expect(revision.habitId, 'water');
    expect(revision.enabled, isFalse);
    expect(revision.effectiveFrom, LocalDate(2026, 10, 2));
    expect(find.text('0 of 4 done'), findsOneWidget);
    await _shutDown(tester);
  });
}
