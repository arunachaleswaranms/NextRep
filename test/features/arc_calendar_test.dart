import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/app/theme/winter_tokens.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/journey/journey_overview.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/journey/widgets/arc_calendar_view.dart';
import 'package:nextrep/features/journey/widgets/calendar_day_cell.dart';
import 'package:nextrep/features/journey/widgets/day_detail_sheet.dart';
import 'package:nextrep/features/journey/widgets/journey_day_style.dart';

import '../support/calendar_support.dart';
import '../support/lifecycle_arcs.dart';
import '../support/review_arcs.dart';

/// Phase 12C: the Arc Consistency Calendar widget on synthetic Journeys
/// (spec §§ 7.2–7.4, 8, 12.4; K1–K3, K7): 92 cells in 13 blocks, Week 13's
/// wrap, equal cells with visible day numbers, every state's glyph, the
/// Today border, pause rows, taps, week-heading links, 7 or 4 days a line,
/// the initial week and its scroll, high contrast and reduced motion. All
/// data synthetic.

final _routes = <String>[];

Widget host(
  JourneyOverview journey, {
  bool historical = false,
  bool highContrast = false,
  ValueNotifier<JourneyOverview>? live,
}) {
  _routes.clear();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: live == null
              ? ArcCalendarView(journey: journey, historical: historical)
              : ValueListenableBuilder(
                  valueListenable: live,
                  builder: (context, value, _) =>
                      ArcCalendarView(journey: value, historical: historical),
                ),
        ),
      ),
      GoRoute(
        path: '/journey/review',
        builder: (context, state) {
          _routes.add(state.uri.toString());
          return const Scaffold(body: Text('review'));
        },
      ),
      GoRoute(
        path: '/arc/:id/review',
        builder: (context, state) {
          _routes.add(state.uri.toString());
          return const Scaffold(body: Text('review'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  return MaterialApp.router(
    theme: buildWinterTheme(),
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: child!,
    ),
  );
}

void screen(WidgetTester tester, Size size, {double text = 1}) {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Tall enough that every week is laid out at once.
void everything(WidgetTester tester, {double width = 360, double text = 1}) =>
    screen(tester, Size(width, 9000), text: text);

final wed = LocalDate(2026, 10, 7);

/// A Seasonal 2026 Arc joined on Day 18 (18 Oct), viewed on Day 27 (27
/// Oct), with every state of an active Arc.
ArcHistory seasonalHistory() => historyOf(
  seasonalArc(2026, joined: LocalDate(2026, 10, 18)),
  LocalDate(2026, 10, 27),
  days: {
    LocalDate(2026, 10, 18): day(allFive), // Day 18: Perfect
    LocalDate(2026, 10, 19): day(allFive, mode: DayMode.minimum), // 19
    LocalDate(2026, 10, 20): day({'water'}), // Day 20: partial
    LocalDate(2026, 10, 21): day({'water'}, mode: DayMode.minimum), // 21
    // Day 22: nothing at all; Day 23: a Minimum Day, nothing done.
    LocalDate(2026, 10, 23): day(const {}, mode: DayMode.minimum),
    LocalDate(2026, 10, 27): day({'water', 'reading'}), // today
  },
);

JourneyOverview journeyOf(ArcHistory h) => JourneyOverview.fromHistory(h);

Finder glyphOf(int day) =>
    find.descendant(of: dayCell(day), matching: find.byType(CalendarGlyph));

CalendarGlyph glyph(WidgetTester tester, int day) =>
    tester.widget<CalendarGlyph>(glyphOf(day));

BoxDecoration decoration(WidgetTester tester, int day) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: glyphOf(day),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Future<void> pumpCalendar(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('92 cells in 13 week blocks; Week 13 wraps Day 92 onto its own '
      'line; equal cells; every day number visible', (tester) async {
    everything(tester);
    await pumpCalendar(tester, host(journeyOf(seasonalHistory())));
    expect(find.byType(CalendarDayCell), findsNWidgets(92));
    expect(
      find.bySemanticsLabel(RegExp(r'^Week \d+ of 13,')),
      findsNWidgets(13),
    );
    expect(find.bySemanticsLabel(RegExp(r'^Week 14')), findsNothing);
    final sizes = {
      for (final e in find.byType(CalendarDayCell).evaluate())
        tester.getSize(find.byWidget(e.widget)),
    };
    expect(sizes, hasLength(1), reason: 'equal cells: $sizes');
    expect(sizes.single.width, greaterThanOrEqualTo(48));
    expect(sizes.single.height, greaterThanOrEqualTo(48));
    for (var d = 1; d <= 92; d++) {
      expect(
        find.descendant(of: dayCell(d), matching: find.text('$d')),
        findsOneWidget,
        reason: 'Day $d shows its number',
      );
    }
    double top(int d) => tester.getTopLeft(dayCell(d)).dy;
    expect({for (var d = 85; d <= 91; d++) top(d)}, hasLength(1));
    expect(top(92), greaterThan(top(91)));
    expect(
      tester.getTopLeft(dayCell(92)).dx,
      tester.getTopLeft(dayCell(85)).dx,
    );
    for (var w = 1; w <= 12; w++) {
      final first = 7 * (w - 1) + 1;
      expect(
        {for (var d = first; d < first + 7; d++) top(d)},
        hasLength(1),
        reason: 'Week $w is one line of 7',
      );
    }
  });

  testWidgets('7 a line from 352 dp at ≤ 1.3× text; otherwise 4 a line, '
      'Week 13 as 4 + 4; never wider than 600 dp', (tester) async {
    final journey = journeyOf(historyOf(rollingArc(wed), wed));
    for (final (width, text, perLine) in [
      (360.0, 1.0, 7),
      (352.0, 1.3, 7),
      (351.0, 1.0, 4),
      (320.0, 1.0, 4),
      (360.0, 1.31, 4),
      (360.0, 2.0, 4),
      (1280.0, 1.0, 7),
    ]) {
      everything(tester, width: width, text: text);
      await pumpCalendar(tester, host(journey));
      final why = '$width dp at $text×';
      expect(ArcCalendarView.daysPerLine(width.clamp(0, 600), text), perLine);
      double top(int d) => tester.getTopLeft(dayCell(d)).dy;
      expect(
        {for (var d = 1; d <= 7; d++) top(d)},
        hasLength(perLine == 7 ? 1 : 2),
        reason: why,
      );
      expect(
        {for (var d = 85; d <= 92; d++) top(d)},
        hasLength(2),
        reason: why,
      );
      if (perLine == 4) {
        expect(top(88), top(85), reason: why);
        expect(top(89), greaterThan(top(88)), reason: why);
        expect(top(92), top(89), reason: why);
      }
      final left = tester.getTopLeft(dayCell(1)).dx;
      final right = tester.getTopRight(dayCell(perLine)).dx;
      expect(right - left, lessThanOrEqualTo(600), reason: why);
      for (final d in [1, 50, 92]) {
        final size = tester.getSize(dayCell(d));
        expect(size.width, greaterThanOrEqualTo(48), reason: why);
        expect(size.height, greaterThanOrEqualTo(48), reason: why);
      }
      expect(tester.takeException(), isNull, reason: why);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('each state\'s glyph comes from JourneyDayStyle; outlines are '
      'never dimmed; Minimum is a square with a flame, Perfect a circle with '
      'a star', (tester) async {
    everything(tester);
    await pumpCalendar(tester, host(journeyOf(seasonalHistory())));
    const colors = WinterColors.night;
    final expected = {
      8: JourneyDayState.notJoined,
      18: JourneyDayState.perfect,
      19: JourneyDayState.minimumComplete,
      20: JourneyDayState.partial,
      21: JourneyDayState.minimumPartial,
      22: JourneyDayState.missed,
      23: JourneyDayState.missed,
      27: JourneyDayState.today,
      28: JourneyDayState.future,
    };
    for (final MapEntry(key: d, value: state) in expected.entries) {
      final g = glyph(tester, d);
      expect(g.state, state, reason: 'Day $d');
      final box = decoration(tester, d);
      final radius = box.borderRadius! as BorderRadius;
      expect(
        radius.topLeft.x,
        state.square ? CalendarGlyph.size * 0.3 : CalendarGlyph.size,
        reason: 'Day $d shape',
      );
      if (state.dashed) {
        expect(box.border, isNull, reason: 'painted dashed instead');
      } else {
        final side = (box.border! as Border).top;
        expect(side.color.a, 1, reason: 'Day $d outline at full opacity');
        expect(
          side.color,
          d == 27 ? colors.snow : calendarOutlineColor(state, colors),
        );
        expect(side.width, d == 27 ? 3 : 1.5);
      }
      expect(
        find.descendant(
          of: glyphOf(d),
          matching: find.byIcon(state.icon ?? Icons.abc),
        ),
        state.icon == null ? findsNothing : findsOneWidget,
        reason: 'Day $d icon',
      );
      switch (state.fill) {
        case MarkerFill.full:
          expect(box.color, isNotNull);
        case MarkerFill.half:
          expect(box.gradient, isNotNull);
        case MarkerFill.none:
          expect(box.gradient, isNull);
      }
    }
    expect(glyph(tester, 19).state, isNot(JourneyDayState.perfect));
    expect(
      tester.getSemantics(dayCell(19)).label,
      'Day 19, Monday 19 October. Minimum Day completed.',
    );
    expect(
      tester.getSemantics(dayCell(23)).label,
      'Day 23, Friday 23 October. No progress.',
    );
  });

  testWidgets('one Today cell with the 3 dp snow border, also when it is '
      'already a Perfect Day; none on an ended Arc', (tester) async {
    everything(tester);
    final perfectToday = historyOf(
      rollingArc(wed),
      wed.addDays(2),
      days: {wed.addDays(2): day(allFive)},
    );
    await pumpCalendar(tester, host(journeyOf(perfectToday)));
    final todays = [
      for (final e in find.byType(CalendarGlyph).evaluate())
        if ((e.widget as CalendarGlyph).isToday) e.widget as CalendarGlyph,
    ];
    expect(todays, hasLength(1));
    expect(todays.single.state, JourneyDayState.perfect);
    expect((decoration(tester, 3).border! as Border).top.width, 3);
    expect(
      tester.getSemantics(dayCell(3)).label,
      'Day 3, Friday 9 October. Today. Perfect Day.',
    );

    final closedOn = wed.addDays(20);
    final ended = historyOf(
      rollingArc(wed, status: WinterArcStatus.ended, closedOn: closedOn),
      closedOn,
      days: {closedOn: day(allFive)},
    );
    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(tester, host(journeyOf(ended), historical: true));
    expect(
      find.byWidgetPredicate((w) => w is CalendarGlyph && w.isToday),
      findsNothing,
    );
    expect(glyph(tester, 21).state, JourneyDayState.perfect);
    expect(glyph(tester, 22).state, JourneyDayState.notReached);
  });

  testWidgets('taps: past days and today open the read-only detail; a day '
      'before joining its note; upcoming days nothing', (tester) async {
    everything(tester);
    await pumpCalendar(tester, host(journeyOf(seasonalHistory())));
    for (final d in [18, 23, 27]) {
      await tester.tap(dayCell(d));
      await tester.pumpAndSettle();
      expect(find.byType(DayDetailSheet), findsOneWidget, reason: 'Day $d');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
    // A Minimum Day with no progress keeps its Minimum Day label.
    await tester.tap(dayCell(23));
    await tester.pumpAndSettle();
    expect(find.text('NO PROGRESS'), findsOneWidget);
    expect(find.text('Minimum Day'), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(dayCell(8));
    await tester.pumpAndSettle();
    expect(find.byType(NotJoinedDaySheet), findsOneWidget);
    expect(
      find.textContaining(
        'You joined on Day 18. Earlier season days are not '
        'counted against you.',
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(dayCell(28));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final upcoming = tester.getSemantics(dayCell(28));
    expect(upcoming.flagsCollection.isButton, isFalse);
    expect(upcoming.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
  });

  testWidgets('reviewable headings open the active review, or the historical '
      'Arc\'s; other headings are not buttons', (tester) async {
    everything(tester);
    final h = seasonalHistory();
    await pumpCalendar(tester, host(journeyOf(h)));
    await tester.tap(weekHeading(3));
    await tester.pumpAndSettle();
    expect(_routes, ['/journey/review?week=3']);

    for (final w in [1, 2, 5, 13]) {
      await pumpCalendar(tester, host(journeyOf(h)));
      final node = tester.getSemantics(weekHeading(w));
      expect(node.flagsCollection.isButton, isFalse, reason: 'Week $w');
      expect(node.label, isNot(contains('Opens')));
      await tester.tap(weekHeading(w));
      await tester.pumpAndSettle();
      expect(_routes, isEmpty, reason: 'Week $w');
    }

    final completed = historyOf(
      rollingArc(wed, status: WinterArcStatus.completed, id: 7),
      wed.addDays(120),
    );
    await pumpCalendar(tester, host(journeyOf(completed), historical: true));
    await tester.tap(weekHeading(13));
    await tester.pumpAndSettle();
    expect(_routes, ['/arc/7/review?week=13']);
  });

  testWidgets('pause rows: one labelled row each, not a cell or a button; an '
      'open pause names no end', (tester) async {
    everything(tester);
    final start = LocalDate(2027, 3, 1);
    final closed = historyOf(
      rollingArc(
        start,
        freezes: [
          closedFreeze(LocalDate(2027, 3, 11), 9),
          closedFreeze(start.addDays(98), 2),
        ],
      ),
      start.addDays(140),
    );
    await pumpCalendar(tester, host(journeyOf(closed)));
    final first = find.bySemanticsLabel('Paused 11–19 Mar · 9 days');
    expect(first, findsOneWidget);
    expect(find.text('Paused 11–19 Mar · 9 days'), findsOneWidget);
    expect(tester.getSemantics(first).flagsCollection.isButton, isFalse);
    expect(find.bySemanticsLabel(RegExp('^Paused ')), findsNWidgets(2));
    expect(find.byType(CalendarDayCell), findsNWidgets(92));
    // Between Day 10 and Day 11, in Arc order.
    final row = tester.getRect(first);
    expect(row.top, greaterThan(tester.getRect(dayCell(10)).bottom - 1));
    expect(row.bottom, lessThan(tester.getRect(dayCell(11)).top + 1));

    final open = historyOf(
      rollingArc(start, freezes: [openFreeze(LocalDate(2027, 3, 11))]),
      LocalDate(2027, 3, 20),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(tester, host(journeyOf(open)));
    expect(find.bySemanticsLabel('Paused since 11 Mar'), findsOneWidget);
    expect(find.textContaining(' · 9 days'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Day 11. Upcoming. Its date is set when you resume.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens on the current week; a completed Arc on Week 13 with '
      'the weeks above filling the view; Week 1 and Week 13 reachable', (
    tester,
  ) async {
    screen(tester, const Size(360, 800));
    final active = historyOf(rollingArc(wed), wed.addDays(45)); // Day 46
    await pumpCalendar(tester, host(journeyOf(active)));
    expect(weekHeading(7).hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(weekHeading(7)).dy,
      lessThan(40),
      reason: 'the current week at the top',
    );
    await reveal(tester, weekHeading(1));
    expect(weekHeading(1).hitTestable(), findsOneWidget);
    await reveal(tester, dayCell(92));
    expect(dayCell(92).hitTestable(), findsOneWidget);

    final completed = historyOf(
      rollingArc(wed, status: WinterArcStatus.completed),
      wed.addDays(150),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(tester, host(journeyOf(completed), historical: true));
    expect(weekHeading(13).hitTestable(), findsOneWidget);
    expect(dayCell(92).hitTestable(), findsOneWidget);
    expect(weekHeading(12).hitTestable(), findsOneWidget, reason: 'no blank');
    final bottom = tester.getBottomLeft(dayCell(92)).dy;
    expect(bottom, greaterThan(800 - 120), reason: 'Week 13 at the bottom');

    final closedOn = wed.addDays(30); // Day 31, Week 5
    final ended = historyOf(
      rollingArc(wed, status: WinterArcStatus.ended, closedOn: closedOn),
      closedOn.addDays(40),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(tester, host(journeyOf(ended), historical: true));
    expect(weekHeading(5).hitTestable(), findsOneWidget);
  });

  testWidgets('a refresh with a new Journey keeps the scroll position and '
      'the initial week', (tester) async {
    screen(tester, const Size(360, 800));
    final s = rollingArc(wed);
    final live = ValueNotifier(journeyOf(historyOf(s, wed.addDays(45))));
    addTearDown(live.dispose);
    await pumpCalendar(tester, host(live.value, live: live));
    final position = tester
        .state<ScrollableState>(calendarScrollable())
        .position;
    position.jumpTo(position.pixels - 300);
    await tester.pumpAndSettle();
    final before = position.pixels;
    final state = tester.state(find.byType(ArcCalendarView));
    // A freshly loaded Journey, and midnight: Day 47 is now in Week 7.
    live.value = journeyOf(historyOf(s, wed.addDays(46)));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ArcCalendarView)), same(state));
    expect(position.pixels, before);
    expect(
      tester.widget<ArcCalendarView>(find.byType(ArcCalendarView)).journey,
      same(live.value),
    );
    expect(
      tester.getSemantics(dayCell(47)).label,
      startsWith('Day 47, Sunday 22 November. Today.'),
    );
  });

  testWidgets('high contrast: drawn without dimming; reduced motion: nothing '
      'animates once shown', (tester) async {
    everything(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpCalendar(
      tester,
      host(journeyOf(seasonalHistory()), highContrast: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final today = decoration(tester, 27);
    expect(today.color!.a, closeTo(0.35, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: Enter and Space open a day; Enter opens a week '
      'review', (tester) async {
    everything(tester);
    await pumpCalendar(tester, host(journeyOf(seasonalHistory())));
    Future<void> focus(Finder target) async {
      final ink = find.descendant(of: target, matching: find.byType(InkWell));
      Focus.of(
        tester.element(
          find
              .descendant(of: ink.first, matching: find.byType(ConstrainedBox))
              .first,
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
    }

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await focus(dayCell(20));
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(find.byType(DayDetailSheet), findsOneWidget, reason: '$key');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
    await focus(weekHeading(4));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_routes, ['/journey/review?week=4']);
  });

  testWidgets('worst case: 12 habits, heavy goal revisions, several pauses, '
      'every day logged; built from the loaded Journey with no query', (
    tester,
  ) async {
    everything(tester);
    final start = LocalDate(2027, 3, 1);
    final session = rollingArc(
      start,
      freezes: [
        closedFreeze(LocalDate(2027, 3, 11), 9),
        closedFreeze(LocalDate(2027, 4, 20), 30),
        closedFreeze(LocalDate(2027, 6, 30), 4),
      ],
    );
    final habits = [
      for (var i = 0; i < 12; i++)
        namedHabit('h$i', 'H' * 40, order: i, binary: false, target: 10),
    ];
    final dates = [for (var d = 1; d <= 92; d++) session.dateOfDay(d)!];
    final today = dates.last.addDays(1);
    final history = historyOf(
      session,
      today,
      habits: habits,
      revisions: [
        for (final h in habits)
          for (var k = 0; k < 92; k += 2)
            HabitRevision(
              habitId: h.id,
              effectiveFrom: dates[k],
              config: HabitConfig(
                target: 10 + k % 5,
                minimumTarget: 2,
                enabled: true,
              ),
              createdAt: DateTime(2027, 1, 1),
            ),
      ],
      days: {
        for (final (i, d) in dates.indexed)
          d: day(
            {for (final h in habits.take(i % 13)) h.id},
            mode: i % 7 == 0 ? DayMode.minimum : DayMode.normal,
            xp: 50,
          ),
      },
    );
    final watch = Stopwatch()..start();
    final journey = journeyOf(history);
    final journeyMs = watch.elapsedMilliseconds;
    watch.reset();
    await pumpCalendar(tester, host(journey));
    final calendarMs = watch.elapsedMilliseconds;
    expect(find.byType(CalendarDayCell), findsNWidgets(92));
    expect(find.bySemanticsLabel(RegExp('^Paused ')), findsNWidgets(3));
    // Recorded, not gated (spec § 10): a debug-mode test run, not a
    // profile build.
    debugPrint(
      'Phase 12C worst case: Journey model ${journeyMs}ms, calendar first '
      'build and layout ${calendarMs}ms (debug, test environment)',
    );
  });
}
