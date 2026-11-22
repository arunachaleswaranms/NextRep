import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/setup_labels.dart';
import 'package:nextrep/features/habit_setup/setup_navigation.dart';

import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/ui.dart';

/// Phase 12D layouts (spec § 9, ARC_MOMENTUM_SPEC § 8.5 A1–A10): Habit
/// Setup with 12 habits and 40-character titles, the saved-setup hub
/// (normal, empty, late Seasonal), Review Setup, Confirm & Start (Rolling,
/// Seasonal, preseason refusal) and a failed start, on the seven layouts of
/// the Phase 12B / 12C sweeps. Each screen is scrolled through; nothing
/// may overflow, clip a line or scroll sideways; content stays within
/// 600 dp; every button and the drag handles are at least 48 dp; Confirm
/// keeps 24 dp between its two actions. All data synthetic.

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

enum _Scene {
  editor12,
  hub,
  hubEmpty,
  hubLateSeason,
  review12,
  confirmRolling,
  confirmSeasonal,
  confirmPreseason,
  confirmFailed,
}

const _long = 'An Unusually Long Custom Habit Name Here'; // 40 characters

/// Seeds the database for [scene] inside the test body (see
/// `widget-harness` note: a database opened in setUp can't be awaited
/// here) and opens its screen.
Future<void> _open(WidgetTester tester, _Scene scene) async {
  final db = memoryDatabase();
  addTearDown(db.close);
  final seasonal =
      scene == _Scene.hubLateSeason ||
      scene == _Scene.confirmSeasonal ||
      scene == _Scene.confirmPreseason;
  final clock = FakeClock(switch (scene) {
    _Scene.confirmPreseason => DateTime(2026, 9, 20, 9),
    _ when seasonal => DateTime(2026, 10, 18, 9),
    _ => DateTime(2026, 11, 13, 9),
  });
  final app = TestApp(db, clock);
  if (scene == _Scene.confirmPreseason) {
    await app.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
  } else {
    await app.winterArc.beginSetup(
      kind: seasonal ? ArcKind.seasonalWinter : ArcKind.rolling92,
    );
  }
  final twelve = scene == _Scene.editor12 || scene == _Scene.review12;
  if (twelve) {
    for (final id in ['reading', 'mobility', 'fruit', 'journal']) {
      await app.winterArc.addTemplateHabit(id);
    }
    await app.winterArc.addCustomHabit(
      const HabitDraft(
        title: _long,
        type: HabitType.count,
        iconKey: 'star',
        target: 50,
        minimumTarget: 20,
        unit: 'repetitions',
      ),
    );
    final ids = [for (final h in await app.winterArc.setupHabits()) h.id];
    expect(ids, hasLength(12));
    await app.winterArc.reorderSetupHabits(ids.reversed.toList());
  }
  if (scene == _Scene.hubEmpty) {
    for (final h in await app.winterArc.setupHabits()) {
      await app.winterArc.deleteSetupHabit(h.id);
    }
  }
  if (scene == _Scene.confirmFailed) {
    await db.customStatement(
      'CREATE TRIGGER fail_start BEFORE UPDATE OF status ON '
      "winter_arc_sessions WHEN NEW.status = 'active' "
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
  }
  final route = switch (scene) {
    _Scene.editor12 => AppRoutes.habitSetup,
    _Scene.hub ||
    _Scene.hubEmpty ||
    _Scene.hubLateSeason => AppRoutes.savedSetup,
    _Scene.review12 => AppRoutes.reviewSetup,
    _ => AppRoutes.confirmStart,
  };
  await tester.pumpWidget(reviewApp(db, clock, route));
  await tester.pumpAndSettle();
  if (scene == _Scene.confirmFailed) {
    final start = find.widgetWithText(
      FilledButton,
      'Confirm & Start Challenge',
    );
    await showIn(tester, start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text(SetupLabels.startFailed), findsOneWidget);
  }
}

/// Every check, at the current scroll position.
void _checkVisible(WidgetTester tester, Size screen) {
  for (final type in [FilledButton, OutlinedButton, TextButton]) {
    for (final element in find.byType(type).hitTestable().evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$type height');
      expect(
        rect.width,
        lessThanOrEqualTo(SetupLayout.maxContentWidth + 0.5),
        reason: '$type within 600 dp',
      );
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
    }
  }
  for (final element
      in find.byIcon(Icons.drag_indicator_rounded).hitTestable().evaluate()) {
    final handle = find
        .ancestor(
          of: find.byWidget(element.widget),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 48 && w.height == 48,
          ),
        )
        .first;
    final rect = tester.getRect(handle);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
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
        if (layout.reduceMotion) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        await _open(tester, scene);
        expect(tester.takeException(), isNull);
        if (scene == _Scene.hubEmpty) {
          expect(
            find.text(SetupLabels.addAHabit, skipOffstage: false),
            findsWidgets,
          );
        }
        if (scene == _Scene.editor12) {
          // The 40-character habit, moved to the top by the reversal.
          expect(find.text(_long, skipOffstage: false), findsOneWidget);
        }
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

        final scrollable = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        final position = tester
            .state<ScrollableState>(scrollable.first)
            .position;
        for (var page = 0; page < 80; page++) {
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

        switch (scene) {
          case _Scene.editor12:
            expect(find.text('Review & Start'), findsOneWidget);
          case _Scene.review12:
            expect(find.text('Save for Later'), findsOneWidget);
          case _Scene.confirmRolling ||
              _Scene.confirmSeasonal ||
              _Scene.confirmFailed:
            final start = tester.getRect(find.byType(FilledButton));
            final save = tester.getRect(
              find.widgetWithText(OutlinedButton, 'Save for Later'),
            );
            expect(save.top - start.bottom, greaterThanOrEqualTo(24));
          case _Scene.confirmPreseason:
            expect(find.text(SetupLabels.seasonNotStarted), findsOneWidget);
          case _Scene.hub || _Scene.hubLateSeason || _Scene.hubEmpty:
            expect(find.text('Cancel setup'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }

  testWidgets('A11y guidelines at 360 × 800, 1× and 2×: tap targets, labels, '
      'contrast (hub, Review, Confirm, Habit Setup)', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final text in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      for (final scene in [
        _Scene.hub,
        _Scene.hubEmpty, // Start Challenge unavailable
        _Scene.review12,
        _Scene.confirmRolling,
        _Scene.confirmSeasonal,
        _Scene.confirmPreseason, // Confirm unavailable, with the reason
        _Scene.editor12,
      ]) {
        await _open(tester, scene);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // Rendered text contrast, every node, primary buttons included.
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    handle.dispose();
  });
}
