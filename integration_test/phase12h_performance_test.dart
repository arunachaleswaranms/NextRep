import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';

import '../test/support/arcs.dart';
import '../test/support/fakes.dart';
import '../test/support/pause_support.dart';
import '../test/support/restart_support.dart';
import '../test/support/review_app.dart';
import '../test/support/review_db.dart';
import '../test/support/ui.dart';

/// Phase 12H performance measurements (brief § 13; ARC_MOMENTUM_SPEC § 10:
/// "recorded, not gated"). Informational only: nothing here fails on a
/// time. It records, on a device in **profile** mode, how long each
/// representative operation takes from the action to the first settled
/// frame, over several iterations, and prints `PERF <name>: …` lines and
/// `reportData`.
///
/// The history is synthetic and built in-process through the app's own
/// services on an in-memory database: a completed Arc, an Arc ended by
/// Restart with a pause, and an active Arc on Day 86 (all 13 weeks,
/// Week 13 open) with a pause of its own.
///
/// Run on a disposable emulator only (it installs `com.nextrep.nextrep`):
/// `flutter drive --profile --driver=test_driver/integration_test.dart
///  --target=integration_test/phase12h_performance_test.dart -d DEVICE`
/// Never on a device holding the official app.

const _iterations = 5;
final _results = <String, List<int>>{};

Future<void> _measure(
  WidgetTester tester,
  String name,
  Future<void> Function() action, {
  Future<void> Function()? reset,
}) async {
  for (var i = 0; i < _iterations; i++) {
    if (reset != null) await reset();
    final watch = Stopwatch()..start();
    await action();
    await tester.pumpAndSettle();
    watch.stop();
    (_results[name] ??= []).add(watch.elapsedMilliseconds);
  }
}

String _summary(List<int> ms) {
  final sorted = [...ms]..sort();
  return 'median ${sorted[sorted.length ~/ 2]} ms, min ${sorted.first}, '
      'max ${sorted.last}, n ${ms.length}';
}

Future<void> _screens(
  WidgetTester tester,
  TestApp app,
  int endedId,
  String mode,
  Future<void> Function(String) open,
  Future<void> Function(String) openAt,
) async {
  await openAt(AppRoutes.today); // warm-up
  await _measure(tester, 'open Today (Day 86, populated) [$mode]', () async {
    await open(AppRoutes.today);
  });
  for (final week in [1, 7, 13]) {
    await _measure(tester, 'open Weekly Review, week $week [$mode]', () async {
      await open(AppRoutes.activeReview(week));
    });
  }
  await _measure(
    tester,
    'switch Journey to the 92-day Calendar [$mode]',
    () async {
      await tester.tap(find.text('Calendar'));
    },
    reset: () async {
      await openAt(AppRoutes.journey);
      await tester.tap(find.text('Path'));
      await tester.pumpAndSettle();
    },
  );
  await _measure(tester, 'open Arc History (3 Arcs) [$mode]', () async {
    await open(AppRoutes.history);
  });
  await _measure(tester, 'open an ended Arc summary [$mode]', () async {
    await open(AppRoutes.arc(endedId));
  });
  await _measure(tester, 'open Sound & Feedback [$mode]', () async {
    await open(AppRoutes.soundSettings);
  });
  await openAt(AppRoutes.today);
  for (final tab in ['Journey', 'Journal', 'History', 'Today']) {
    await _measure(tester, 'tab to $tab [$mode]', () async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(tab),
        ),
      );
    });
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile timings of the v1.3 screens', (tester) async {
    final db = memoryDatabase();
    final app = TestApp(db, FakeClock(DateTime(2026, 7, 1, 8)));
    await runFirstArc(app); // completed
    final first = LocalDate(2027, 1, 4);
    final ended = await startRolling(app, first);
    await liveDays(app, first, first.addDays(9));
    at(app, first.addDays(9), hour: 21);
    await pauseServiceOf(app)
        .pause(sessionId: ended.id, frozenFrom: first.addDays(10));
    at(app, first.addDays(14));
    await pauseServiceOf(app)
        .resume(sessionId: ended.id, on: first.addDays(14));
    await liveDays(app, first.addDays(14), first.addDays(30));
    at(app, first.addDays(31), hour: 12);
    final active = (await restartNow(app, ended.id)).started;
    final day1 = active.startDate;
    await liveDays(app, day1, day1.addDays(39));
    at(app, day1.addDays(39), hour: 21);
    await pauseServiceOf(app)
        .pause(sessionId: active.id, frozenFrom: day1.addDays(40));
    at(app, day1.addDays(45));
    await pauseServiceOf(app)
        .resume(sessionId: active.id, on: day1.addDays(45));
    final resumed = await stored(app, active.id);
    await liveDays(app, day1.addDays(45), resumed.dateOfDay(85)!);
    at(app, resumed.dateOfDay(86)!, hour: 9);
    final backup = (await app.backup.export()).bytes;

    Future<void> open(String route) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(reviewApp(db, app.clock, route));
    }

    Future<void> openAt(String route) async {
      await open(route);
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
    }

    for (final still in [false, true]) {
      // With reduced motion every transition is instant, so the settle
      // time is the work itself; without it, it includes the app's
      // entry motion.
      final mode = still ? 'reduced motion' : 'animations on';
      if (still) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
      }
      await _screens(tester, app, ended.id, mode, open, openAt);
    }
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    // Paused: the active Arc paused from tomorrow, viewed during the pause.
    await pauseServiceOf(app)
        .pause(sessionId: active.id, frozenFrom: app.clock.today().addDays(1));
    at(app, app.clock.today().addDays(3));
    await _measure(tester, 'open a paused Arc (Today)', () async {
      await open(AppRoutes.today);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));

    // Restore of the complex backup (service only, no UI), into a fresh
    // database each time.
    for (var i = 0; i < _iterations; i++) {
      final target = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
      final watch = Stopwatch()..start();
      await target.backup.restore(await target.backup.inspect(backup));
      watch.stop();
      (_results['inspect + restore the complex backup'] ??= []).add(
        watch.elapsedMilliseconds,
      );
      await target.db.close();
    }

    final report = <String, Object>{};
    for (final entry in _results.entries) {
      // ignore: avoid_print
      print('PERF ${entry.key}: ${_summary(entry.value)} ${entry.value}');
      report[entry.key] = entry.value;
    }
    binding.reportData = {'phase12h_timings_ms': report};
    await db.close();
  });
}
