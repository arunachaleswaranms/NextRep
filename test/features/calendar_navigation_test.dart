import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_achievement_repository.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/journey/widgets/arc_calendar_view.dart';
import 'package:nextrep/features/journey/widgets/day_detail_sheet.dart';
import 'package:nextrep/features/journey/widgets/journey_path.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';

import '../support/calendar_support.dart';
import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/review_fakes.dart';
import '../support/review_seed.dart';

/// Phase 12C: the Path | Calendar switch in the real app (spec § 7.1, K3,
/// K4): Path by default, no persistence, no new route or tab, the same
/// loaded Journey with zero extra reads, week headings opening the
/// existing Weekly Review for the right Arc, Back to the same Journey, the
/// shared Legend, and read-only day details. All data synthetic.

late AppDatabase db;
late FakeClock clock;
late ReviewSeed seed;

Future<void> seeded({bool paused = false}) async {
  db = memoryDatabase();
  addTearDown(db.close);
  clock = FakeClock(DateTime(2026, 7, 1));
  seed = await seedReviewData(
    TestApp(db, clock),
    pausedFrom: paused ? ReviewSeed.today : null,
  );
}

/// A tall phone, 360 dp wide.
void tallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 6000)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Repositories that count every call, over the seeded database.
typedef Counters = ({
  CountingProgressRepository progress,
  CountingSessionRepository sessions,
  CountingAchievementRepository achievements,
});

Counters counters() => (
  progress: CountingProgressRepository(DriftProgressRepository(db, clock)),
  sessions: CountingSessionRepository(DriftWinterArcRepository(db)),
  achievements: CountingAchievementRepository(DriftAchievementRepository(db)),
);

Future<void> open(WidgetTester tester, String route, {Counters? count}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpWidget(
    reviewApp(
      db,
      clock,
      route,
      progress: count?.progress,
      sessions: count?.sessions,
      achievements: count?.achievements,
    ),
  );
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

Uri location(WidgetTester tester, Type screen) =>
    GoRouterState.of(tester.element(find.byType(screen).first)).uri;

List<int> reads(Counters c) => [
  c.progress.loadArcCalls,
  c.progress.otherReads,
  c.sessions.reads,
  c.achievements.reads,
];

List<int> writes(Counters c) => [
  c.progress.writes,
  c.sessions.writes,
  c.achievements.writes,
];

void main() {
  testWidgets('Path is the default; the Calendar shows the same loaded '
      'Journey with zero extra reads or writes, switching repeatedly; no '
      'new route or tab', (tester) async {
    tallPhone(tester);
    await seeded();
    final count = counters();
    await open(tester, AppRoutes.journey, count: count);

    expect(selectedView(tester), JourneyView.path);
    expect(find.byType(JourneyPath), findsOneWidget);
    expect(find.byType(ArcCalendarView), findsNothing);
    final tabs = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(tabs.destinations, hasLength(4), reason: 'no new tab');
    expect(location(tester, JourneyScreen).toString(), AppRoutes.journey);
    final readsBefore = reads(count);
    final writesBefore = writes(count);
    expect(readsBefore.first, greaterThan(0), reason: 'the Journey loaded');

    for (var i = 0; i < 5; i++) {
      await choose(tester, 'Calendar');
      expect(selectedView(tester), JourneyView.calendar);
      expect(find.byType(ArcCalendarView), findsOneWidget);
      expect(find.byType(JourneyPath), findsNothing, reason: 'offstage');
      expect(dayCell(13), findsOneWidget);
      await choose(tester, 'Path');
      expect(find.byType(JourneyPath), findsOneWidget);
      expect(find.byType(ArcCalendarView), findsNothing, reason: 'offstage');
    }
    await choose(tester, 'Calendar');
    await reveal(tester, weekHeading(1));
    await reveal(tester, weekHeading(13));
    expect(location(tester, JourneyScreen).toString(), AppRoutes.journey);
    expect(
      reads(count),
      readsBefore,
      reason:
          'loadArc, other progress '
          'reads, session lookups, achievement reads',
    );
    expect(writes(count), writesBefore);

    // A fresh screen starts on Path again: the choice is not stored.
    await open(tester, AppRoutes.journey);
    expect(selectedView(tester), JourneyView.path);
    await done(tester);
  });

  testWidgets('the current week\'s heading opens its Weekly Review over the '
      'tabs; Back returns to the Calendar of the same Journey', (tester) async {
    tallPhone(tester);
    await seeded();
    await open(tester, AppRoutes.journey);
    await choose(tester, 'Calendar');
    // Opens on the current week (Week 2, Days 8–14, Day 13 today).
    expect(weekHeading(2).hitTestable(), findsOneWidget);
    expect(
      tester.getSemantics(weekHeading(2)).label,
      startsWith('Week 2 of 13, 16 to 22 October, '),
    );

    await tester.tap(weekHeading(2));
    await tester.pumpAndSettle();
    expect(find.text('Week 2 review'), findsOneWidget);
    expect(
      location(tester, WeeklyReviewScreen).toString(),
      '/journey/review?week=2',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(WeeklyReviewScreen), findsNothing);
    expect(selectedView(tester), JourneyView.calendar);
    expect(find.byType(ArcCalendarView), findsOneWidget);

    // Week 1 (above), then Back: one push, one pop, no growing stack.
    await reveal(tester, weekHeading(1));
    await tester.tap(weekHeading(1));
    await tester.pumpAndSettle();
    expect(find.text('Week 1 review'), findsOneWidget);
    expect(location(tester, WeeklyReviewScreen).queryParameters['week'], '1');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('JOURNEY'), findsOneWidget);
    expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    expect(selectedView(tester), JourneyView.calendar);
    await done(tester);
  });

  testWidgets('upcoming weeks are information, not buttons', (tester) async {
    tallPhone(tester);
    await seeded();
    await open(tester, AppRoutes.journey);
    await choose(tester, 'Calendar');
    await reveal(tester, weekHeading(3));
    final node = tester.getSemantics(weekHeading(3));
    expect(node.label, endsWith(', upcoming.'));
    expect(node.label, isNot(contains('Opens')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(node.flagsCollection.isButton, isFalse);
    expect(node.flagsCollection.isHeader, isTrue);
    await tester.tap(weekHeading(3));
    await tester.pumpAndSettle();
    expect(find.byType(WeeklyReviewScreen), findsNothing);
    await done(tester);
  });

  testWidgets('a completed Arc: opens on Week 13; its heading opens that '
      'Arc\'s review; Back returns to the same historical Journey', (
    tester,
  ) async {
    tallPhone(tester);
    await seeded();
    await open(tester, AppRoutes.arcJourney(seed.completedId));
    await choose(tester, 'Calendar');
    expect(weekHeading(13).hitTestable(), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Not reached')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Day \d+, .*\. Today\.')),
      findsNothing,
    );
    await tester.tap(weekHeading(13));
    await tester.pumpAndSettle();
    expect(find.text('Week 13 review'), findsOneWidget);
    expect(
      location(tester, WeeklyReviewScreen).toString(),
      AppRoutes.arcReview(seed.completedId, 13),
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final screen = tester.widget<JourneyScreen>(find.byType(JourneyScreen));
    expect(screen.sessionId, seed.completedId);
    expect(selectedView(tester), JourneyView.calendar);
    await done(tester);
  });

  testWidgets('an ended Arc: its own days, later days not reached, later '
      'weeks not reviewable, its last week opens its review', (tester) async {
    tallPhone(tester);
    await seeded();
    await open(tester, AppRoutes.arcJourney(seed.endedId));
    await choose(tester, 'Calendar');
    // Ended on Day 3: Week 1 is its last week.
    expect(weekHeading(1).hitTestable(), findsOneWidget);
    expect(find.bySemanticsLabel('Day 4. Not reached.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\. Today\.')), findsNothing);
    final later = tester.getSemantics(weekHeading(2));
    expect(later.label, endsWith(', not reached.'));
    expect(later.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    final notReached = tester.getSemantics(
      find.bySemanticsLabel('Day 4. Not reached.'),
    );
    expect(
      notReached.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(weekHeading(1));
    await tester.pumpAndSettle();
    expect(
      location(tester, WeeklyReviewScreen).toString(),
      AppRoutes.arcReview(seed.endedId, 1),
    );
    await done(tester);
  });

  testWidgets('a paused Arc opens on its paused week with "Paused since" '
      'and undated later days', (tester) async {
    tallPhone(tester);
    await seeded(paused: true);
    await open(tester, AppRoutes.journey);
    await choose(tester, 'Calendar');
    expect(weekHeading(2).hitTestable(), findsOneWidget);
    expect(
      tester.getSemantics(weekHeading(2)).label,
      contains('paused. Opens the week review.'),
    );
    expect(find.bySemanticsLabel('Paused since 21 Oct'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Day 14. Upcoming. Its date is set when you resume.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'\. Today\.')), findsNothing);
    await done(tester);
  });

  testWidgets('the Legend opens from both views with the shared words; '
      'Not reached only for an ended Arc', (tester) async {
    tallPhone(tester);
    await seeded();
    Future<List<String>> legend() async {
      await tester.tap(find.byTooltip('Legend'));
      await tester.pumpAndSettle();
      final sheet = find.ancestor(
        of: find.text('Legend'),
        matching: find.byType(BottomSheet),
      );
      final words = [
        for (final t in tester.widgetList<Text>(
          find.descendant(of: sheet, matching: find.byType(Text)),
        ))
          t.data ?? '',
      ];
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      return words;
    }

    await open(tester, AppRoutes.journey);
    final path = await legend();
    await choose(tester, 'Calendar');
    final calendar = await legend();
    expect(calendar, path);
    expect(path, contains('No progress'));
    expect(path, isNot(contains('Missed')));
    expect(path, isNot(contains('Not reached')));
    expect(path, isNot(contains('Before you joined')));

    await open(tester, AppRoutes.arcJourney(seed.endedId));
    await choose(tester, 'Calendar');
    expect(await legend(), contains('Not reached'));
    await done(tester);
  });

  testWidgets('day taps open the read-only sheets: today, a past day, a '
      'completed Minimum Day; upcoming days do nothing', (tester) async {
    tallPhone(tester);
    await seeded();
    await open(tester, AppRoutes.journey);
    await choose(tester, 'Calendar');

    Future<void> openDay(int day) async {
      await reveal(tester, dayCell(day));
      await tester.tap(dayCell(day));
      await tester.pumpAndSettle();
    }

    Future<void> dismiss() async {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    await openDay(13);
    expect(find.byType(DayDetailSheet), findsOneWidget);
    expect(find.text('Day 13'), findsWidgets);
    final sheet = find.byType(DayDetailSheet);
    for (final editable in [
      TextField,
      Checkbox,
      Switch,
      FilledButton,
      ElevatedButton,
      OutlinedButton,
      TextButton,
      IconButton,
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.byType(editable)),
        findsNothing,
        reason: 'read-only: no $editable',
      );
    }
    await dismiss();

    // Day 6 (14 Oct): a completed Minimum Day; Day 7: nothing logged.
    await openDay(6);
    expect(find.text('MINIMUM COMPLETE'), findsOneWidget);
    expect(find.text('Minimum Day'), findsWidgets);
    expect(find.text('PERFECT'), findsNothing);
    await dismiss();
    await openDay(7);
    expect(find.text('NO PROGRESS'), findsOneWidget);
    await dismiss();
    expect(
      tester.getSemantics(dayCell(7)).label,
      'Day 7, Thursday 15 October. No progress.',
    );

    // Day 14 is tomorrow: not a button, nothing opens.
    await reveal(tester, dayCell(14));
    expect(
      tester
          .getSemantics(dayCell(14))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(dayCell(14));
    await tester.pumpAndSettle();
    expect(find.byType(DayDetailSheet), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await done(tester);
  });
}
