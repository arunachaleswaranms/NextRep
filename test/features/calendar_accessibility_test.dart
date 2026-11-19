import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/journey/journey_overview.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/journey/widgets/arc_calendar_view.dart';

import '../support/arcs.dart';
import '../support/calendar_support.dart';
import '../support/fakes.dart';
import '../support/lifecycle_arcs.dart';
import '../support/review_app.dart';
import '../support/review_arcs.dart';
import '../support/review_db.dart';
import '../support/review_seed.dart';

/// Phase 12C: accessibility of the Arc Consistency Calendar (spec § 8,
/// A5, A7, A9, A10; brief § 23): every cell's announcement with its number,
/// date and state for all nine states; buttons only where something opens;
/// the reading order switch → week heading → its days (pause rows in place)
/// → the next week; one focus group per week; Material's tap-target, label
/// and contrast guidelines in the real app. Manual TalkBack is Phase 12H.
/// All data synthetic.

Widget bare(JourneyOverview journey) => MaterialApp(
  theme: buildWinterTheme(),
  home: Scaffold(body: ArcCalendarView(journey: journey, historical: false)),
);

void tall(WidgetTester tester, {double height = 9000}) {
  tester.view
    ..physicalSize = Size(1080, height)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

SemanticsNode node(WidgetTester tester, Finder f) => tester.getSemantics(f);
bool isButton(SemanticsNode n) => n.flagsCollection.isButton;
bool taps(SemanticsNode n) =>
    n.getSemanticsData().hasAction(SemanticsAction.tap);

Future<void> openApp(
  WidgetTester tester,
  AppDatabase db,
  FakeClock clock,
  String route,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpWidget(reviewApp(db, clock, route));
  await tester.pumpAndSettle();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('all nine states announced in words with number and date; '
      'buttons exactly where a sheet opens', (tester) async {
    tall(tester);
    final handle = tester.ensureSemantics();
    final seasonal = historyOf(
      seasonalArc(2026, joined: LocalDate(2026, 10, 18)),
      LocalDate(2026, 10, 27),
      days: {
        LocalDate(2026, 10, 18): day(allFive),
        LocalDate(2026, 10, 19): day(allFive, mode: DayMode.minimum),
        LocalDate(2026, 10, 20): day({'water'}),
        LocalDate(2026, 10, 21): day({'water'}, mode: DayMode.minimum),
        LocalDate(2026, 10, 27): day({'water', 'reading'}),
      },
    );
    await tester.pumpWidget(bare(JourneyOverview.fromHistory(seasonal)));
    await tester.pumpAndSettle();
    final expected = {
      8: (
        'Day 8, Thursday 8 October. Before you joined this Seasonal Winter '
            'Arc.',
        true,
      ),
      18: ('Day 18, Sunday 18 October. Perfect Day.', true),
      19: ('Day 19, Monday 19 October. Minimum Day completed.', true),
      20: ('Day 20, Tuesday 20 October. Partial, 20 percent complete.', true),
      21: (
        'Day 21, Wednesday 21 October. Minimum Day, 20 percent complete.',
        true,
      ),
      22: ('Day 22, Thursday 22 October. No progress.', true),
      27: ('Day 27, Tuesday 27 October. Today. 40 percent complete.', true),
      28: ('Day 28, Wednesday 28 October. Upcoming.', false),
    };
    for (final MapEntry(key: d, value: (label, button)) in expected.entries) {
      final n = node(tester, dayCell(d));
      expect(n.label, label, reason: 'Day $d');
      expect(isButton(n), button, reason: 'Day $d');
      expect(taps(n), button, reason: 'Day $d');
    }
    for (var d = 1; d <= 92; d++) {
      final n = node(tester, dayCell(d));
      expect(n.label, matches(RegExp('^Day $d[,.] .+\\.\$')));
    }

    final start = LocalDate(2027, 3, 1);
    final ended = historyOf(
      rollingArc(
        start,
        status: WinterArcStatus.ended,
        closedOn: start.addDays(42),
      ),
      start.addDays(60),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(bare(JourneyOverview.fromHistory(ended)));
    await tester.pumpAndSettle();
    final notReached = node(tester, dayCell(44));
    expect(notReached.label, 'Day 44. Not reached.');
    expect(isButton(notReached), isFalse);
    expect(taps(notReached), isFalse);
    handle.dispose();
  });

  testWidgets('one reading-order focus group per week; headings are '
      'semantic headers', (tester) async {
    tall(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      bare(
        JourneyOverview.fromHistory(
          historyOf(rollingArc(LocalDate(2026, 10, 7)), LocalDate(2026, 11, 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final groups = tester.widgetList<FocusTraversalGroup>(
      find.descendant(
        of: find.byType(ArcCalendarView),
        matching: find.byType(FocusTraversalGroup),
      ),
    );
    expect(groups, hasLength(13));
    expect(
      groups.map((g) => g.policy),
      everyElement(isA<ReadingOrderTraversalPolicy>()),
    );
    for (var w = 1; w <= 13; w++) {
      expect(node(tester, weekHeading(w)).flagsCollection.isHeader, isTrue);
    }
    handle.dispose();
  });

  testWidgets('reading order: the switch, then each week\'s heading and its '
      'days in Arc order with the pause row in place, Week 1 to Week 13', (
    tester,
  ) async {
    tall(tester);
    final handle = tester.ensureSemantics();
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 7, 1));
    await seedReviewData(TestApp(db, clock));
    await openApp(tester, db, clock, AppRoutes.journey);
    await choose(tester, 'Calendar');
    final nodes = tester.semantics.simulatedAccessibilityTraversal().toList();
    final labels = [for (final n in nodes) n.label];
    int at(Pattern p) => labels.indexWhere(
      (l) => p is RegExp ? p.hasMatch(l) : l.startsWith(p as String),
    );
    // A segment is a button node whose words are its child's label.
    int segmentAt(String label) {
      SemanticsNode? n = tester.getSemantics(segment(label));
      while (n != null && !nodes.contains(n)) {
        n = n.parent;
      }
      return n == null ? -1 : nodes.indexOf(n);
    }

    final order = [
      segmentAt('Path'),
      segmentAt('Calendar'),
      at('Week 1 of 13, 6 to 15 October, '),
      at('Frozen Forest begins on Day 1'),
      for (var d = 1; d <= 3; d++) at('Day $d,'),
      at('Paused 9–11 Oct · 3 days'),
      for (var d = 4; d <= 7; d++) at('Day $d,'),
      for (var w = 2; w <= 13; w++) ...[
        at('Week $w of 13,'),
        if (w == 3) at('First Ascent begins on Day 15'),
        for (var d = 7 * (w - 1) + 1; d <= (w == 13 ? 92 : 7 * w); d++)
          at(RegExp('^Day $d[,.]')),
      ],
    ];
    expect(order, everyElement(greaterThanOrEqualTo(0)), reason: '$labels');
    expect(order, orderedEquals([...order]..sort()), reason: '$labels');
    expect(
      labels[at('Week 2 of 13,')],
      'Week 2 of 13, 16 to 22 October, 5 of 5 days full, this week. Opens '
      'the week review.',
    );
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Material\'s tap-target, labelled-target and text-contrast '
      'guidelines: active, paused, ended and late-joined Calendars', (
    tester,
  ) async {
    tall(tester, height: 6000);
    final handle = tester.ensureSemantics();
    Future<void> check(String why) async {
      await expectLater(
        tester,
        meetsGuideline(androidTapTargetGuideline),
        reason: why,
      );
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: why,
      );
      await expectLater(
        tester,
        meetsGuideline(textContrastGuideline),
        reason: why,
      );
    }

    for (final paused in [false, true]) {
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 7, 1));
      final seed = await seedReviewData(
        TestApp(db, clock),
        pausedFrom: paused ? ReviewSeed.today : null,
      );
      await openApp(tester, db, clock, AppRoutes.journey);
      await choose(tester, 'Calendar');
      await check(paused ? 'paused' : 'active');
      if (!paused) {
        await openApp(tester, db, clock, AppRoutes.arcJourney(seed.endedId));
        await choose(tester, 'Calendar');
        await check('ended');
      }
    }

    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 1));
    final app = TestApp(db, clock);
    await joinSeason(app, DateTime(2026, 10, 18));
    at(app, LocalDate(2026, 10, 18));
    await completeAll(app);
    at(app, LocalDate(2026, 10, 19), hour: 13);
    await openApp(tester, db, clock, AppRoutes.journey);
    await choose(tester, 'Calendar');
    await reveal(tester, weekHeading(1));
    await check('late-joined Seasonal');
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
