import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/journey_overview.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/journey/widgets/journey_path.dart';

import '../support/builders.dart' as b;
import '../support/lifecycle_arcs.dart';

/// Review finding R1 on the Journey itself: an ended arc's last day, viewed
/// on its own date, is settled history. It is not announced, labelled,
/// lit or scrolled to as an open today, and the trail stops at it. Active
/// and completed arcs are unchanged. All data is synthetic.

/// [session] as of [today], two habits (target 8): [perfect] dates have
/// both complete, [partial] dates have water at 2.
JourneyOverview _journey(
  WinterArcSession session,
  LocalDate today, {
  Set<LocalDate> perfect = const {},
  Set<LocalDate> partial = const {},
}) => JourneyOverview.fromHistory(
  ArcHistory(
    session: session,
    today: today,
    records: ArcRecords(
      habits: HabitHistory(
        habits: [
          b.habit('water', target: 8, minimum: 3, sortOrder: 0),
          b.habit('junk', target: 8, minimum: 3, sortOrder: 1),
        ],
      ),
      progress: <DailyHabitProgress>[
        for (final d in perfect) ...[
          b.progress('water', d, 8),
          b.progress('junk', d, 8),
        ],
        for (final d in partial) b.progress('water', d, 2, completed: false),
      ],
      modes: const {},
      xpByDate: const {},
      totalXp: 0,
    ),
  ),
);

/// Shows [journey] on a 360 × 800 dp phone and returns the path's height.
Future<double> _show(WidgetTester tester, JourneyOverview journey) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWinterTheme(),
      home: Scaffold(body: JourneyPath(journey: journey)),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(JourneyPath)).height;
}

/// The scroll offset the path opened at.
double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(JourneyPath),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

/// The offset that centres challenge day [day] of [journey].
double _offsetOfDay(JourneyOverview journey, int day, double viewport) {
  final layout = JourneyPathLayout(journey.days);
  return layout.offsetToShow(layout.indexOfDay(day), viewport);
}

void main() {
  // The review's example: Rolling Arc from 7 Oct 2026; Day 1 Perfect, Day 2
  // missed, Day 3 partial; ended with closedOn 9 Oct.
  final start = LocalDate(2026, 10, 7);
  final closed = LocalDate(2026, 10, 9);

  testWidgets('L. an ended arc viewed on closedOn never announces Today', (
    tester,
  ) async {
    final journey = _journey(
      rollingArc(start, status: WinterArcStatus.ended, closedOn: closed),
      closed,
      perfect: {start},
      partial: {closed},
    );
    await _show(tester, journey);

    expect(find.bySemanticsLabel('Day 1. Perfect Day.'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 2. Missed.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Day 3\. Partial, \d+ percent complete\.$'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Day 4. Not reached.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Today')), findsNothing);
    expect(find.textContaining('TODAY'), findsNothing);
    expect(find.text('Day 3 · 9 Oct'), findsOneWidget);
  });

  testWidgets('M. an ended arc opens on its last day, not as today, and the '
      'trail stops there; the active arc of the same date is unchanged', (
    tester,
  ) async {
    final day40 = start.addDays(39);
    final ended = _journey(
      rollingArc(start, status: WinterArcStatus.ended, closedOn: day40),
      day40,
      partial: {day40},
    );
    final viewport = await _show(tester, ended);
    expect(_offset(tester), _offsetOfDay(ended, 40, viewport));
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Day 40\. Partial, \d+ percent complete\.$'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Today')), findsNothing);
    expect(find.textContaining('TODAY'), findsNothing);
    expect(find.text('Day 40 · 15 Nov'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 41. Not reached.'), findsOneWidget);

    // The active arc on the same date: today's marker, label and position.
    await tester.pumpWidget(const SizedBox());
    final active = _journey(rollingArc(start), day40, partial: {day40});
    await _show(tester, active);
    expect(_offset(tester), _offsetOfDay(active, 40, viewport));
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Day 40\. Today\. \d+ percent complete\.$'),
      ),
      findsOneWidget,
    );
    expect(find.text('TODAY · Day 40'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 41. Upcoming.'), findsOneWidget);
  });

  testWidgets('M. an arc ended on Day 92 never reaches the Summit; a '
      'completed arc does', (tester) async {
    final endedArc = rollingArc(
      start,
      status: WinterArcStatus.ended,
      closedOn: WinterArcRules.endDateFor(start),
    );
    for (final today in [endedArc.endDate, endedArc.endDate.addDays(5)]) {
      await tester.pumpWidget(const SizedBox());
      final ended = _journey(endedArc, today, perfect: {endedArc.endDate});
      final viewport = await _show(tester, ended);
      expect(
        _offset(tester),
        _offsetOfDay(ended, 92, viewport),
        reason: '$today',
      );
      expect(find.bySemanticsLabel('Day 92. Perfect Day.'), findsOneWidget);
      expect(find.bySemanticsLabel('Summit, Day 92'), findsOneWidget);
      expect(find.bySemanticsLabel('Summit, Day 92, reached'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Today')), findsNothing);
    }

    await tester.pumpWidget(const SizedBox());
    final completedArc = rollingArc(start, status: WinterArcStatus.completed);
    await _show(
      tester,
      _journey(completedArc, completedArc.endDate.addDays(1)),
    );
    expect(find.bySemanticsLabel('Summit, Day 92, reached'), findsOneWidget);
  });
}
