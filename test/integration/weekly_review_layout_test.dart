import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';
import 'package:nextrep/shared/widgets/winter_card.dart';

import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/review_seed.dart';

/// Phase 12B: the Weekly Review (and the Journey header that opens it) on
/// the six layouts of the Phase 11E sweep plus the 360 × 800 dp layout at
/// 1× text that spec § 5.3 adds, with a 40-character habit title. Each
/// screen is scrolled top to bottom; any overflow or framework error fails.
/// Also checked: nothing scrolls sideways, content is at most 600 dp wide,
/// and the week strip wraps to 4 days a line with large text or a narrow
/// screen (7 otherwise). All data synthetic.

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

/// (state name, paused seed?, route builder, first day of the strip, days)
typedef _Case = ({
  String name,
  bool paused,
  String Function(ReviewSeed) route,
  int firstDay,
  int days,
});

final _cases = <_Case>[
  (
    name: 'current week',
    paused: false,
    route: (s) => AppRoutes.activeReview(2),
    firstDay: 8,
    days: 7,
  ),
  (
    name: 'week with a pause',
    paused: false,
    route: (s) => AppRoutes.activeReview(1),
    firstDay: 1,
    days: 7,
  ),
  (
    name: 'paused week',
    paused: true,
    route: (s) => AppRoutes.activeReview(2),
    firstDay: 8,
    days: 7,
  ),
  (
    name: 'completed Arc, Week 13',
    paused: false,
    route: (s) => AppRoutes.arcReview(s.completedId, 13),
    firstDay: 85,
    days: 8,
  ),
  (
    name: 'ended Arc, last week',
    paused: false,
    route: (s) => AppRoutes.arcReview(s.endedId, 1),
    firstDay: 1,
    days: 7,
  ),
  (
    name: 'Journey header',
    paused: false,
    route: (s) => AppRoutes.journey,
    firstDay: 0,
    days: 0,
  ),
];

void main() {
  /// Scrolls every vertical scrollable on screen to its end, a page at a
  /// time (the Phase 11E sweep's routine).
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollables = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < scrollables.evaluate().length; i++) {
      for (var page = 0; page < 40; page++) {
        final state = tester.state<ScrollableState>(scrollables.at(i));
        final position = state.position;
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo(
          (position.pixels + position.viewportDimension * 0.8).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
    }
  }

  for (final layout in _layouts) {
    for (final c in _cases) {
      testWidgets('${layout.name}: ${c.name}', (tester) async {
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
        final AppDatabase db = memoryDatabase();
        addTearDown(db.close);
        final clock = FakeClock(DateTime(2026, 7, 1));
        final seed = await seedReviewData(
          TestApp(db, clock),
          pausedFrom: c.paused ? LocalDate(2026, 10, 21) : null,
        );
        await tester.pumpWidget(reviewApp(db, clock, c.route(seed)));
        await tester.pumpAndSettle();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
        }

        if (c.days > 0) {
          expect(find.byType(WeeklyReviewScreen), findsOneWidget);
          final screen = find.byType(WeeklyReviewScreen);
          expect(
            find.descendant(
              of: screen,
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
          for (final card in tester.widgetList(find.byType(WinterCard))) {
            expect(
              tester.getSize(find.byWidget(card)).width,
              lessThanOrEqualTo(WeeklyReviewScreen.maxContentWidth),
            );
          }
          // The strip: one line of 7 (plus Day 92's own line), or lines of
          // 4 with large text or under 48 dp a cell.
          await tester.scrollUntilVisible(
            find.bySemanticsLabel(
              RegExp('^Day ${c.firstDay + c.days - 1}[,.]'),
            ),
            80,
            scrollable: find
                .descendant(
                  of: screen,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  ),
                )
                .first,
          );
          await tester.pumpAndSettle();
          final tops = <double>{};
          for (var d = c.firstDay; d < c.firstDay + c.days; d++) {
            final cell = find.bySemanticsLabel(RegExp('^Day $d[,.]'));
            expect(cell, findsOneWidget, reason: 'Day $d');
            final rect = tester.getRect(cell);
            expect(rect.width, greaterThanOrEqualTo(48), reason: 'Day $d');
            expect(rect.height, greaterThanOrEqualTo(48), reason: 'Day $d');
            tops.add(rect.top);
          }
          final width = layout.size.width.clamp(
            0,
            WeeklyReviewScreen.maxContentWidth,
          );
          final fourPerLine = layout.text > 1.3 || (width - 16) / 7 < 48;
          expect(
            tops.length,
            fourPerLine ? (c.days / 4).ceil() : (c.days / 7).ceil(),
            reason: 'strip lines',
          );
        }

        await scrollThrough(tester);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
