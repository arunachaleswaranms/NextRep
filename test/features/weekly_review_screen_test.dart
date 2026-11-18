import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/arc_refresh.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/journey/widgets/day_detail_sheet.dart';
import 'package:nextrep/features/review/weekly_review_controller.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';
import 'package:nextrep/shared/widgets/failure_view.dart';
import 'package:nextrep/shared/widgets/loading_view.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/review_fakes.dart';
import '../support/review_seed.dart';

/// Phase 12B: the Weekly Review in the real app (spec §§ 5, 8; R7, R8):
/// Journey entry points, routes and Back, week navigation without a
/// growing back stack, malformed locations, every screen state, the week
/// strip, read-only day details, semantics, focus order, keyboard access
/// and Material's accessibility guidelines. All data is synthetic.

late AppDatabase db;
late FakeClock clock;
late ReviewSeed seed;

Future<void> seeded(WidgetTester tester, {LocalDate? pausedFrom}) async {
  db = memoryDatabase();
  addTearDown(db.close);
  clock = FakeClock(DateTime(2026, 7, 1));
  seed = await seedReviewData(TestApp(db, clock), pausedFrom: pausedFrom);
}

/// A tall phone, so the whole review is built without scrolling.
void tallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 6000)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> open(
  WidgetTester tester,
  String route, {
  CountingProgressRepository? progress,
  bool settle = true,
}) async {
  // A fresh app each time: a new ProviderScope, never an updated one.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpWidget(reviewApp(db, clock, route, progress: progress));
  if (!settle) return;
  await tester.pumpAndSettle();
  // Let celebration cards time out, like a user would.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }
}

Future<void> done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Uri location(WidgetTester tester) =>
    GoRouterState.of(tester.element(find.byType(WeeklyReviewScreen))).uri;

Finder reviewButton(int week) =>
    find.widgetWithText(OutlinedButton, 'Week $week review');

Finder dayCell(int day) => find.bySemanticsLabel(RegExp('^Day $day,'));

void main() {
  group('entry points, routes and Back', () {
    testWidgets('Journey → "Week 2 review" over the tabs; week navigation '
        'replaces the location; Back returns to Journey', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.journey);
      expect(find.byType(NavigationBar), findsOneWidget);
      final tabs = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(tabs.destinations, hasLength(4), reason: 'no new tab');

      await tester.tap(reviewButton(2));
      await tester.pumpAndSettle();
      expect(find.text('Week 2 review'), findsOneWidget);
      expect(location(tester).toString(), '/journey/review?week=2');
      // On the root navigator: it covers the navigation bar.
      expect(find.byType(NavigationBar).hitTestable(), findsNothing);

      await tester.tap(find.text('Week 1'));
      await tester.pumpAndSettle();
      expect(find.text('Week 1 review'), findsOneWidget);
      expect(location(tester).queryParameters['week'], '1');
      await tester.tap(find.text('Week 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week 1'));
      await tester.pumpAndSettle();
      expect(find.text('Week 1 review'), findsOneWidget);

      // One Back, after three week changes: Journey, not an earlier week.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(WeeklyReviewScreen), findsNothing);
      expect(find.text('JOURNEY'), findsOneWidget);
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
      await done(tester);
    });

    testWidgets('a completed Arc\'s Journey opens Week 13 of that Arc', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.arcJourney(seed.completedId));
      await tester.tap(reviewButton(13));
      await tester.pumpAndSettle();
      expect(
        location(tester).toString(),
        '/arc/${seed.completedId}/review?week=13',
      );
      expect(find.text('Winter Arc · 1 Jul – 30 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Week 13 of 13'), findsOneWidget);
      expect(find.textContaining('Complete'), findsWidgets);
      expect(find.textContaining('TODAY SO FAR'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('JOURNEY'), findsOneWidget);
      await done(tester);
    });

    testWidgets('an ended Arc\'s Journey opens the week of closedOn; final, '
        'no Today so far, no later week', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.arcJourney(seed.endedId));
      await tester.tap(reviewButton(1));
      await tester.pumpAndSettle();
      expect(location(tester).toString(), '/arc/${seed.endedId}/review?week=1');
      expect(find.text('Ended early · Day 3 of 92'), findsOneWidget);
      expect(find.textContaining('TODAY SO FAR'), findsNothing);
      expect(find.text('Week 2'), findsNothing, reason: 'not reached');
      expect(find.textContaining('summit'), findsNothing);
      await done(tester);
    });

    testWidgets('before the participation start there is no review button, '
        'and a review route shows the empty state', (tester) async {
      tallPhone(tester);
      db = memoryDatabase();
      addTearDown(db.close);
      clock = FakeClock(DateTime(2026, 10, 18, 9));
      final app = TestApp(db, clock);
      await joinSeason(app, DateTime(2026, 10, 18));
      at(app, LocalDate(2026, 10, 17)); // the date moved back
      await open(tester, AppRoutes.journey);
      expect(find.byType(JourneyScreen), findsOneWidget);
      expect(find.textContaining(' review'), findsNothing);
      await open(tester, AppRoutes.activeReview(3));
      expect(
        find.text('Your first week review appears once your Arc has started.'),
        findsOneWidget,
      );
      expect(find.byType(FailureView), findsNothing);
      await done(tester);
    });

    testWidgets('malformed or unreviewable weeks never show an error page', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester);
      const cases = {
        '': 2,
        '?week=': 2,
        '?week=abc': 2,
        '?week=0': 2,
        '?week=-1': 2,
        '?week=14': 2,
        '?week=99': 2,
        '?week=123': 2,
        '?week=2.5': 2,
        '?week=0x1': 2,
        '?week=%20': 2,
        '?week=9': 2, // upcoming: the nearest reviewable week
        '?week=13': 2,
        '?week=1': 1,
        '?week=01': 1,
      };
      for (final MapEntry(key: query, value: week) in cases.entries) {
        await open(tester, '${AppRoutes.journeyReview}$query');
        expect(find.text('Week $week review'), findsOneWidget, reason: query);
        expect(find.byType(FailureView), findsNothing, reason: query);
      }
      // A historical route for a missing Arc: the existing calm failure.
      await open(tester, AppRoutes.arcReview(999, 1));
      expect(
        find.text('This Winter Arc is no longer on this device.'),
        findsOneWidget,
      );
      await done(tester);
    });
  });

  group('screen states', () {
    testWidgets('current week: settled totals, Today so far apart, '
        'in-progress wording, highlights and habits', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.activeReview(2));
      expect(find.text('Week 2 of 13 · Days 8–14'), findsOneWidget);
      expect(find.textContaining('In progress'), findsOneWidget);
      // Week 2 = Days 8–14 = 16–22 Oct; settled 16–20 Oct; today 21 Oct.
      expect(
        find.text('Fri 16 Oct – Thu 22 Oct · In progress'),
        findsOneWidget,
      );
      expect(find.text('TODAY SO FAR (DAY 13)'), findsOneWidget);
      expect(find.text('Today counts once it ends.'), findsOneWidget);
      expect(find.text('5 days counted'), findsOneWidget);
      expect(find.text('+0 XP'), findsNothing);
      expect(find.text('MOST CONSISTENT THIS WEEK'), findsOneWidget);
      expect(find.text('HABITS THIS WEEK'), findsOneWidget);
      expect(find.text(ReviewSeed.longTitle), findsWidgets);
      expect(
        find.textContaining(
          'Counts finished days; today is added when it '
          'ends.',
        ),
        findsOneWidget,
      );
      expect(find.text('Week 3'), findsNothing, reason: 'no next week yet');
      // Nothing on the review can change progress.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('Add'), findsNothing);
      await done(tester);
    });

    testWidgets('a completed week: Complete, no Today so far, both '
        'directions', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      clock.current = DateTime(2026, 10, 29, 9); // Week 3 in progress
      await open(tester, AppRoutes.activeReview(2));
      expect(find.text('Fri 16 Oct – Thu 22 Oct · Complete'), findsOneWidget);
      expect(find.textContaining('TODAY SO FAR'), findsNothing);
      expect(find.text('Week 1'), findsOneWidget);
      expect(find.text('Week 3'), findsOneWidget);
      // Week 1 holds the 9–11 Oct pause.
      await tester.tap(find.text('Week 1'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tue 6 Oct – Thu 15 Oct · includes a 3-day pause · Complete'),
        findsOneWidget,
      );
      await done(tester);
    });

    testWidgets('a paused week: paused since, no Today so far, reviewable', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester, pausedFrom: LocalDate(2026, 10, 21));
      await open(tester, AppRoutes.journey);
      await tester.tap(reviewButton(2));
      await tester.pumpAndSettle();
      expect(find.text('Paused since Wed 21 Oct'), findsOneWidget);
      expect(find.text('Fri 16 Oct – paused · Paused'), findsOneWidget);
      expect(find.textContaining('TODAY SO FAR'), findsNothing);
      expect(find.text('5 days counted'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Day 13. Upcoming. Its date is set when you resume.',
        ),
        findsOneWidget,
      );
      await done(tester);
    });

    testWidgets('an empty in-progress week: START, the strip, Today so far, '
        'and no stats grid', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      clock.current = DateTime(2026, 10, 23, 9); // Day 15, first of Week 3
      await open(tester, AppRoutes.activeReview(3));
      expect(
        find.text('A new week begins today. One habit at a time.'),
        findsOneWidget,
      );
      expect(
        find.text('Stats appear after your first full day this week.'),
        findsOneWidget,
      );
      expect(find.text('HABIT COMPLETION'), findsNothing);
      expect(find.text('TODAY SO FAR (DAY 15)'), findsOneWidget);
      expect(dayCell(15), findsOneWidget);
      expect(dayCell(21), findsOneWidget);
      await done(tester);
    });

    testWidgets('an empty paused week: reviewable, says it begins on '
        'resume, no stats and no Today so far', (tester) async {
      tallPhone(tester);
      db = memoryDatabase();
      addTearDown(db.close);
      clock = FakeClock(DateTime(2027, 3, 1, 9));
      final app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      final arc = await app.winterArc.startWinterArc();
      for (var d = 1; d <= 14; d++) {
        at(app, LocalDate(2027, 3, d));
        await completeAll(app);
      }
      await addFreeze(db, arc.id, LocalDate(2027, 3, 15)); // after Day 14
      at(app, LocalDate(2027, 3, 18));
      await open(tester, AppRoutes.journey);
      await tester.tap(reviewButton(3));
      await tester.pumpAndSettle();
      expect(find.text('Week 3 review'), findsOneWidget);
      expect(find.text('This week begins when you resume.'), findsOneWidget);
      expect(find.text('Paused since Mon 15 Mar'), findsOneWidget);
      expect(find.text('HABIT COMPLETION'), findsNothing);
      expect(
        find.text('Stats appear after your first full day this week.'),
        findsNothing,
      );
      expect(find.textContaining('TODAY SO FAR'), findsNothing);
      expect(find.textContaining('begins today'), findsNothing);
      await done(tester);
    });

    testWidgets('loading, then the review; a failed read offers Try again', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester);
      final progress = CountingProgressRepository(
        DriftProgressRepository(db, clock),
      );
      await open(tester, AppRoutes.activeReview(2), progress: progress);
      expect(find.text('Week 2 review'), findsOneWidget);

      progress.gate = Completer<void>();
      progress.failNextLoads = 1;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WeeklyReviewScreen)),
      );
      // Only the review re-reads (the Journey beneath keeps its value).
      container.invalidate(weeklyReviewSourceProvider(null));
      await tester.pump();
      // While re-reading, the previous review stays on screen.
      expect(find.text('Week 2 review'), findsOneWidget);
      progress.gate!.complete();
      progress.gate = null;
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(FailureView), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Week 2 review'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a first load shows the labelled loading view', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      final progress = CountingProgressRepository(
        DriftProgressRepository(db, clock),
      )..gate = Completer<void>();
      await open(
        tester,
        AppRoutes.activeReview(2),
        progress: progress,
        settle: false,
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.descendant(
          of: find.byType(WeeklyReviewScreen),
          matching: find.byType(LoadingView),
        ),
        findsOneWidget,
      );
      progress.gate!.complete();
      progress.gate = null;
      await tester.pumpAndSettle();
      expect(find.text('Week 2 review'), findsOneWidget);
      await done(tester);
    });

    testWidgets('midnight with the review open keeps the week it opened with', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester);
      clock.current = DateTime(2026, 10, 22, 23, 59); // Day 14, Week 2
      await open(tester, AppRoutes.journeyReview); // no week: the default
      expect(find.text('Week 2 review'), findsOneWidget);
      expect(find.textContaining('In progress'), findsOneWidget);
      clock.current = DateTime(2026, 10, 23, 0, 0, 1); // Day 15, Week 3
      ProviderScope.containerOf(tester.element(find.byType(WeeklyReviewScreen)))
          .read(dayChangedProvider.notifier)
          .changed();
      await tester.pumpAndSettle();
      expect(find.text('Week 2 review'), findsOneWidget);
      expect(find.text('Fri 16 Oct – Thu 22 Oct · Complete'), findsOneWidget);
      expect(find.text('Week 3'), findsOneWidget);
      await done(tester);
    });
  });

  testWidgets('resume re-reads: a date change while away is shown, on the '
      'same week', (tester) async {
    tallPhone(tester);
    await seeded(tester);
    clock.current = DateTime(2026, 10, 22, 22); // Day 14, Week 2
    await open(tester, AppRoutes.activeReview(2));
    expect(find.text('Fri 16 Oct – Thu 22 Oct · In progress'), findsOneWidget);
    // Away overnight; no day-change tick reached the app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock.current = DateTime(2026, 10, 23, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Week 2 review'), findsOneWidget);
    expect(find.text('Fri 16 Oct – Thu 22 Oct · Complete'), findsOneWidget);
    await done(tester);
  });

  group('week strip and accessibility', () {
    testWidgets('every day labelled with its number, date and state; past '
        'days open the read-only detail; upcoming days are not buttons', (
      tester,
    ) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.activeReview(2));
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'^Day 8, Friday 16 October\. Perfect')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Day 13, Wednesday 21 October\. Today\. \d+ percent'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Day 14, Thursday 22 October. Upcoming.'),
        findsOneWidget,
      );
      for (var day = 8; day <= 14; day++) {
        final node = tester.getSemantics(dayCell(day));
        expect(node.flagsCollection.isButton, day <= 13, reason: 'Day $day');
      }
      await tester.tap(dayCell(10));
      await tester.pumpAndSettle();
      expect(find.byType(DayDetailSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DayDetailSheet),
          matching: find.byWidgetPredicate(
            (w) => w is ButtonStyleButton || w is IconButton || w is Checkbox,
          ),
        ),
        findsNothing,
        reason: 'read-only',
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(dayCell(14)); // upcoming: nothing opens
      await tester.pumpAndSettle();
      expect(find.byType(DayDetailSheet), findsNothing);
      handle.dispose();
      await done(tester);
    });

    testWidgets('stats, Today so far and highlights are single labelled '
        'nodes, read in the spec\'s order', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.activeReview(2));
      final handle = tester.ensureSemantics();
      final labels = [
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          node.label,
      ];
      int first(String prefix) =>
          labels.indexWhere((l) => l.startsWith(prefix));
      final order = [
        first(
          'Week 2 of 13. Days 8 to 14. Friday 16 October to Thursday 22 '
          'October. In progress.',
        ),
        labels.indexWhere(
          (l) => l.contains('this week') || l.contains('so far'),
        ),
        first('Day 8, '),
        first('Day 14, '),
        first('Habit completion: '),
        first('Consistency: '),
        first('XP earned: '),
        first('Perfect Days: '),
        first('Minimum Days: '),
        first('Today so far, Day 13: '),
        first('Most consistent this week: '),
        first('HABITS THIS WEEK'),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)), reason: '$labels');
      expect(order, orderedEquals([...order]..sort()), reason: '$labels');
      expect(
        labels[first('Today so far, Day 13: ')],
        matches(
          RegExp(
            r'^Today so far, Day 13: \d+ of \d+ habits, \d+ XP\. Today counts '
            r'once it ends\.$',
          ),
        ),
      );
      expect(
        labels[first('Habit completion: ')],
        matches(
          RegExp(
            r'^Habit completion: \d+ of \d+, \d+ percent\. 5 days '
            r'counted\.$',
          ),
        ),
      );
      expect(
        labels[first('Most consistent this week: ')],
        matches(RegExp(r'^Most consistent this week: .+, \d+ of \d+ days\.$')),
      );
      handle.dispose();
      await done(tester);
    });

    testWidgets('keyboard: Enter and Space open a day; week buttons work '
        'from the keyboard', (tester) async {
      tallPhone(tester);
      await seeded(tester);
      await open(tester, AppRoutes.activeReview(2));
      Future<void> focusCell(int day) async {
        final ink = find.descendant(
          of: dayCell(day),
          matching: find.byType(InkWell),
        );
        Focus.of(
          tester.element(
            find
                .descendant(of: ink.first, matching: find.byType(SizedBox))
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
      }

      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await focusCell(9);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(DayDetailSheet), findsOneWidget, reason: '$key');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
      final previous = find.widgetWithText(OutlinedButton, 'Week 1');
      Focus.of(
        tester.element(
          find.descendant(of: previous, matching: find.text('Week 1')),
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Week 1 review'), findsOneWidget);
      await done(tester);
    });

    testWidgets('meets Material\'s tap-target, label and contrast guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tallPhone(tester);
      await seeded(tester);
      for (final route in [
        AppRoutes.activeReview(2),
        AppRoutes.activeReview(1),
        AppRoutes.arcReview(seed.endedId, 1),
      ]) {
        await open(tester, route);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
      await done(tester);
    });

    testWidgets('reduced motion: nothing animates once shown', (tester) async {
      tallPhone(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seeded(tester);
      await open(tester, AppRoutes.activeReview(2));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await done(tester);
    });
  });

  test('the review code has no network, platform or storage access', () {
    final files = [
      ...Directory('lib/features/review').listSync(),
      ...Directory('lib/domain/review').listSync(),
      File('lib/domain/journey/arc_weeks.dart'),
    ].whereType<File>();
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final banned in [
        'package:http',
        'dart:io',
        'HttpClient',
        'url_launcher',
        'shared_preferences',
        'package:drift',
        'MethodChannel',
        'commitDay',
        'AchievementService',
        'reconcile(',
        'achievementSync',
        'journeyControllerProvider',
      ]) {
        expect(
          source,
          isNot(contains(banned)),
          reason: '${file.path}: $banned',
        );
      }
    }
  });
}
