import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/features/arc_restart/restart_labels.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12F layouts (spec §§ 9.9–9.11 "one scrolling column; the field
/// stays visible above the keyboard"; ARC_MOMENTUM § 8.5 A1–A10): the
/// Restart screen (Rolling with a scheduled pause, Seasonal, Day 92, the
/// clock-guard refusal, a failed restart, the success screen), the typed
/// DELETE screen (after a restart, from a completed Arc's summary, a failed
/// deletion) and the paused Today's Restart link, on the seven layouts of
/// the earlier sweeps. Each screen is scrolled through; nothing may
/// overflow, clip a line or scroll sideways, and every button is at least
/// 48 dp. Then the Flutter accessibility guidelines (tap targets, labels,
/// contrast) at 1× and 2×, and the labels of § 9.9 / § 9.11. All data
/// synthetic.

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
  restartRolling,
  restartSeasonal,
  restartDay92,
  restartRefused,
  restartFailed,
  restartSuccess,
  deleteAfterRestart,
  deleteFromSummary,
  deleteFailed,
  pausedTodayRestartLink,
}

// Day 1 on Wed 27 Sep 2028: the new Arc's Day 92 falls in 2029, so long
// dates (with a year) print.
final _day1 = LocalDate(2028, 9, 27);
LocalDate _d(int n) => _day1.addDays(n - 1);

/// Scenes that show the Delete button enabled (DELETE typed).
const _deleteEnabled = {_Scene.deleteAfterRestart, _Scene.deleteFailed};

final _restartWord = find.byKey(const ValueKey('restart-word'));
final _restartConfirm = find.byKey(const ValueKey('restart-confirm'));
final _deleteWord = find.byKey(const ValueKey('delete-word'));
final _deleteConfirm = find.byKey(const ValueKey('delete-confirm'));

Future<void> _type(WidgetTester tester, Finder field, String word) async {
  final input = find.descendant(of: field, matching: find.byType(TextField));
  await tester.enterText(input, word);
  await tester.pumpAndSettle();
  // The field stays reachable above the keyboard (§ 9.9 large text).
  await tester.ensureVisible(input);
  await tester.pumpAndSettle();
  expect(input.hitTestable(), findsOneWidget, reason: 'field visible');
}

Future<void> _tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _Scene scene) async {
  final db = memoryDatabase();
  addTearDown(db.close);
  final app = TestApp(db, FakeClock(DateTime(2028, 9, 27)));
  String route;
  switch (scene) {
    case _Scene.restartRolling || _Scene.restartFailed || _Scene.restartSuccess:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(24));
      at(app, _d(25));
      await completeHabit(app, 'water');
      if (scene == _Scene.restartRolling) {
        await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(26));
      }
      route = AppRoutes.restartArc(arc.id);
    case _Scene.restartSeasonal:
      final arc = await joinSeason(app, DateTime(2028, 10, 15));
      await liveDays(app, LocalDate(2028, 10, 15), LocalDate(2028, 11, 13));
      at(app, LocalDate(2028, 11, 14));
      route = AppRoutes.restartArc(arc.id);
    case _Scene.restartDay92:
      final arc = await startRolling(app, _day1);
      at(app, _d(92));
      route = AppRoutes.restartArc(arc.id);
    case _Scene.restartRefused:
      final arc = await startRolling(app, _day1);
      await liveDay(app, _d(26));
      at(app, _d(25));
      route = AppRoutes.restartArc(arc.id);
    case _Scene.deleteAfterRestart:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(10));
      at(app, _d(11));
      await restartNow(app, arc.id);
      route = AppRoutes.deleteArc(arc.id, afterRestart: true);
    case _Scene.deleteFromSummary || _Scene.deleteFailed:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(3));
      at(app, _d(93));
      await app.lifecycle.reconcile();
      route = AppRoutes.deleteArc(arc.id);
    case _Scene.pausedTodayRestartLink:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(10));
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(11));
      at(app, _d(40));
      route = AppRoutes.today;
  }
  await tester.pumpWidget(reviewApp(db, app.clock, route));
  await tester.pumpAndSettle();
  await clearCelebrations(tester);

  switch (scene) {
    case _Scene.restartRolling:
      expect(find.text(RestartCopy.scheduledPauseRemoved), findsOneWidget);
      await _type(tester, _restartWord, RestartCopy.word);
      expect(find.text('Restart Arc'), findsOneWidget);
    case _Scene.restartSeasonal:
      expect(find.text('Start a Rolling Arc with this setup'), findsOneWidget);
      expect(find.text('Start Rolling Arc'), findsOneWidget);
      expect(
        find.textContaining('You will leave the Seasonal Winter Arc'),
        findsOneWidget,
      );
    case _Scene.restartDay92:
      expect(find.text(RestartCopy.lastDay), findsOneWidget);
    case _Scene.restartRefused:
      expect(find.textContaining("Your phone's date"), findsOneWidget);
    case _Scene.restartFailed:
      await db.customStatement(
        'CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON '
        "winter_arc_sessions BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await _type(tester, _restartWord, RestartCopy.word);
      await _tapShown(tester, _restartConfirm);
      expect(find.text(RestartCopy.failed), findsOneWidget);
    case _Scene.restartSuccess:
      await _type(tester, _restartWord, RestartCopy.word);
      await _tapShown(tester, _restartConfirm);
      expect(find.text(RestartCopy.started), findsWidgets);
      expect(find.text(RestartCopy.goToToday), findsOneWidget);
      expect(find.text(RestartCopy.viewPrevious), findsOneWidget);
    case _Scene.deleteAfterRestart:
      expect(find.text(DeleteArcCopy.titleAfterRestart), findsOneWidget);
      await _type(tester, _deleteWord, DeleteArcCopy.word);
    case _Scene.deleteFromSummary:
      expect(find.text(DeleteArcCopy.titleFromSummary), findsOneWidget);
    case _Scene.deleteFailed:
      await db.customStatement(
        'CREATE TEMP TRIGGER injected_failure BEFORE DELETE ON '
        "winter_arc_sessions BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await _type(tester, _deleteWord, DeleteArcCopy.word);
      await _tapShown(tester, _deleteConfirm);
      expect(find.text(DeleteArcCopy.failed), findsOneWidget);
    case _Scene.pausedTodayRestartLink:
      expect(find.text('Restart with this setup'), findsOneWidget);
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
  for (final element
      in find.byType(RadioListTile<bool>).hitTestable().evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    expect(rect.height, greaterThanOrEqualTo(48), reason: 'radio height');
    expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
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

/// Scrollables of the page itself: a text field's own single-line
/// horizontal scrollable is part of the field, not the page.
List<Element> _pageScrollables(bool Function(AxisDirection) direction) => [
  for (final element
      in find
          .byWidgetPredicate(
            (w) => w is Scrollable && direction(w.axisDirection),
          )
          .evaluate())
    if (element.findAncestorWidgetOfExactType<EditableText>() == null) element,
];

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
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
          _pageScrollables(
            (d) => d == AxisDirection.left || d == AxisDirection.right,
          ),
          isEmpty,
          reason: 'nothing scrolls sideways',
        );
        final vertical = _pageScrollables((d) => d == AxisDirection.down);
        expect(vertical, isNotEmpty);
        final position =
            (vertical.first as StatefulElement).state as ScrollableState;
        for (var page = 0; page < 60; page++) {
          _checkVisible(tester, layout.size);
          final p = position.position;
          if (p.pixels >= p.maxScrollExtent) break;
          p.jumpTo(
            (p.pixels + p.viewportDimension * 0.6).clamp(
              p.minScrollExtent,
              p.maxScrollExtent,
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await _close(tester);
      });
    }
  }

  // Reported defect (Phase 12F layout sweep): the Restart and Delete
  // screens put their full title in a one-line AppBar title, which
  // ellipsizes ("Start a Rolling Arc with this setup" on a 360 dp phone,
  // and every title at 1.3× / 2× text) instead of the spec's "everything
  // in one scrolling column". Skipped until the product decides; the test
  // font makes it fail at 1× too, so a fix must be confirmed on a device.
  for (final layout in _layouts) {
    testWidgets('app bar titles are never ellipsized: ${layout.name}', (
      tester,
    ) async {
      tester.view
        ..physicalSize = layout.size * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = layout.text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final scene in [
        _Scene.restartRolling,
        _Scene.restartSeasonal,
        _Scene.restartSuccess,
        _Scene.deleteAfterRestart,
        _Scene.deleteFromSummary,
      ]) {
        await _open(tester, scene);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: 'ellipsized: "${paragraph.text.toPlainText()}"',
          );
        }
        await _close(tester);
      }
    });
  }

  testWidgets('A11y guidelines at 360 × 800, 1× and 2×: tap targets, labels, '
      'contrast (every restart and delete surface)', (tester) async {
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
        await _close(tester);
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    handle.dispose();
  });

  // Found by this sweep and fixed before the PR: the enabled "Delete
  // previous Arc" / "Delete this Arc" button drew light text on the danger
  // colour (#FF5C8A): 2.71:1. It now uses the dark background colour.
  testWidgets('Delete button contrast when enabled, 1× and 2×', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final text in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      for (final scene in _deleteEnabled) {
        await _open(tester, scene);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await _close(tester);
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    handle.dispose();
  });

  testWidgets('semantics: the RESTART field, the disabled buttons say why, '
      'the "Your old Arc" group, the losses read item by item', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Restart (§ 9.9), opened without typing anything.
    final db = memoryDatabase();
    addTearDown(db.close);
    final app = TestApp(db, FakeClock(DateTime(2028, 9, 27)));
    final arc = await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(3));
    at(app, _d(4));
    await tester.pumpWidget(
      reviewApp(db, app.clock, AppRoutes.restartArc(arc.id)),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(RestartCopy.fieldLabel)), findsWidgets);
    expect(
      find.bySemanticsLabel('Restart Arc. Type RESTART to enable.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RestartCopy.oldArcHeading), findsOneWidget);
    // Typed and matching: the button reads its own name and is enabled.
    await tester.enterText(_restartWord, ' RESTART ');
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Restart Arc. Type RESTART to enable.'),
      findsNothing,
    );
    expect(
      tester.getSemantics(_restartConfirm),
      matchesSemantics(
        label: 'Restart Arc',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await _close(tester);

    // Delete (§ 9.11), after a restart.
    final db2 = memoryDatabase();
    addTearDown(db2.close);
    final app2 = TestApp(db2, FakeClock(DateTime(2028, 9, 27)));
    final old = await startRolling(app2, _day1);
    await liveDays(app2, _d(1), _d(3));
    at(app2, _d(4));
    await restartNow(app2, old.id);
    await tester.pumpWidget(
      reviewApp(
        db2,
        app2.clock,
        AppRoutes.deleteArc(old.id, afterRestart: true),
      ),
    );
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(
      find.bySemanticsLabel('Delete previous Arc. Type DELETE to enable.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(DeleteArcCopy.fieldLabel)),
      findsWidgets,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^3 challenge days and [\d,]+ XP$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^\d+ achievements?$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('0 Journal reflections'),
      findsOneWidget,
      reason: 'a zero count is shown, never hidden',
    );
    expect(find.bySemanticsLabel(DeleteArcCopy.journey), findsOneWidget);
    await _close(tester);
    handle.dispose();
  });
}
