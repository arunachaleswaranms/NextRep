import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/journey/widgets/arc_calendar_view.dart';
import 'package:nextrep/features/journey/widgets/calendar_day_cell.dart';
import 'package:nextrep/features/journey/widgets/day_detail_sheet.dart';

import '../support/arcs.dart';
import '../support/calendar_support.dart';
import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/review_seed.dart';

/// Phase 12C: the Arc Consistency Calendar in the real app on the seven
/// layouts of the Phase 12B sweep (spec § 7.4, A1–A5): an active Arc with
/// a resumed pause and a 40-character habit, a paused Arc (undated days),
/// a completed Arc (Week 13's 8 days), an ended Arc, and a late-joined
/// Seasonal Arc. Each calendar is scrolled from Week 1 to Week 13; every
/// heading must be reached, nothing may overflow or scroll sideways,
/// content stays within 600 dp, cells are at least 48 × 48 dp, and a week
/// is one line of 7 (Week 13: 7 + 1) at ≤ 1.3× text on ≥ 352 dp, else
/// lines of 4. The Legend and a day detail are opened and scrolled too.
/// All data synthetic.

typedef _Layout = ({String name, Size size, double text, bool reduceMotion});

const _layouts = <_Layout>[
  (name: 'phone, 1× text', size: Size(360, 800), text: 1, reduceMotion: false),
  (name: 'phone, 2× text', size: Size(360, 800), text: 2, reduceMotion: false),
  (
    name: 'small phone, 1.5× text',
    size: Size(320, 568),
    text: 1.5,
    reduceMotion: false,
  ),
  (
    name: 'small phone landscape',
    size: Size(568, 320),
    text: 1,
    reduceMotion: false,
  ),
  (
    name: 'phone landscape, 1.3× text',
    size: Size(800, 360),
    text: 1.3,
    reduceMotion: false,
  ),
  (
    name: 'tablet landscape',
    size: Size(1280, 800),
    text: 1,
    reduceMotion: false,
  ),
  (
    name: 'phone, 1.3× text, reduced motion',
    size: Size(360, 640),
    text: 1.3,
    reduceMotion: true,
  ),
];

enum _Arc { active, paused, completed, ended, seasonal }

/// Opens [arc]'s Journey in a fresh app over a fresh database.
Future<void> _open(WidgetTester tester, _Arc arc) async {
  final AppDatabase db = memoryDatabase();
  addTearDown(db.close);
  late final String route;
  late final FakeClock clock;
  if (arc == _Arc.seasonal) {
    clock = FakeClock(DateTime(2026, 10, 1));
    final app = TestApp(db, clock);
    await joinSeason(app, DateTime(2026, 10, 18));
    for (var d = 18; d <= 20; d++) {
      at(app, LocalDate(2026, 10, d));
      await completeAll(app);
    }
    at(app, LocalDate(2026, 10, 21), hour: 13);
    route = AppRoutes.journey;
  } else {
    clock = FakeClock(DateTime(2026, 7, 1));
    final seed = await seedReviewData(
      TestApp(db, clock),
      pausedFrom: arc == _Arc.paused ? ReviewSeed.today : null,
    );
    route = switch (arc) {
      _Arc.completed => AppRoutes.arcJourney(seed.completedId),
      _Arc.ended => AppRoutes.arcJourney(seed.endedId),
      _ => AppRoutes.journey,
    };
  }
  await tester.pumpWidget(reviewApp(db, clock, route));
  await tester.pumpAndSettle();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }
}

/// Scrolls every vertical scrollable on screen to its end, a page at a
/// time (the Phase 11E sweep's routine).
Future<void> _scrollThrough(WidgetTester tester, Finder within) async {
  final scrollables = find.descendant(
    of: within,
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    for (var page = 0; page < 60; page++) {
      final position = tester
          .state<ScrollableState>(scrollables.at(i))
          .position;
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
    }
  }
}

void main() {
  for (final layout in _layouts) {
    for (final arc in _Arc.values) {
      testWidgets('${layout.name}: ${arc.name} Arc', (tester) async {
        tester.view
          ..physicalSize = layout.size * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = layout.text;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (layout.reduceMotion) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        await _open(tester, arc);
        await choose(tester, 'Calendar');
        expect(tester.takeException(), isNull);
        final calendar = find.byType(ArcCalendarView);
        expect(
          find.descendant(
            of: calendar,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Scrollable &&
                  (w.axisDirection == AxisDirection.left ||
                      w.axisDirection == AxisDirection.right),
            ),
          ),
          findsNothing,
          reason: 'nothing scrolls sideways',
        );

        final width = layout.size.width.clamp(0, ArcCalendarView.maxWidth);
        final perLine = layout.text > 1.3 || (width - 16) / 7 < 48 ? 4 : 7;

        // From the top: every heading is reached, every visible cell is at
        // least 48 dp square, and every row of cells fits within 600 dp.
        final position = tester
            .state<ScrollableState>(calendarScrollable())
            .position;
        for (
          var i = 0;
          i < 20 && position.pixels > position.minScrollExtent;
          i++
        ) {
          position.jumpTo(position.minScrollExtent);
          await tester.pumpAndSettle();
        }
        final reached = <int>{};
        final viewport = tester.getRect(calendarScrollable());
        for (var page = 0; page < 200; page++) {
          for (var w = 1; w <= 13; w++) {
            if (weekHeading(w).hitTestable().evaluate().isNotEmpty) {
              reached.add(w);
            }
          }
          for (final cell
              in find.byType(CalendarDayCell).hitTestable().evaluate()) {
            final rect = tester.getRect(find.byWidget(cell.widget));
            if (rect.top < viewport.top || rect.bottom > viewport.bottom) {
              continue;
            }
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.5));
            expect(rect.right, lessThanOrEqualTo(viewport.right + 0.5));
          }
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(
            (position.pixels + position.viewportDimension * 0.6).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(reached, {for (var w = 1; w <= 13; w++) w});
        expect(tester.takeException(), isNull);

        // Lines: a whole week, and Week 13 (7 + 1, or 4 + 4).
        Future<Set<double>> tops(int first, int last) async {
          await reveal(tester, dayCell(last));
          await reveal(tester, dayCell(first));
          return {
            for (var d = first; d <= last; d++)
              tester.getTopLeft(dayCell(d)).dy,
          };
        }

        // Week 3: no pause row splits it in any of these Arcs.
        expect(await tops(15, 21), hasLength(perLine == 7 ? 1 : 2));
        expect(await tops(85, 92), hasLength(2));
        final row = [
          for (var d = 85; d < 85 + perLine; d++) tester.getRect(dayCell(d)),
        ];
        expect(
          row.last.right - row.first.left,
          lessThanOrEqualTo(ArcCalendarView.maxWidth),
        );

        // Headings are never clipped: no ellipsis, no line limit hit.
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: calendar, matching: find.byType(RichText)),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse);
        }

        if (arc == _Arc.active) {
          // The Legend, scrolled through.
          await tester.tap(find.byTooltip('Legend'));
          await tester.pumpAndSettle();
          await _scrollThrough(tester, find.byType(BottomSheet));
          expect(tester.takeException(), isNull);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          // Today's detail, with the 40-character habit title.
          await reveal(tester, dayCell(13));
          await tester.tap(dayCell(13));
          await tester.pumpAndSettle();
          expect(find.byType(DayDetailSheet), findsOneWidget);
          await _scrollThrough(tester, find.byType(DayDetailSheet));
          expect(find.textContaining(ReviewSeed.longTitle), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
