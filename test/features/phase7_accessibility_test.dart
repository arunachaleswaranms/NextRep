import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/habit/night_time.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/achievements/achievements_screen.dart';
import 'package:nextrep/features/celebration/celebration_cards.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/insights/insights_screen.dart';
import 'package:nextrep/features/journal/widgets/reflection_entry_card.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/journey/widgets/journey_marker.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';
import 'package:nextrep/features/today/widgets/time_before_tile.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 7 accessibility qualification: what a screen reader or switch user
/// gets (labels, states, actions), large text, reduced motion, touch
/// targets, and that long lists stay lazy.
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

Future<void> _openTab(WidgetTester tester, String label) async {
  await clearCelebrations(tester);
  await _tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
}

void _go(WidgetTester tester, String location) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);

/// The semantics a screen reader gets for the node labelled [label].
SemanticsData _node(WidgetTester tester, Pattern label) =>
    tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();

/// A seasonal arc joined on 5 Oct 2026 (Day 5) with Sleep Before Target
/// on, the clock left on [today] at 09:00.
Future<TestApp> _seasonalArc(AppDatabase db, DateTime today) async {
  final clock = FakeClock(DateTime(2026, 10, 5, 9));
  final app = TestApp(db, clock);
  await app.winterArc.startNewArc(
    NewArcBaseline.fresh,
    kind: ArcKind.seasonalWinter,
  );
  await app.winterArc.setHabitEnabled('sleep_before', enabled: true);
  await app.winterArc.startWinterArc();
  clock.current = DateTime(today.year, today.month, today.day, 9);
  return app;
}

void main() {
  group('semantics', () {
    testWidgets('Arc choice: availability is spoken and only an available '
        'card can be activated', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 5, 10, 9))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("Let's Begin"));

      final seasonal = _node(tester, RegExp(r'^Seasonal Winter Arc\.'));
      expect(seasonal.label, contains('Preseason opens September 1'));
      expect(seasonal.label, contains('Not available yet'));
      expect(seasonal.hasAction(SemanticsAction.tap), isFalse);
      final rolling = _node(tester, RegExp(r'^Rolling 92-Day Arc\.'));
      expect(rolling.hasAction(SemanticsAction.tap), isTrue);
      expect(rolling.label, contains('92 days from the day you begin'));

      // Activating the card through its semantics action works (switch
      // access, voice access, a screen reader's double tap).
      tester.semantics.tap(find.semantics.byLabel(RegExp(r'^Rolling 92')));
      await tester.pumpAndSettle();
      expect(find.byType(HabitSetupScreen), findsOneWidget);

      // Add Habit is a real action too.
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Add Habit'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final add = _node(tester, 'Add Habit');
      expect(add.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('in season, the Seasonal card says days before joining '
        "don't count", (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 10, 15, 9))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text("Let's Begin"));
      final seasonal = _node(tester, RegExp(r'^Seasonal Winter Arc\.'));
      expect(seasonal.label, contains("Days before you join don't count"));
      expect(seasonal.label, contains('In season · 2026'));
      // Found on a device: the description's own period was doubled.
      expect(seasonal.label, isNot(contains('..')));
      expect(seasonal.label, isNot(contains('Not available')));
      expect(seasonal.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('the clock-time card reads its record and goal, can be '
        'activated, and offers Clear as an action', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      await app.tracking.perform(
        habitId: 'sleep_before',
        action: HabitAction.setTime,
        date: app.clock.today(),
        time: NightTime(23, 10),
      );
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TimeBeforeHabitTile));

      final card = _node(tester, RegExp(r'^Sleep Before Target, '));
      expect(card.label, contains('23:10'));
      expect(card.label, contains('goal before'));
      expect(card.hasAction(SemanticsAction.tap), isTrue);
      expect(card.hasAction(SemanticsAction.customAction), isTrue);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('Journey days say their state in words, including days '
        'before joining, and can be activated', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 7));
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await _openTab(tester, 'Journey');

      final today = _node(tester, RegExp(r'^Day 7\. Today\. '));
      expect(today.label, matches(RegExp(r'\d+ percent complete\.$')));
      expect(today.hasAction(SemanticsAction.tap), isTrue);
      final missed = _node(tester, 'Day 6. Missed.');
      expect(missed.hasAction(SemanticsAction.tap), isTrue);

      await tester.scrollUntilVisible(
        find.bySemanticsLabel(
          'Day 3. Before you joined this Seasonal Winter Arc.',
        ),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      final before = _node(
        tester,
        'Day 3. Before you joined this Seasonal Winter Arc.',
      );
      expect(before.hasAction(SemanticsAction.tap), isTrue);
      // The whole reserved square is the target, not the 26 dp marker.
      final box = tester.getSize(
        find
            .ancestor(
              of: find.bySemanticsLabel(
                'Day 3. Before you joined this Seasonal Winter Arc.',
              ),
              matching: find.byType(JourneyMarker),
            )
            .first,
      );
      expect(box.shortestSide, greaterThanOrEqualTo(48));
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('Insights moods have a text alternative, and no mood bars '
        'when no mood was picked', (tester) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      final arc = (await app.sessions.currentSession())!;
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(win: 'Walked home'),
      );
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      _go(tester, AppRoutes.insights);
      await tester.pumpAndSettle();
      expect(find.byType(InsightsScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('No moods picked yet.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1 saved without a mood'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Excellent: ')), findsNothing);

      // With a mood, every bar and the timeline are also spoken.
      app.clock.current = DateTime(2026, 10, 7, 9);
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(mood: Mood.good),
      );
      _go(tester, AppRoutes.today);
      await tester.pumpAndSettle();
      _go(tester, AppRoutes.insights);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(RegExp(r'^Recent moods, oldest first\. ')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        _node(tester, RegExp(r'^Recent moods, oldest first\. ')).label,
        contains('Day 7: Good'),
      );
      expect(find.bySemanticsLabel('Good: 1'), findsOneWidget);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('an Arc History card speaks its counts in the singular when '
        'there is one', (tester) async {
      // Found on a device in Phase 8: "1 reflections".
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      final arc = (await app.sessions.currentSession())!;
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(mood: Mood.good),
      );
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await _openTab(tester, 'History');
      final card = _node(tester, RegExp(r'^Seasonal Winter Arc · 2026, '));
      expect(card.label, contains('0 Perfect Days'));
      expect(card.label, contains('1 reflection'));
      expect(card.label, isNot(contains('1 reflections')));
      expect(card.label, matches(RegExp(r'\d+ of 15 achievements')));
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('Today meets the tap-target and labelled-target guidelines', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final handle = tester.ensureSemantics();
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await _openTab(tester, 'Journey');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
      await _shutDown(tester);
    });
  });

  group('large text', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('onboarding and Arc choice at ${scale}x keep their actions '
          'reachable', (tester) async {
        await _setPhoneSize(tester);
        _textScale(tester, scale);
        final db = memoryDatabase();
        addTearDown(db.close);
        await tester.pumpWidget(_app(db, FakeClock(DateTime(2026, 9, 10, 9))));
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The call to action is always on screen, even at 2x.
        final screen = tester.getRect(find.byType(OnboardingScreen));
        expect(
          screen.contains(tester.getCenter(find.text("Let's Begin"))),
          isTrue,
        );
        await _tap(tester, find.text("Let's Begin"));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Preseason · the season starts October 1'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await _shutDown(tester);
      });
    }

    testWidgets('the level and XP beside the XP pill are never cut short at '
        '2x', (tester) async {
      // Found on a device in Phase 8: "Le…" and "30 / 250…" on Today.
      await _setPhoneSize(tester);
      _textScale(tester, 2);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['Level 1', '0 / 250 XP']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        expect(paragraph.size.width, greaterThan(0), reason: label);
      }
      await _shutDown(tester);
    });

    testWidgets('a late-joined Summary heading at 2x grows instead of '
        'running under the top buttons', (tester) async {
      await _setPhoneSize(tester);
      _textScale(tester, 2);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2027, 1, 1));
      await app.lifecycle.reconcile();
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.text('SEASONAL WINTER ARC COMPLETE'));
      final options = tester.getRect(find.byTooltip('Arc options'));
      expect(heading.top, greaterThanOrEqualTo(options.bottom));
      expect(find.textContaining('Joined Day 5'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('the day detail and Minimum Day sheets fit at 2x', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      _textScale(tester, 2);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();

      await reveal(tester, find.text('Having a rough day?'));
      await _tap(tester, find.text('Having a rough day?'));
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();

      await _openTab(tester, 'Journey');
      await _tap(tester, find.bySemanticsLabel(RegExp(r'^Day 6\. Today\.')));
      expect(find.text('Day 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('Today hero, Perfect Day, seasonal Journey and achievements '
        'settle with nothing animating and nothing missing', (tester) async {
      await _setPhoneSize(tester);
      _reducedMotion(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      // Everything but No Junk Food, which the test then taps for the
      // Perfect Day.
      for (final entry in (await app.tracking.today()).entries) {
        final habit = entry.habit;
        if (habit.id == 'no_junk_food') continue;
        if (habit.type.isClockTime) {
          await app.tracking.perform(
            habitId: habit.id,
            action: HabitAction.setTime,
            date: app.clock.today(),
            time: NightTime(22, 30),
          );
        } else {
          await completeHabit(app, habit.id);
        }
      }
      // The ambient scene would loop forever if reduced motion were
      // ignored, and pumpAndSettle would time out.
      await tester.pumpWidget(_app(db, app.clock, ambient: true));
      await tester.pumpAndSettle();
      expect(find.text('Day 6 of 92'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      await reveal(tester, find.byTooltip('Complete No Junk Food'));
      await _tap(tester, find.byTooltip('Complete No Junk Food'));
      expect(find.byType(CelebrationCard), findsOneWidget);
      expect(find.textContaining('Perfect'), findsWidgets);
      expect(tester.binding.transientCallbackCount, 0);
      await clearCelebrations(tester);

      await _openTab(tester, 'Journey');
      expect(find.byType(JourneyScreen), findsOneWidget);
      expect(find.byType(JourneyMarker), findsWidgets);
      expect(find.bySemanticsLabel('Day 6. Today. Perfect Day.'), findsOne);
      expect(tester.binding.transientCallbackCount, 0);

      _go(tester, AppRoutes.achievements);
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      await _shutDown(tester);
    });

    testWidgets('the Summary summit is complete on the first frame', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      _reducedMotion(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = TestApp(db, FakeClock(DateTime(2026, 7, 1, 8)));
      await runFirstArc(app);
      await tester.pumpWidget(_app(db, app.clock, ambient: true));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await _shutDown(tester);
    });
  });

  group('long lists stay lazy', () {
    testWidgets('the Journey builds only the days near the viewport', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = await _seasonalArc(db, DateTime(2026, 10, 6));
      await tester.pumpWidget(_app(db, app.clock));
      await tester.pumpAndSettle();
      await _openTab(tester, 'Journey');
      final built = find.byType(JourneyMarker).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(WinterArcRules.lengthInDays ~/ 2));
      await _shutDown(tester);
    });

    testWidgets('a past Journal with 60 entries builds a screenful', (
      tester,
    ) async {
      await _setPhoneSize(tester);
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 7, 1, 8));
      final app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      final arc = await app.winterArc.startWinterArc();
      for (var day = 1; day <= 60; day++) {
        clock.current = DateTime(2026, 7, day, 21);
        await app.reflections.save(
          sessionId: arc.id,
          date: clock.today(),
          draft: ReflectionDraft(mood: Mood.okay, win: 'Day $day'),
        );
      }
      clock.current = DateTime(2026, 10, 1, 9);
      await app.lifecycle.reconcile();

      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      _go(tester, AppRoutes.arcJournal(arc.id));
      await tester.pumpAndSettle();
      final built = find.byType(ReflectionEntryCard).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(30));
      await _shutDown(tester);
    });
  });
}
