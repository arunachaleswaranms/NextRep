import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/arc_pause/pause_labels.dart';

import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12E2 layouts (spec § 9 "content within 600 dp, scrolls
/// vertically, nothing sideways; above 1.3× text rows stack"; ARC_MOMENTUM
/// § 8.5 A1–A10): the Pause sheet, its clock-guard refusal, the scheduled
/// banner, the paused Today (open pause, and a date moved back into a
/// closed one), the Resume sheet with the longest dates (year shown, two
/// pauses) and its failure, on the seven layouts of the earlier sweeps.
/// Each screen and sheet is scrolled through; nothing may overflow, clip a
/// line or scroll sideways, and every button is at least 48 dp. Then the
/// Flutter accessibility guidelines (tap targets, labels, contrast) at 1×
/// and 2×. All data synthetic.

typedef _Layout = ({String name, Size size, double text});

const _layouts = <_Layout>[
  (name: 'phone, 1× text', size: Size(360, 800), text: 1),
  (name: 'phone, 2× text', size: Size(360, 800), text: 2),
  (name: 'small phone, 1.5× text', size: Size(320, 568), text: 1.5),
  (name: 'small phone landscape', size: Size(568, 320), text: 1),
  (name: 'phone landscape, 1.3× text', size: Size(800, 360), text: 1.3),
  (name: 'tablet landscape', size: Size(1280, 800), text: 1),
  (name: 'phone, 1.3× text', size: Size(360, 640), text: 1.3),
];

enum _Scene {
  pauseSheet,
  pauseRefused,
  banner,
  pausedToday,
  pausedClosed,
  resumeSheet,
  resumeFailed,
}

// Day 1 on Wed 27 Sep 2028: the new last day falls in 2029, so the Resume
// sheet prints the year ("Wed 24 Jan 2029").
final _day1 = LocalDate(2028, 9, 27);
LocalDate _d(int n) => _day1.addDays(n - 1);

bool _isSheet(_Scene scene) =>
    scene == _Scene.pauseSheet ||
    scene == _Scene.pauseRefused ||
    scene == _Scene.resumeSheet ||
    scene == _Scene.resumeFailed;

Future<void> _open(WidgetTester tester, _Scene scene) async {
  final db = memoryDatabase();
  addTearDown(db.close);
  final app = TestApp(db, FakeClock(DateTime(2028, 9, 27)));
  final arc = await startRolling(app, _day1);
  final service = pauseServiceOf(app);
  switch (scene) {
    case _Scene.pauseSheet:
      at(app, _d(25));
    case _Scene.pauseRefused:
      await liveDay(app, _d(26));
      at(app, _d(25));
    case _Scene.banner:
      at(app, _d(25));
      await service.pause(sessionId: arc.id, frozenFrom: _d(26));
    case _Scene.pausedToday || _Scene.resumeSheet || _Scene.resumeFailed:
      at(app, _d(10));
      await service.pause(sessionId: arc.id, frozenFrom: _d(11));
      at(app, _d(14));
      await service.resume(sessionId: arc.id, on: _d(14));
      at(app, _d(14));
      await service.pause(sessionId: arc.id, frozenFrom: _d(15));
      at(app, _d(40));
    case _Scene.pausedClosed:
      at(app, _d(10));
      await service.pause(sessionId: arc.id, frozenFrom: _d(11));
      at(app, _d(30));
      await service.resume(sessionId: arc.id, on: _d(30));
      at(app, _d(20));
  }
  await tester.pumpWidget(reviewApp(db, app.clock, AppRoutes.today));
  await tester.pumpAndSettle();
  if (scene == _Scene.pauseSheet || scene == _Scene.pauseRefused) {
    await clearCelebrations(tester);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PauseCopy.menuItem));
    await tester.pumpAndSettle();
  }
  if (scene == _Scene.resumeSheet || scene == _Scene.resumeFailed) {
    await clearCelebrations(tester);
    await tester.ensureVisible(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
  }
  if (scene == _Scene.resumeFailed) {
    await db.customStatement(
      'CREATE TEMP TRIGGER injected_failure BEFORE UPDATE ON arc_freezes '
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    final resume = find.text(ResumeCopy.resumeAction);
    await tester.ensureVisible(resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.failed), findsOneWidget);
  }
  switch (scene) {
    case _Scene.pauseSheet:
      expect(find.text(PauseCopy.pauseAction), findsOneWidget);
    case _Scene.pauseRefused:
      expect(find.textContaining("Your phone's date"), findsOneWidget);
    case _Scene.banner:
      expect(find.text(PauseCopy.cancelAction), findsOneWidget);
    case _Scene.pausedToday:
      expect(find.text(PausedCopy.resumeAction), findsOneWidget);
    case _Scene.pausedClosed:
      expect(find.textContaining('Continues on'), findsOneWidget);
    case _Scene.resumeSheet:
      expect(find.textContaining('2029'), findsOneWidget);
      expect(find.textContaining('Paused days in this Arc'), findsOneWidget);
    case _Scene.resumeFailed:
      break;
  }
}

void _checkVisible(WidgetTester tester, Size screen) {
  for (final type in [FilledButton, OutlinedButton, TextButton]) {
    for (final element in find.byType(type).hitTestable().evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$type height');
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
    }
  }
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'clipped: "${paragraph.text.toPlainText()}"',
    );
  }
}

void main() {
  for (final layout in _layouts) {
    for (final scene in _Scene.values) {
      testWidgets('${layout.name}: ${scene.name}', (tester) async {
        tester.view
          ..physicalSize = layout.size * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = layout.text;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(tester, scene);
        expect(tester.takeException(), isNull);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.left ||
                    w.axisDirection == AxisDirection.right),
          ),
          findsNothing,
          reason: 'nothing scrolls sideways',
        );
        final vertical = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        final scrollable = _isSheet(scene)
            ? find.descendant(of: find.byType(BottomSheet), matching: vertical)
            : vertical;
        final position = tester
            .state<ScrollableState>(scrollable.first)
            .position;
        for (var page = 0; page < 60; page++) {
          _checkVisible(tester, layout.size);
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(
            (position.pixels + position.viewportDimension * 0.6).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }

  testWidgets('A11y guidelines at 360 × 800, 1× and 2×: tap targets, labels, '
      'contrast (every pause surface)', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final text in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      for (final scene in _Scene.values) {
        await _open(tester, scene);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    handle.dispose();
  });

  testWidgets('semantics: headings, full spoken dates, a labelled Cancel, the '
      'snowflake not relied on', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _open(tester, _Scene.pauseSheet);
    expect(
      tester.getSemantics(find.text(PauseCopy.sheetTitle)),
      isSemantics(label: PauseCopy.sheetTitle, isHeader: true),
    );
    expect(
      find.bySemanticsLabel(
        'From tomorrow, Sunday 22 October 2028, your Arc stops counting '
        'days until you resume.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));

    await _open(tester, _Scene.banner);
    expect(
      find.bySemanticsLabel(RegExp('^${PauseCopy.cancelAction}\$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(PauseCopy.bannerTomorrow), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));

    await _open(tester, _Scene.pausedToday);
    expect(
      tester.getSemantics(find.text(PausedCopy.heading)),
      isSemantics(label: PausedCopy.heading, isHeader: true),
    );
    expect(
      // The card's lines are read as one paragraph; the date is spoken in
      // full and the count is text.
      find.bySemanticsLabel(
        RegExp(
          r'^Paused since Wednesday 11 October 2028, 25 days\n'
          r'You stopped after Day 11 of 92\.\n'
          r'When you resume, that day becomes Day 12\.\n'
          r"Paused days don't count against you\.$",
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));

    await _open(tester, _Scene.resumeSheet);
    expect(
      tester.getSemantics(find.text(ResumeCopy.title)),
      isSemantics(label: ResumeCopy.title, isHeader: true),
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Today, Sunday 5 November 2028, becomes Day 12 of 92\.$'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    handle.dispose();
  });
}
