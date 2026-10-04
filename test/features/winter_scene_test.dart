import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/domain/journey/arc_milestones.dart';
import 'package:nextrep/shared/winter_scene/scene_progress.dart';
import 'package:nextrep/shared/winter_scene/winter_scene.dart';

void main() {
  group('SceneProgress', () {
    test('Day 1: frozen trail, no camp, aurora or shelter', () {
      final s = SceneProgress(dayNumber: 1);
      expect(s.milestone, ArcMilestone.frozenTrail);
      expect(s.journey, 0);
      expect(s.campLit, isFalse);
      expect(s.aurora, 0);
      expect(s.shelterGlow, 0);
      expect(s.summitRevealed, isFalse);
    });

    test('Day 7: first camp lights up', () {
      final s = SceneProgress(dayNumber: 7);
      expect(s.campLit, isTrue);
      expect(s.forestCamp, isFalse);
    });

    test('Day 14: the forest camp grows', () {
      expect(SceneProgress(dayNumber: 13).forestCamp, isFalse);
      expect(SceneProgress(dayNumber: 14).forestCamp, isTrue);
    });

    test('Day 30: the ridge comes out of the fog', () {
      expect(SceneProgress(dayNumber: 29).ridgeVisible, isFalse);
      final s = SceneProgress(dayNumber: 30);
      expect(s.ridgeVisible, isTrue);
      expect(
        s.summitReveal,
        greaterThan(SceneProgress(dayNumber: 29).summitReveal),
      );
    });

    test('Day 45: the aurora appears, restrained', () {
      expect(SceneProgress(dayNumber: 44).aurora, 0);
      expect(SceneProgress(dayNumber: 45).aurora, inExclusiveRange(0, 1));
    });

    test('Day 60: the high ridge', () {
      expect(SceneProgress(dayNumber: 59).highRidge, isFalse);
      expect(SceneProgress(dayNumber: 60).highRidge, isTrue);
    });

    test('Day 75: the summit shelter glows', () {
      expect(SceneProgress(dayNumber: 74).shelterGlow, 0);
      expect(SceneProgress(dayNumber: 75).shelterGlow, greaterThan(0));
    });

    test('Day 92: the summit is fully revealed', () {
      final s = SceneProgress(dayNumber: 92);
      expect(s.summitRevealed, isTrue);
      expect(s.summitReveal, 1);
      expect(s.aurora, 1);
      expect(s.shelterGlow, 1);
      expect(s.journey, 1);
    });

    test('stays inside the arc and never goes backwards', () {
      expect(SceneProgress(dayNumber: 400).dayNumber, 92);
      expect(SceneProgress(dayNumber: 400).journey, 1);
      expect(SceneProgress(dayNumber: -3).dayNumber, 1);
      var previous = SceneProgress(dayNumber: 1);
      for (var day = 2; day <= 92; day++) {
        final s = SceneProgress(dayNumber: day);
        expect(s.journey, greaterThan(previous.journey));
        expect(s.summitReveal, greaterThanOrEqualTo(previous.summitReveal));
        expect(s.aurora, greaterThanOrEqualTo(previous.aurora));
        previous = s;
      }
    });

    test('results only change the light, never the stage', () {
      final plain = SceneProgress(dayNumber: 20);
      final perfect = SceneProgress(
        dayNumber: 20,
        dayCompletion: 1,
        perfect: true,
      );
      final minimum = SceneProgress(
        dayNumber: 20,
        dayCompletion: 0.5,
        minimum: true,
      );
      expect(perfect.milestone, plain.milestone);
      expect(perfect.warmth, 1);
      expect(plain.warmth, 0);
      expect(minimum.recovery, isTrue);
      expect(minimum.warmth, closeTo(0.3, 1e-9));
    });
  });

  group('WinterScene ambient motion', () {
    Widget scene({bool ambient = true}) => ProviderScope(
      overrides: [ambientMotionProvider.overrideWithValue(ambient)],
      child: MaterialApp(
        theme: buildWinterTheme(),
        home: SizedBox(
          height: 200,
          child: WinterScene(scene: SceneProgress(dayNumber: 50)),
        ),
      ),
    );

    testWidgets('loops while visible and allowed', (tester) async {
      await tester.pumpWidget(scene());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      // Decorative: nothing in the scene reaches the semantics tree.
      expect(tester.getSemantics(find.byType(WinterScene)).label, isEmpty);
    });

    testWidgets('stops when the app is backgrounded, resumes after', (
      tester,
    ) async {
      await tester.pumpWidget(scene());
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('is still under reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle(); // would time out if anything looped
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('is still when a hidden tab mutes tickers', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildWinterTheme(),
            home: TickerMode(
              enabled: false,
              child: SizedBox(
                height: 200,
                child: WinterScene(scene: SceneProgress(dayNumber: 50)),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
