import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/achievements/widgets/trophy_button.dart';
import 'package:nextrep/features/celebration/celebration_cards.dart';
import 'package:nextrep/features/journey/widgets/journey_marker.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/fakes.dart';
import '../support/ui.dart';

Widget _app(AppDatabase db, FakeClock clock, {bool ambient = false}) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        ambientMotionProvider.overrideWithValue(ambient),
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

Future<void> _onboardAndStart(WidgetTester tester) async {
  await tester.tap(find.text("Let's Begin"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start Winter Arc'));
  await tester.pumpAndSettle();
}

Finder get _navBar => find.byType(NavigationBar);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: _navBar, matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// An arc started on Oct 1 through the real services, with Day 1's No Junk
/// Food done.
Future<TestApp> _seedArc(FakeClock clock) async {
  final app = TestApp(memoryDatabase(), clock);
  await app.winterArc.beginSetup();
  await app.winterArc.startWinterArc();
  await app.tracking.perform(
    habitId: 'no_junk_food',
    action: HabitAction.complete,
    date: LocalDate(2026, 10, 1),
  );
  return app;
}

void main() {
  testWidgets('Today hero shows the persisted day, XP, level and stage', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2026, 10, 9, 9); // Day 9: past the first camp

    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 9 of 92'), findsOneWidget);
    expect(find.text('Friday, 9 October'), findsOneWidget);
    expect(find.text('First Camp'), findsOneWidget); // milestone chip
    expect(find.text('Next: Forest Camp in 5 days'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Daily completion 0 percent'), findsOneWidget);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('30 XP'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('an achievement is celebrated once, when first stored', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);
    expect(find.byType(CelebrationCard), findsNothing);
    expect(find.text('0/15'), findsOneWidget);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
    expect(find.text('First Rep'), findsOneWidget);
    expect(find.text('1/15'), findsOneWidget);

    // Tapping the card dismisses it.
    await tester.tap(find.byType(CelebrationCard));
    await tester.pumpAndSettle();
    expect(find.byType(CelebrationCard), findsNothing);

    // Undo and redo: already unlocked, so nothing is celebrated again.
    await reveal(tester, find.byTooltip('Undo No Junk Food'));
    await tester.tap(find.byTooltip('Undo No Junk Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.byType(CelebrationCard), findsNothing);
    expect(find.text('1/15'), findsOneWidget);
    expect(await db.select(db.achievementUnlocks).get(), hasLength(1));

    // Nor after a relaunch.
    await _shutDown(tester);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    expect(find.byType(CelebrationCard), findsNothing);
    expect(find.text('1/15'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('achievements screen shows unlocked and locked badges', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);

    expect(
      find.bySemanticsLabel('Achievements, 1 of 15 unlocked'),
      findsOneWidget,
    );
    await tester.tap(find.byType(TrophyButton));
    await tester.pumpAndSettle();
    expect(find.text('1 of 15 unlocked'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'First Rep. Unlocked, Day 1 · 1 Oct. Complete your first habit.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Snowball. Locked. Reach a 3-day streak on any habit.',
      ),
      findsOneWidget,
    );
    expect(find.text('LOCKED'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Summit'), 200);
    expect(find.text('Complete the 92-day Winter Arc.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Journey v2 shows the path and opens a day\'s detail', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2026, 10, 3, 9);
    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);

    await _openTab(tester, 'Journey');
    expect(find.text('JOURNEY'), findsOneWidget);
    expect(find.text('Frozen Forest · Frozen Trail'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 3, Today, today'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 2, Missed'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 4, Upcoming'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Day 1, Partial'));
    await tester.pumpAndSettle();
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Thursday, 1 October 2026'), findsOneWidget);
    expect(find.text('Frozen Forest'), findsWidgets);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('15 XP'), findsWidgets);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();

    // Future days are not interactive.
    await tester.tap(find.bySemanticsLabel('Day 4, Upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('Thursday, 1 October 2026'), findsNothing);

    // All 92 days and the summit are on the path.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Day 92, Upcoming'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SUMMIT'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('a completed arc opens on its summary, read-only', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2027, 1, 1, 8); // Day 93

    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(_navBar, findsNothing);
    expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
    expect(find.text('92 days'), findsOneWidget);
    expect(find.bySemanticsLabel('Total XP: 15'), findsOneWidget);
    expect(find.bySemanticsLabel('Habits completed: 1'), findsOneWidget);
    // First Rep, Midwinter and Summit.
    expect(find.bySemanticsLabel('Achievements: 3 / 15'), findsOneWidget);
    expect(find.text('No Junk Food'), findsOneWidget); // strongest habit
    expect(
      (await seeded.sessions.latestSession())!.status,
      WinterArcStatus.completed,
    );

    await tester.scrollUntilVisible(
      find.text('View Journey'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View Journey'));
    await tester.pumpAndSettle();
    expect(find.text('JOURNEY'), findsOneWidget);
    expect(find.text('Winter Arc complete'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r', today$')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);

    final achievements = find.widgetWithText(OutlinedButton, 'Achievements');
    await tester.scrollUntilVisible(
      achievements,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(achievements);
    await tester.pumpAndSettle();
    expect(find.text('3 of 15 unlocked'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('resuming after Day 92 closes the arc and shows the summary', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2026, 12, 31, 22); // Day 92: still active

    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 92 of 92'), findsOneWidget);
    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);

    clock.current = DateTime(2027, 1, 1, 7);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
    await _shutDown(tester);
  });

  testWidgets('Day 92: goal edits are locked, renames still allowed', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2026, 12, 31, 9);
    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Edit habits'));
    await tester.tap(find.text('Edit habits'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Today is the last day of your Winter Arc'),
      findsOneWidget,
    );
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((s) => s.onChanged == null), isTrue);

    await tester.tap(find.text('Water Intake'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add_rounded).first,
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Hydrate');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Renamed.'), findsOneWidget);
    expect(find.text('Hydrate'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('reduced motion: ambient scene still, app fully usable', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final db = memoryDatabase();
    addTearDown(db.close);
    // Ambient motion allowed by the app: only the platform setting stops it,
    // so every pumpAndSettle below proves nothing loops.
    await tester.pumpWidget(_app(db, clock, ambient: true));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);
    expect(tester.binding.transientCallbackCount, 0);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('First Rep'), findsOneWidget); // shown without motion
    await _openTab(tester, 'Journey');
    expect(find.byType(JourneyMarker), findsWidgets);
    expect(tester.binding.transientCallbackCount, 0);
    await _shutDown(tester);
  });

  testWidgets('large text keeps Today, Journey and the summary intact', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    final seeded = await _seedArc(clock);
    addTearDown(seeded.db.close);
    clock.current = DateTime(2026, 10, 20, 9);

    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(tester.takeException(), isNull);
    await reveal(tester, find.byTooltip('Add to Water Intake'));
    await tester.tap(find.byTooltip('Add to Water Intake'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 8 glasses'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _openTab(tester, 'Journey');
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Day 20, Today, today'), findsOneWidget);
    await _shutDown(tester);

    clock.current = DateTime(2027, 1, 3, 9);
    await tester.pumpWidget(_app(seeded.db, clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shutDown(tester);
  });
}
