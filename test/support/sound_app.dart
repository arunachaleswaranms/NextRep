import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';

import 'fakes.dart';
import 'sound_fakes.dart';
import 'ui.dart';

/// NextRep with a recording sound player and a hand-moved monotonic clock
/// (Phase 12G widget tests).
Widget soundApp(
  TestApp app, {
  required FakeSoundPlayer player,
  required FakeMonotonic monotonic,
  List<Override> extra = const [],
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(app.db),
    clockProvider.overrideWithValue(app.clock),
    ambientMotionProvider.overrideWithValue(false),
    reminderSchedulerProvider.overrideWithValue(app.scheduler),
    soundPlayerProvider.overrideWithValue(player),
    monotonicClockProvider.overrideWithValue(monotonic.call),
    ...extra,
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> phoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// One habit of each kind, and nothing else, on a Rolling Arc started on
/// 4 Oct 2026 at 09:00 (the clock stays there):
///
/// * Stretch: binary
/// * Glasses: count, target 3, minimum 1
/// * Focus: duration, target 10 min, minimum 5 (two steps of 5)
/// * Lights Out: clock time, goal 23:00
Future<TestApp> fourKindsArc() async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 4, 9)));
  await app.winterArc.beginSetup();
  final starters = await app.winterArc.setupHabits();
  for (final draft in [
    const HabitDraft(
      title: 'Stretch',
      type: HabitType.binary,
      iconKey: 'mobility',
    ),
    const HabitDraft(
      title: 'Glasses',
      type: HabitType.count,
      iconKey: 'water',
      target: 3,
      minimumTarget: 1,
      unit: 'glasses',
    ),
    const HabitDraft(
      title: 'Focus',
      type: HabitType.duration,
      iconKey: 'learning',
      target: 10,
      minimumTarget: 5,
    ),
    HabitDraft(
      title: 'Lights Out',
      type: HabitType.timeBefore,
      iconKey: 'sleep',
      target: NightTime(23, 0).value,
    ),
  ]) {
    await app.winterArc.addCustomHabit(draft);
  }
  for (final habit in starters) {
    await app.winterArc.setHabitEnabled(habit.id, enabled: false);
  }
  await app.winterArc.startWinterArc();
  return app;
}

/// Records every haptic the app asks for (`HapticFeedback.*`).
List<String> recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

/// Taps a Today control by its tooltip, once nothing covers it, and lets
/// the save and its feedback finish.
Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await reveal(tester, find.byTooltip(tooltip));
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}
