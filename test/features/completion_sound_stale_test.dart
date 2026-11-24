import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/app_restart.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/feedback/completion_feedback.dart';
import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/sound/sound_settings_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_controller.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/fakes.dart';
import '../support/restart_support.dart';
import '../support/sound_app.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// Independent review correction G-R1: a sound whose screen, Arc or app
/// state is gone by the time its setting has been read never plays, and is
/// never replayed. Through the real Today and Sound & Feedback screens, the
/// real router (indexed-stack tabs) and Drift, with every setting read (and,
/// where needed, write) held on a Completer until the test releases it.
/// No real-time sleeps: the races are ordered by hand.
void main() {
  late FakeSoundPlayer player;
  late FakeMonotonic monotonic;
  late HeldFeedbackPreferences held;

  setUp(() {
    player = FakeSoundPlayer();
    monotonic = FakeMonotonic();
  });

  /// Lets every throttle window close.
  void later() => monotonic.advance(const Duration(seconds: 4));

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(NextRepApp)));

  /// The router's location, as the screens' sound origins see it.
  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Navigator).first))
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation;

  /// The four-kinds Arc on Today, with the engine's setting reads going
  /// through [held] (to the stored setting, or to [reads]). [settings] makes
  /// the settings screen's repository.
  Future<TestApp> open(
    WidgetTester tester, {
    FeedbackPreferencesRepository? reads,
    FeedbackPreferencesRepository Function(TestApp app)? settings,
  }) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    held = HeldFeedbackPreferences(
      reads ?? DriftFeedbackPreferencesRepository(app.db),
    );
    await tester.pumpWidget(
      soundApp(
        app,
        player: player,
        monotonic: monotonic,
        extra: [
          completionFeedbackProvider.overrideWithValue(
            CompletionFeedback(
              preferences: held,
              player: player,
              elapsed: monotonic.call,
            ),
          ),
          if (settings != null)
            feedbackPreferencesRepositoryProvider.overrideWithValue(
              settings(app),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(location(tester), AppRoutes.today);
    return app;
  }

  /// Completes Stretch: the completion is saved, and its sound is left
  /// waiting for the setting.
  Future<void> completeStretchHeld(WidgetTester tester) async {
    later();
    held.holding = true;
    await tapTooltip(tester, 'Complete Stretch');
    expect(held.waitingLoads, 1, reason: 'the sound waits for the setting');
    expect(player.plays, isEmpty);
  }

  Future<void> releaseReads(WidgetTester tester) async {
    held.release();
    await tester.pumpAndSettle();
  }

  Future<int> completedToday(TestApp app) async =>
      (await app.tracking.today()).completion.completed;

  Future<void> openTab(WidgetTester tester, String label) async {
    await clearCelebrations(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Reaches Focus's 10-minute target in two taps (the second sounds).
  Future<void> completeFocus(WidgetTester tester) async {
    await tapTooltip(tester, 'Add to Focus');
    await tapTooltip(tester, 'Add to Focus');
  }

  group('completions', () {
    testWidgets('1. still on Today when the setting arrives: one sound', (
      tester,
    ) async {
      final app = await open(tester);
      await completeStretchHeld(tester);
      await releaseReads(tester);
      expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);
      expect(await completedToday(app), 1);
      await shutDown(tester);
    });

    testWidgets('2. a page pushed over Today before the setting arrives: no '
        'sound, then or after coming back; the save stands', (tester) async {
      final app = await open(tester);
      await completeStretchHeld(tester);
      await clearCelebrations(tester);
      await reveal(tester, find.byTooltip('Reminders'));
      await tester.tap(find.byTooltip('Reminders'));
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.reminders);
      await releaseReads(tester);
      expect(player.plays, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.today);
      expect(player.plays, isEmpty, reason: 'never replayed on return');
      expect(await completedToday(app), 1);
      await shutDown(tester);
    });

    testWidgets('2b. the setting arrives after a page is pushed but before '
        'the next frame (Today still drawn, its tickers still on): no sound', (
      tester,
    ) async {
      // The setting comes from memory (microtasks only), so the engine
      // resumes without a frame. The router's location changes at once on
      // a push; tickers only at the next frame (or, with a page
      // transition, when it ends): only the location guard applies here.
      await open(tester, reads: FakeFeedbackPreferences());
      await completeStretchHeld(tester);
      await clearCelebrations(tester);
      await reveal(tester, find.byTooltip('Reminders'));
      final today = tester.element(find.byType(TodayScreen));
      bool tickersOn() => TickerMode.valuesOf(today).enabled;

      await tester.tap(find.byTooltip('Reminders')); // no frame pumped
      expect(location(tester), AppRoutes.reminders);
      expect(tickersOn(), isTrue, reason: 'no frame since the push');

      final returned = held.returned;
      held.release();
      for (var i = 0; i < 10; i++) {
        await Future<void>.value();
      }
      // `returned` counts the read handing back its value; the engine's
      // own continuation runs a microtask later, well within these ten.
      // The G-R1 mutation check confirms it: without the location guard
      // this test fails here.
      expect(held.returned, returned + 1, reason: 'the engine has resumed');
      expect(tickersOn(), isTrue);
      expect(player.plays, isEmpty);
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.reminders);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('3b. a page pushed outside the router over Today (as Share '
        'preview is): the location stays /today, the tickers stop: no '
        'sound; after closing it, the next completion sounds', (tester) async {
      await open(tester);
      await completeStretchHeld(tester);
      await clearCelebrations(tester);
      unawaited(
        Navigator.of(
          tester.element(find.byType(TodayScreen)),
          rootNavigator: true,
        ).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const Scaffold(body: Text('Preview')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.today);
      await releaseReads(tester);
      expect(player.plays, isEmpty);

      Navigator.of(tester.element(find.text('Preview'))).pop();
      await tester.pumpAndSettle();
      later();
      await completeFocus(tester);
      expect(player.plays, hasLength(1));
      await shutDown(tester);
    });

    testWidgets('3. another tab shown while Today stays mounted under it: no '
        'stale sound', (tester) async {
      await open(tester);
      await completeStretchHeld(tester);
      await openTab(tester, 'Journey');
      expect(location(tester), AppRoutes.journey);
      expect(
        find.byType(TodayScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'the indexed stack keeps Today mounted',
      );
      expect(
        tester.state(find.byType(TodayScreen, skipOffstage: false)).mounted,
        isTrue,
      );
      await releaseReads(tester);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('4, 9, 10. away and back before the setting arrives: the old '
        'request stays dropped; the next completion sounds at once, its '
        'window untouched by the dropped one', (tester) async {
      final app = await open(tester);
      await completeStretchHeld(tester);
      await openTab(tester, 'Journey');
      await openTab(tester, 'Today');
      expect(location(tester), AppRoutes.today);
      await releaseReads(tester);
      expect(player.plays, isEmpty);

      // No clock advance: the dropped request took no global window.
      await completeFocus(tester);
      expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);
      expect(await completedToday(app), 2);
      await shutDown(tester);
    });

    testWidgets('5, 9. an Arc Restart while the setting is read: the old '
        "Arc's sound never plays; the new Arc's completions do", (
      tester,
    ) async {
      final app = await open(tester);
      final old = (await app.sessions.currentSession())!;
      await completeStretchHeld(tester);

      // Restarted elsewhere (the service, as the Restart screen would), and
      // Today, still shown at /today, re-reads the new Arc.
      await restartNow(app, old.id);
      await container(tester).read(todayControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      final current = (await app.sessions.currentSession())!;
      expect(current.id, isNot(old.id));
      expect(
        container(tester).read(todayControllerProvider).value?.session.id,
        current.id,
      );
      expect(location(tester), AppRoutes.today);

      await releaseReads(tester);
      expect(player.plays, isEmpty);

      later();
      await tapTooltip(tester, 'Complete Stretch');
      expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);
      await shutDown(tester);
    });

    testWidgets('6. the Arc ends while the setting is read: no sound', (
      tester,
    ) async {
      final app = await open(tester);
      final arc = (await app.sessions.currentSession())!;
      await completeStretchHeld(tester);

      final end = arc.endDate;
      app.clock.current = DateTime(end.year, end.month, end.day + 1, 9);
      await container(tester).read(todayControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        isNot(WinterArcStatus.active),
      );
      expect(find.byType(SummaryScreen), findsOneWidget);

      await releaseReads(tester);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('7, 9. a new app epoch (restore) while the setting is read: '
        'no sound; the rebuilt Today sounds normally', (tester) async {
      // The setting comes from memory here (microtasks only), so the
      // engine can resume without a frame being pumped.
      await open(tester, reads: FakeFeedbackPreferences());
      await completeStretchHeld(tester);
      final returned = held.returned;
      final oldToday = tester.state(find.byType(TodayScreen));

      // The epoch moves and the setting arrives before any frame: the old
      // Today is still mounted and shown, so only the epoch cancels it.
      container(tester).read(appEpochProvider.notifier).restart();
      held.release();
      for (var i = 0; i < 10; i++) {
        await Future<void>.value();
      }
      // As in 2b: without the epoch guard this test fails here.
      expect(held.returned, returned + 1, reason: 'the engine has resumed');
      expect(oldToday.mounted, isTrue);
      expect(player.plays, isEmpty);

      await tester.pumpAndSettle();
      expect(oldToday.mounted, isFalse, reason: 'the epoch rebuilt Today');
      expect(location(tester), AppRoutes.today);
      expect(player.plays, isEmpty);

      later();
      await completeFocus(tester);
      expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);
      await shutDown(tester);
    });

    testWidgets('8, 9. backgrounded while the setting is read: no sound, '
        'not even after resuming; the next completion sounds', (tester) async {
      await open(tester);
      await completeStretchHeld(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      await releaseReads(tester);
      expect(player.plays, isEmpty);

      later();
      await completeFocus(tester);
      expect(player.plays, hasLength(1));
      await shutDown(tester);
    });

    testWidgets('8. Today disposed while the setting is read: no sound', (
      tester,
    ) async {
      final app = await open(tester);
      await completeStretchHeld(tester);
      await tester.pumpWidget(const SizedBox());
      held.release();
      await tester.pump(const Duration(seconds: 5));
      expect(player.plays, isEmpty);
      expect(await completedToday(app), 1);
    });

    testWidgets('20. a hung or failing player never affects what is saved', (
      tester,
    ) async {
      final app = await open(tester);
      player.hang = true;
      later();
      await tapTooltip(tester, 'Complete Stretch');
      expect(player.plays, hasLength(1));
      expect(await completedToday(app), 1);
      player
        ..hang = false
        ..failPlay = true;
      later();
      await completeFocus(tester);
      expect(player.plays, hasLength(2));
      expect(await completedToday(app), 2);
      expect(tester.takeException(), isNull);
      await shutDown(tester);
      await tester.pump(const Duration(days: 2)); // the hung call's timer
    });
  });

  group('previews', () {
    Finder preview(SoundTheme t) => find.byKey(ValueKey('preview-${t.name}'));
    Finder set(SoundTheme t) => find.byKey(ValueKey('sound-${t.name}'));
    Finder soundSwitch() => find.byKey(const ValueKey('sound-switch'));

    Future<void> openSettings(WidgetTester tester) async {
      await clearCelebrations(tester);
      await reveal(tester, find.byTooltip(SoundCopy.title));
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.soundSettings);
    }

    Future<void> tapShownControl(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }

    testWidgets('11. Sound & Feedback still shown when the setting arrives: '
        'the preview plays', (tester) async {
      await open(tester);
      await openSettings(tester);
      later();
      held.holding = true;
      await tapShownControl(tester, preview(SoundTheme.warmEmber));
      expect(held.waitingLoads, 1);
      await releaseReads(tester);
      expect(player.plays, [(SoundTheme.warmEmber, CompletionSound.habit)]);
      await shutDown(tester);
    });

    testWidgets('12, 13, 15. left (and reopened) while the setting is read: '
        'no preview; one asked for in the new screen plays', (tester) async {
      await open(tester);
      await openSettings(tester);
      later();
      held.holding = true;
      await tapShownControl(tester, preview(SoundTheme.warmEmber));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.today);
      await openSettings(tester);
      await releaseReads(tester);
      expect(player.plays, isEmpty);

      // No clock advance: the dropped preview took no window.
      await tapShownControl(tester, preview(SoundTheme.summitSpark));
      await tester.pumpAndSettle();
      expect(player.plays, [(SoundTheme.summitSpark, CompletionSound.habit)]);
      await shutDown(tester);
    });

    testWidgets('a preview read pending while the app is backgrounded: '
        'dropped; a new preview after resuming plays', (tester) async {
      await open(tester);
      await openSettings(tester);
      later();
      held.holding = true;
      await tapShownControl(tester, preview(SoundTheme.warmEmber));
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await releaseReads(tester);
      expect(player.plays, isEmpty);
      await tapShownControl(tester, preview(SoundTheme.iceCrystal));
      await tester.pumpAndSettle();
      expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);
      await shutDown(tester);
    });

    testWidgets('14. a set chosen, then another page shown over Sound & '
        'Feedback before the save finishes (the screen still mounted '
        'under it): stored, never previewed, not even on return', (
      tester,
    ) async {
      // The settings screen's writes are held too.
      late HeldFeedbackPreferences settings;
      final app = await open(
        tester,
        settings: (app) => settings = HeldFeedbackPreferences(
          DriftFeedbackPreferencesRepository(app.db),
        ),
      );
      await openSettings(tester);
      later();
      settings.holdSaves = true;
      await tapShownControl(tester, set(SoundTheme.summitSpark));
      expect(settings.waitingSaves, 1);

      // Replaced by another page (as a notification tap or deep link
      // would): the settings screen stays mounted underneath, so `mounted`
      // alone would let its preview through.
      unawaited(
        GoRouter.of(tester.element(find.byType(SoundSettingsScreen)))
            .push(AppRoutes.about),
      );
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.about);
      final screen = find.byType(SoundSettingsScreen, skipOffstage: false);
      expect(tester.state(screen).mounted, isTrue);

      settings.releaseSaves();
      await tester.pumpAndSettle();
      expect(player.plays, isEmpty);
      expect(
        await DriftFeedbackPreferencesRepository(app.db).load(),
        const FeedbackPreferences(
          soundsEnabled: true,
          soundTheme: SoundTheme.summitSpark,
        ),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.soundSettings);
      expect(player.plays, isEmpty, reason: 'never replayed on return');

      // Left by Back while the save is held: disposed when it finishes.
      later();
      settings.holdSaves = true;
      await tapShownControl(tester, set(SoundTheme.warmEmber));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.today);
      settings.releaseSaves();
      await tester.pumpAndSettle();
      expect(player.plays, isEmpty);
      expect(
        (await DriftFeedbackPreferencesRepository(app.db).load()).soundTheme,
        SoundTheme.warmEmber,
      );
      await shutDown(tester);
    });

    testWidgets('16. sounds turned off while a preview reads the setting: '
        'nothing plays', (tester) async {
      final app = await open(tester);
      await openSettings(tester);
      later();
      held.holding = true;
      await tapShownControl(tester, preview(SoundTheme.warmEmber));
      expect(held.waitingLoads, 1);
      await tapShownControl(tester, soundSwitch());
      await tester.pumpAndSettle();
      expect(
        (await DriftFeedbackPreferencesRepository(app.db).load()).soundsEnabled,
        isFalse,
      );
      await releaseReads(tester);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('16b. sounds turned off while a preview reads the setting, '
        'even if the read still says "on": the switch drops it', (
      tester,
    ) async {
      // The engine's read returns "on" whatever is stored, so only the
      // switch cancelling the screen's pending previews can stop it.
      await open(tester, reads: FakeFeedbackPreferences());
      await openSettings(tester);
      later();
      held.holding = true;
      await tapShownControl(tester, preview(SoundTheme.warmEmber));
      expect(held.waitingLoads, 1);
      await tapShownControl(tester, soundSwitch());
      await tester.pumpAndSettle();
      expect(location(tester), AppRoutes.soundSettings);
      await releaseReads(tester);
      expect(held.returned, greaterThan(0));
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });
  });
}
