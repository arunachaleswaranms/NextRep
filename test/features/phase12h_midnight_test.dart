import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';

import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// Phase 12H: midnight while a v1.3 screen is open (brief § 10), for the
/// screens earlier phases did not cover (Today, the Weekly Review, the
/// Calendar, Confirm & Start, the Pause and Resume sheets, a scheduled
/// pause and the Restart screen are covered in 12B–12G).
///
/// Each screen is opened at 23:59:30; the clock then passes midnight and
/// the app's day-change ticker runs. The screen must stay usable, nothing
/// may be written (every table identical: a view or a pending confirmation
/// never becomes an action by itself), and no completion sound may play.
/// All data synthetic.

final _day1 = LocalDate(2028, 1, 5);
LocalDate _d(int n) => _day1.addDays(n - 1);

typedef _Scene = ({
  String name,
  Future<String> Function(TestApp app) seed,
  Finder still,
});

final _scenes = <_Scene>[
  (
    name: 'Delete Arc after a restart (DELETE not typed)',
    seed: (app) async {
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(6));
      at(app, _d(7), hour: 12);
      await restartNow(app, arc.id);
      return AppRoutes.deleteArc(arc.id, afterRestart: true);
    },
    still: find.text('Delete your previous Arc?'),
  ),
  (
    name: 'Sound & Feedback',
    seed: (app) async {
      await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(2));
      return AppRoutes.soundSettings;
    },
    still: find.text('Ice Crystal'),
  ),
  (
    name: 'Habit Setup (reorder)',
    seed: (app) async {
      at(app, _day1);
      await app.winterArc.beginSetup();
      return AppRoutes.habitSetup;
    },
    still: find.byType(Scrollable),
  ),
  (
    name: 'saved setup hub',
    seed: (app) async {
      at(app, _day1);
      await app.winterArc.beginSetup();
      return AppRoutes.savedSetup;
    },
    still: find.text('Your Arc Setup Is Saved'),
  ),
  (
    name: 'an ended Arc summary',
    seed: (app) async {
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(6));
      at(app, _d(7), hour: 12);
      await restartNow(app, arc.id);
      return AppRoutes.arc(arc.id);
    },
    still: find.textContaining('Ended early'),
  ),
  (
    name: 'Arc History with an ended and a paused Arc',
    seed: (app) async {
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(6));
      at(app, _d(7), hour: 12);
      final fresh = (await restartNow(app, arc.id)).started;
      await pauseServiceOf(app).pause(sessionId: fresh.id, frozenFrom: _d(8));
      return AppRoutes.history;
    },
    still: find.byType(NavigationBar),
  ),
  (
    name: 'paused Journey calendar',
    seed: (app) async {
      final arc = await startRolling(app, _day1);
      await liveDays(app, _d(1), _d(6));
      await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(7));
      at(app, _d(9));
      return AppRoutes.journey;
    },
    still: find.byType(NavigationBar),
  ),
];

void main() {
  for (final scene in _scenes) {
    testWidgets('midnight with ${scene.name} open: still usable, nothing '
        'written, no sound', (tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final db = memoryDatabase();
      addTearDown(db.close);
      final app = TestApp(db, FakeClock(DateTime(2028, 1, 5)));
      final route = await scene.seed(app);
      final today = app.clock.today();
      app.clock.current = DateTime(
        today.year,
        today.month,
        today.day,
        23,
        59,
        30,
      );
      final player = FakeSoundPlayer();
      await tester.pumpWidget(
        reviewApp(
          db,
          app.clock,
          route,
          overrides: [soundPlayerProvider.overrideWithValue(player)],
        ),
      );
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(scene.still, findsWidgets, reason: 'opened');
      final before = await snapshotAll(db);

      final next = today.addDays(1);
      app.clock.current = DateTime(next.year, next.month, next.day, 0, 0, 2);
      await tester.pump(const Duration(seconds: 40));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);

      expect(tester.takeException(), isNull);
      expect(scene.still, findsWidgets, reason: 'still shown after midnight');
      expect(await snapshotAll(db), before, reason: 'nothing written');
      expect(player.plays, isEmpty, reason: 'no sound at midnight');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('control: in this harness the day change does reach the app '
      '(Today moves from Day 3 to Day 4)', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    addTearDown(db.close);
    final app = TestApp(db, FakeClock(DateTime(2028, 1, 5)));
    await startRolling(app, _day1);
    app.clock.current = DateTime(2028, 1, 7, 23, 59, 30);
    await tester.pumpWidget(reviewApp(db, app.clock, AppRoutes.today));
    await tester.pumpAndSettle();
    expect(find.text('Day 3 of 92'), findsOneWidget);
    app.clock.current = DateTime(2028, 1, 8, 0, 0, 2);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('Day 4 of 92'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
