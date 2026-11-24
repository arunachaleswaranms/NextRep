import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12H layout and accessibility sweep (brief § 8; ARC_MOMENTUM_SPEC
/// § 8.5 A1–A5, A9, A10; ARC_CONTROL_SPEC § 10 "Accessibility"). It covers
/// the v1.3 surfaces no earlier sweep reached (Phase 12H coverage matrix):
///
/// * Arc History holding a completed, an ended and a paused Arc;
/// * an ended Arc's Summary ("Ended early");
/// * Today's header (Phase 12G: five actions, wrapped under the title);
/// * Habits with a scheduled pause and the Restart link;
/// * Journal while paused;
/// * Habit Setup with a habit's Move up / Move down menu open;
/// * Sound & Feedback (also at 360 × 640, 1.3×, with reduced motion);
/// * the hub's Cancel Setup dialog and Data & Backup's Replace Data dialog
///   (both destructive).
///
/// On the seven layouts of the earlier sweeps (360 × 800 at 1× and 2×,
/// 320 × 568 at 1.5×, 568 × 320, 800 × 360 at 1.3×, 1280 × 800, and
/// 360 × 640 at 1.3× with reduced motion) every screen is scrolled
/// through: nothing may overflow, clip a line or scroll sideways, and every
/// button is at least 48 dp. Then Flutter's tap-target, label and contrast
/// guidelines at 1× and 2×, and reduced motion: once shown, nothing keeps
/// animating on any v1.3 screen. All data synthetic.

typedef _Layout = ({String name, Size size, double text, bool still});

const _layouts = <_Layout>[
  (name: 'phone, 1× text', size: Size(360, 800), text: 1, still: false),
  (name: 'phone, 2× text', size: Size(360, 800), text: 2, still: false),
  (name: 'small phone, 1.5×', size: Size(320, 568), text: 1.5, still: false),
  (name: 'small landscape', size: Size(568, 320), text: 1, still: false),
  (name: 'landscape, 1.3×', size: Size(800, 360), text: 1.3, still: false),
  (name: 'tablet', size: Size(1280, 800), text: 1, still: false),
  (
    name: 'phone 1.3×, reduced motion',
    size: Size(360, 640),
    text: 1.3,
    still: true,
  ),
];

enum _Scene {
  historyMixed,
  summaryEnded,
  todayHeader,
  habitsScheduledPause,
  journalPaused,
  setupMoveMenu,
  soundSettings,
  hubCancelDialog,
  replaceDataDialog,
}

final _day1 = LocalDate(2028, 1, 5);
LocalDate _d(int n) => _day1.addDays(n - 1);

const _longHabit = HabitDraft(
  title: 'Evening mobility and breathing routine',
  type: HabitType.count,
  iconKey: 'star',
  target: 12,
  minimumTarget: 6,
  unit: 'repetitions',
);

Future<void> _open(WidgetTester tester, _Scene scene) async {
  final db = memoryDatabase();
  addTearDown(db.close);
  final app = TestApp(db, FakeClock(DateTime(2027, 7, 1)));
  final files = FakeBackupFiles();
  late String route;
  switch (scene) {
    case _Scene.historyMixed || _Scene.summaryEnded || _Scene.journalPaused:
      await runFirstArc(app, start: DateTime(2027, 7, 1));
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(12));
      at(app, _d(13), hour: 12);
      await completeHabit(app, 'water');
      final fresh = (await restartNow(app, arc.id)).started;
      await liveDays(app, _d(13), _d(16));
      await pauseServiceOf(app).pause(sessionId: fresh.id, frozenFrom: _d(17));
      at(app, _d(20));
      route = switch (scene) {
        _Scene.historyMixed => AppRoutes.history,
        _Scene.summaryEnded => AppRoutes.arc(arc.id),
        _ => AppRoutes.journal,
      };
    case _Scene.todayHeader:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(3));
      at(app, _d(4));
      expect(arc.status.name, 'active');
      route = AppRoutes.today;
    case _Scene.habitsScheduledPause:
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(5));
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(6));
      route = AppRoutes.habits;
    case _Scene.setupMoveMenu || _Scene.hubCancelDialog:
      at(app, _day1);
      await app.winterArc.beginSetup();
      await app.winterArc.addCustomHabit(_longHabit);
      route = scene == _Scene.setupMoveMenu
          ? AppRoutes.habitSetup
          : AppRoutes.savedSetup;
    case _Scene.soundSettings:
      await startRolling(app, _day1);
      route = AppRoutes.soundSettings;
    case _Scene.replaceDataDialog:
      await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(2));
      files.toPick = (await app.backup.export()).bytes;
      route = AppRoutes.dataBackup;
  }
  await tester.pumpWidget(
    reviewApp(
      db,
      app.clock,
      route,
      overrides: [backupFilesProvider.overrideWithValue(files)],
    ),
  );
  await tester.pumpAndSettle();
  await clearCelebrations(tester);

  switch (scene) {
    case _Scene.historyMixed:
      await tester.scrollUntilVisible(
        find.textContaining('Ended early'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Ended early'), findsWidgets);
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      list.position.jumpTo(0);
      await tester.pumpAndSettle();
    case _Scene.summaryEnded:
      expect(find.textContaining('Ended early'), findsWidgets);
    case _Scene.todayHeader:
      expect(find.byTooltip('Sound & Feedback'), findsOneWidget);
    case _Scene.habitsScheduledPause:
      await tester.scrollUntilVisible(
        find.text('Restart with this setup'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Restart with this setup'), findsOneWidget);
    case _Scene.journalPaused || _Scene.soundSettings:
      break;
    case _Scene.setupMoveMenu:
      final menu = find.byTooltip('Options for ${_longHabit.title}');
      await tester.scrollUntilVisible(
        menu,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Move up'), findsOneWidget);
    case _Scene.hubCancelDialog:
      final button = find.widgetWithText(TextButton, 'Cancel setup');
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Cancel Setup'), findsOneWidget);
    case _Scene.replaceDataDialog:
      final restore = find.text('Restore Backup');
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Restore');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Replace Data'), findsOneWidget);
  }
}

void _checkVisible(WidgetTester tester, Size screen) {
  for (final type in [FilledButton, OutlinedButton, TextButton, IconButton]) {
    for (final element in find.byType(type).hitTestable().evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(
        rect.height,
        greaterThanOrEqualTo(48 - 1e-6),
        reason: '$type height',
      );
      expect(
        rect.width,
        greaterThanOrEqualTo(48 - 1e-6),
        reason: '$type width',
      );
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
    }
  }
  // App bar titles are left out: Material's AppBar caps its title's text
  // scale, and on the API 36 emulator at 360 dp and 2× text "Sound &
  // Feedback", "Your habits" and "Data & Backup" show in full (Phase 12H,
  // docs/PHASE_12H.md § 6). Only the square test font ellipsizes them.
  final inAppBars = tester
      .renderObjectList<RenderParagraph>(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(RichText),
        ),
      )
      .toSet();
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    if (inAppBars.contains(paragraph)) continue;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'clipped: "${paragraph.text.toPlainText()}"',
    );
  }
}

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

void _useLayout(WidgetTester tester, _Layout layout) {
  tester.view
    ..physicalSize = layout.size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = layout.text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (layout.still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
}

/// Every v1.3 screen and sheet, opened by route (and an action where a
/// sheet or dialog needs one), for the reduced-motion check.
final _v13Routes = <String, Future<String> Function(TestApp app)>{
  'saved setup hub': (app) async {
    at(app, _day1);
    await app.winterArc.beginSetup();
    return AppRoutes.savedSetup;
  },
  'habit setup (reorder list)': (app) async {
    at(app, _day1);
    await app.winterArc.beginSetup();
    return AppRoutes.habitSetup;
  },
  'Review Setup': (app) async {
    at(app, _day1);
    await app.winterArc.beginSetup();
    return AppRoutes.reviewSetup;
  },
  'Confirm & Start': (app) async {
    at(app, _day1);
    await app.winterArc.beginSetup();
    return AppRoutes.confirmStart;
  },
  'Today with a scheduled pause': (app) async {
    final arc = await startRolling(app, _day1);
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(2));
    return AppRoutes.today;
  },
  'paused Today': (app) async {
    final arc = await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(3));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(4));
    at(app, _d(9));
    return AppRoutes.today;
  },
  'Weekly Review': (app) async {
    await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(9));
    return AppRoutes.activeReview(2);
  },
  'Restart': (app) async {
    final arc = await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(4));
    return AppRoutes.restartArc(arc.id);
  },
  'Delete Arc': (app) async {
    final arc = await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(4));
    at(app, _d(5));
    await restartNow(app, arc.id);
    return AppRoutes.deleteArc(arc.id, afterRestart: true);
  },
  'ended Arc summary': (app) async {
    final arc = await startRolling(app, _day1);
    await liveDays(app, _d(1), _d(4));
    at(app, _d(5));
    await restartNow(app, arc.id);
    return AppRoutes.arc(arc.id);
  },
  'Sound & Feedback': (app) async {
    await startRolling(app, _day1);
    return AppRoutes.soundSettings;
  },
};

void main() {
  for (final layout in _layouts) {
    for (final scene in _Scene.values) {
      testWidgets('${layout.name}: ${scene.name}', (tester) async {
        _useLayout(tester, layout);
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
        if (vertical.isNotEmpty) {
          final position =
              (vertical.last as StatefulElement).state as ScrollableState;
          for (var page = 0; page < 80; page++) {
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
        } else {
          _checkVisible(tester, layout.size);
        }
        expect(tester.takeException(), isNull);
        await _close(tester);
      });
    }
  }

  testWidgets('A11y guidelines at 360 × 800, 1× and 2×: tap targets, labels '
      'and text contrast on every scene, destructive dialogs included', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final text in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      for (final scene in _Scene.values) {
        await _open(tester, scene);
        await expectLater(
          tester,
          meetsGuideline(androidTapTargetGuideline),
          reason: '$scene at $text×',
        );
        await expectLater(
          tester,
          meetsGuideline(labeledTapTargetGuideline),
          reason: '$scene at $text×',
        );
        await expectLater(
          tester,
          meetsGuideline(textContrastGuideline),
          reason: '$scene at $text×',
        );
        await _close(tester);
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    handle.dispose();
  });

  for (final entry in _v13Routes.entries) {
    testWidgets('reduced motion: ${entry.key} stops animating once shown', (
      tester,
    ) async {
      _useLayout(tester, _layouts.last);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = TestApp(db, FakeClock(DateTime(2028, 1, 5)));
      final route = await entry.value(app);
      await tester.pumpWidget(reviewApp(db, app.clock, route));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: '${entry.key}: nothing animates with reduced motion',
      );
      await _close(tester);
    });
  }
}
