import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/features/focus_guard/focus_guard_app_picker_screen.dart';
import 'package:nextrep/features/focus_guard/focus_guard_card.dart';
import 'package:nextrep/features/focus_guard/focus_guard_settings_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/share/share_choice_sheet.dart';
import 'package:nextrep/features/share/share_preview_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

/// Phase 11C: Focus Guard's settings, app picker and Today card, over the
/// real services and Drift, with Android's facilities faked. Synthetic
/// package names only.
const _video = 'org.example.video';
const _chat = 'org.example.chat';
const _game = 'org.example.game';

const _installed = [
  LaunchableAppCandidate(packageName: _video, label: 'Video Stream'),
  LaunchableAppCandidate(packageName: _chat, label: 'Chat Hub'),
  LaunchableAppCandidate(packageName: _game, label: 'Puzzle Game'),
  LaunchableAppCandidate(packageName: nextRepPackage, label: 'NextRep'),
];

Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FocusGuardPlatform? platform,
  FakeFocusGuardBackgroundScheduler? background,
  FakeReminderScheduler? scheduler,
  Stream<String?>? taps,
  String? launchPayload,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    if (platform != null)
      focusGuardPlatformProvider.overrideWithValue(platform),
    if (background != null)
      focusGuardSchedulerProvider.overrideWithValue(background),
    if (scheduler != null)
      reminderSchedulerProvider.overrideWithValue(scheduler),
    if (taps != null) reminderTapsProvider.overrideWithValue(taps),
    if (launchPayload != null)
      reminderLaunchPayloadProvider.overrideWithValue(launchPayload),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _textScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// Scrolls the screen's list until [finder] is built and visible.
Future<Finder> _seek(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return finder;
}

Finder get _card => find.byType(FocusGuardCard);

Finder _inCard(String text) =>
    find.descendant(of: _card, matching: find.text(text));

Finder get _switch => find.descendant(
  of: find.widgetWithText(SwitchListTile, 'Focus Guard'),
  matching: find.byType(Switch),
);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TestApp app;
  late FakeFocusGuardPlatform platform;
  late FakeFocusGuardBackgroundScheduler background;
  late FakeReminderScheduler scheduler;

  /// An active arc started on Thu 1 Oct 2026; the clock at 18:00 on Day 1.
  Future<void> seed({bool arc = true}) async {
    db = memoryDatabase();
    addTearDown(db.close);
    clock = FakeClock(DateTime(2026, 10, 1, 18));
    scheduler = FakeReminderScheduler(granted: true);
    platform = FakeFocusGuardPlatform(apps: _installed);
    background = FakeFocusGuardBackgroundScheduler();
    app = TestApp(db, clock, scheduler: scheduler);
    if (arc) {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
    }
  }

  /// Focus Guard on with two apps and a 60-minute budget, Usage Access
  /// granted.
  Future<void> configureOn({int budget = 60}) async {
    platform.access = UsageAccess.granted;
    await DriftFocusGuardSettingsRepository(db).save(
      FocusGuardSettings(
        enabled: true,
        dailyBudgetMinutes: budget,
        selectedPackages: const [_video, _chat],
      ),
      at: clock.now(),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(
      _app(
        db,
        clock,
        platform: platform,
        background: background,
        scheduler: scheduler,
      ),
    );
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await reveal(tester, _card);
    await _tap(tester, _card);
    expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
  }

  group('iOS and other platforms', () {
    testWidgets('unsupported: no card, nothing scheduled, Today works', (
      tester,
    ) async {
      await seed();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Focus Guard'), findsNothing);
      expect(find.textContaining('FOCUS GUARD'), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('the settings route still explains itself', (tester) async {
      await seed();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(TodayScreen));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const FocusGuardSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Focus Guard is available on Android.'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      await _shutDown(tester);
    });
  });

  group('settings', () {
    testWidgets('off by default: a discovery card on Today; settings explain '
        'Focus Guard; nothing is asked or opened at startup', (tester) async {
      await seed();
      await launch(tester);
      await reveal(tester, _card);
      expect(_inCard('Focus Guard'), findsOneWidget);
      expect(
        _inCard('Stay aware of time spent in selected apps.'),
        findsOneWidget,
      );
      expect(platform.settingsOpened, 0);
      expect(scheduler.permissionRequests, 0);
      expect(background.scheduled, isFalse);

      await openSettings(tester);
      expect(find.text('FOCUS GUARD'), findsOneWidget);
      expect(
        find.text(
          'Focus Guard sends a gentle reminder when your selected apps '
          'reach their combined daily budget.',
        ),
        findsOneWidget,
      );
      expect(find.text('It does not block apps.'), findsOneWidget);
      expect(tester.widget<Switch>(_switch).value, isFalse);
      // Usage Access and apps are missing: it can't be switched on.
      expect(tester.widget<Switch>(_switch).onChanged, isNull);
      expect(find.text('Not allowed'), findsOneWidget);
      expect(find.text('Allow Usage Access'), findsOneWidget);
      expect(find.text('60 min'), findsNothing); // shown as "1 h"
      expect(await _seek(tester, find.text('1 h')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('around 15 minutes apart'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('If NextRep is force-stopped, checks resume'),
        findsOneWidget,
      );
      expect(platform.settingsOpened, 0);
      await _shutDown(tester);
    });

    testWidgets('the grant action opens Usage Access settings only when '
        'tapped; returning updates the status', (tester) async {
      await seed();
      await launch(tester);
      await openSettings(tester);
      await _resume(tester);
      expect(platform.settingsOpened, 0, reason: 'never on resume');

      await _tap(tester, find.text('Allow Usage Access'));
      expect(platform.settingsOpened, 1);
      platform.access = UsageAccess.granted; // granted in system settings
      await _resume(tester);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Manage Usage Access'), findsOneWidget);
      expect(platform.settingsOpened, 1);
      await _shutDown(tester);
    });

    testWidgets('choose apps: launcher apps without NextRep, searchable, '
        'several at once; saved by package name', (tester) async {
      await seed();
      platform.access = UsageAccess.granted;
      await launch(tester);
      await openSettings(tester);
      expect(
        await _seek(
          tester,
          find.text(
            'No apps chosen yet. Only the apps you choose are measured.',
          ),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Choose apps'));
      expect(find.byType(FocusGuardAppPickerScreen), findsOneWidget);
      expect(find.text('NextRep'), findsNothing);
      expect(find.text('Video Stream'), findsOneWidget);
      // Nothing is pre-selected.
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .where((tile) => tile.value == true),
        isEmpty,
      );

      await tester.enterText(find.byType(TextField), 'chat');
      await tester.pumpAndSettle();
      expect(find.text('Video Stream'), findsNothing);
      await _tap(tester, find.text('Chat Hub'));
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Video Stream'));
      expect(find.text('2 chosen · up to 100'), findsOneWidget);
      await _tap(tester, find.text('Save'));

      expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
      expect(await _seek(tester, find.text('Chat Hub')), findsOneWidget);
      expect(find.text('Video Stream'), findsOneWidget);
      final stored = await DriftFocusGuardSettingsRepository(db).load();
      expect(stored.selectedPackages, [_chat, _video]);
      expect(
        stored.enabled,
        isFalse,
        reason: 'choosing apps never turns it on',
      );
      await _shutDown(tester);
    });

    testWidgets('an app uninstalled after being chosen is shown and can be '
        'removed; no apps found says so', (tester) async {
      await seed();
      platform
        ..access = UsageAccess.granted
        ..apps = const [];
      await DriftFocusGuardSettingsRepository(db).save(
        const FocusGuardSettings(
          enabled: false,
          dailyBudgetMinutes: 60,
          selectedPackages: [_game],
        ),
        at: clock.now(),
      );
      await launch(tester);
      await openSettings(tester);
      expect(await _seek(tester, find.text(_game)), findsOneWidget);
      expect(find.text('Not installed'), findsOneWidget);

      await _tap(tester, find.text('Edit apps'));
      expect(find.text('No longer installed'), findsOneWidget);
      expect(find.text('No apps to show.'), findsOneWidget);
      await _tap(tester, find.text(_game));
      await _tap(tester, find.text('Save'));
      expect(
        (await DriftFocusGuardSettingsRepository(db).load()).selectedPackages,
        isEmpty,
      );
      await _shutDown(tester);
    });

    testWidgets('budget: a preset or a custom value; invalid values save '
        'nothing', (tester) async {
      await seed();
      await launch(tester);
      await openSettings(tester);
      await _seek(tester, find.text('Combined daily budget'));
      await _tap(tester, find.bySemanticsLabel('Combined daily budget, 1 h'));
      await _tap(tester, find.widgetWithText(ChoiceChip, '30 min'));
      await _tap(tester, find.text('Save'));
      expect(
        (await DriftFocusGuardSettingsRepository(db).load()).dailyBudgetMinutes,
        30,
      );
      expect(find.text('30 min'), findsOneWidget);

      await _tap(
        tester,
        find.bySemanticsLabel('Combined daily budget, 30 min'),
      );
      for (final bad in ['0', '1441']) {
        await tester.enterText(find.byType(TextField), bad);
        await _tap(tester, find.text('Save'));
        expect(find.text('Enter 1 to 1440 minutes.'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), '95');
      await _tap(tester, find.text('Save'));
      expect(find.text('1 h 35 min'), findsOneWidget);
      expect(
        (await DriftFocusGuardSettingsRepository(db).load()).dailyBudgetMinutes,
        95,
      );
      await _shutDown(tester);
    });

    testWidgets('turning it on schedules the check; denied notifications '
        'still measure and say so; off cancels and keeps the setup', (
      tester,
    ) async {
      await seed();
      platform
        ..access = UsageAccess.granted
        ..nudges = false;
      scheduler
        ..granted = false
        ..grant = false;
      await DriftFocusGuardSettingsRepository(db).save(
        const FocusGuardSettings(
          enabled: false,
          dailyBudgetMinutes: 45,
          selectedPackages: [_video],
        ),
        at: clock.now(),
      );
      await launch(tester);
      await openSettings(tester);
      await _tap(tester, _switch);
      expect(scheduler.permissionRequests, 1);
      expect(
        find.textContaining('Notifications are off, so it can measure'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(_switch).value, isTrue);
      expect(find.text('On. Checking in the background.'), findsOneWidget);
      expect(background.scheduled, isTrue);
      expect(
        await _seek(tester, find.text('Off')),
        findsOneWidget,
      ); // the notifications card
      await tester.scrollUntilVisible(
        _switch,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await _tap(tester, _switch);
      expect(tester.widget<Switch>(_switch).value, isFalse);
      expect(background.scheduled, isFalse);
      final stored = await DriftFocusGuardSettingsRepository(db).load();
      expect(stored.selectedPackages, [_video]);
      expect(stored.dailyBudgetMinutes, 45);
      await _shutDown(tester);
    });

    testWidgets('revoked while on: shown as paused, the check cancelled on '
        'resume, nothing fabricated', (tester) async {
      await seed();
      await configureOn();
      await launch(tester);
      expect(background.scheduled, isTrue);
      platform.access = UsageAccess.notGranted;
      await _resume(tester);
      expect(background.scheduled, isFalse);
      await reveal(tester, _card);
      expect(_inCard('0 / 60 min'), findsNothing);
      expect(
        find.descendant(
          of: _card,
          matching: find.textContaining('Usage Access is off'),
        ),
        findsOneWidget,
      );
      await openSettings(tester);
      expect(find.text('On, but paused: Usage Access is off.'), findsOneWidget);
      await _shutDown(tester);
    });
  });

  group('Today card', () {
    Future<void> showUsage(WidgetTester tester, Duration total) async {
      platform.usage = {_video: total ~/ 2, _chat: total - total ~/ 2};
      await _resume(tester);
      await reveal(tester, _card);
    }

    testWidgets('below, near, exactly and over the budget', (tester) async {
      await seed();
      await configureOn();
      await launch(tester);

      await showUsage(tester, Duration.zero);
      expect(_inCard('0 / 60 min'), findsOneWidget);
      expect(_inCard('60 min remaining'), findsOneWidget);
      expect(_inCard('Shield strong'), findsOneWidget);

      await showUsage(tester, const Duration(minutes: 38));
      expect(_inCard('38 / 60 min'), findsOneWidget);
      expect(_inCard('22 min remaining'), findsOneWidget);
      expect(_inCard('Shield strong'), findsOneWidget);

      await showUsage(tester, const Duration(minutes: 50));
      expect(_inCard("Near today's limit"), findsOneWidget);
      expect(_inCard('10 min remaining'), findsOneWidget);

      await showUsage(tester, const Duration(minutes: 59, seconds: 59));
      expect(_inCard('59 / 60 min'), findsOneWidget);
      expect(_inCard('1 min remaining'), findsOneWidget);

      await showUsage(tester, const Duration(minutes: 60));
      expect(_inCard('60 / 60 min'), findsOneWidget);
      expect(_inCard('Budget reached'), findsOneWidget);
      expect(
        _inCard('Budget reached. Tomorrow is a fresh day.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Focus Guard. 60 of 60 minutes used today. Budget reached. '
          'Tomorrow is a fresh day.',
        ),
        findsOneWidget,
      );

      await showUsage(tester, const Duration(minutes: 75));
      expect(_inCard('75 / 60 min'), findsOneWidget);
      for (final word in ['failed', 'broken', 'wasted', 'lost', 'streak']) {
        expect(
          find.descendant(of: _card, matching: find.textContaining(word)),
          findsNothing,
        );
      }
      await _shutDown(tester);
    });

    testWidgets('the budget changing in settings updates the card', (
      tester,
    ) async {
      await seed();
      await configureOn();
      platform.usage = const {_video: Duration(minutes: 40)};
      await launch(tester);
      await reveal(tester, _card);
      expect(_inCard('40 / 60 min'), findsOneWidget);
      await openSettings(tester);
      await _seek(tester, find.text('Combined daily budget'));
      await _tap(tester, find.bySemanticsLabel('Combined daily budget, 1 h'));
      await _tap(tester, find.widgetWithText(ChoiceChip, '45 min'));
      await _tap(tester, find.text('Save'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await reveal(tester, _card);
      expect(_inCard('40 / 45 min'), findsOneWidget);
      expect(_inCard("Near today's limit"), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('a failed measurement says so; never a stale value', (
      tester,
    ) async {
      await seed();
      await configureOn();
      platform.usage = const {_video: Duration(minutes: 30)};
      await launch(tester);
      await reveal(tester, _card);
      expect(_inCard('30 / 60 min'), findsOneWidget);
      platform.failQuery = true;
      await _resume(tester);
      await reveal(tester, _card);
      expect(_inCard('30 / 60 min'), findsNothing);
      expect(
        _inCard("Today's time couldn't be read right now."),
        findsOneWidget,
      );
      await _shutDown(tester);
    });

    testWidgets('notifications off is mentioned on the card', (tester) async {
      await seed();
      await configureOn();
      platform.nudges = false;
      await launch(tester);
      await reveal(tester, _card);
      expect(
        find.descendant(
          of: _card,
          matching: find.textContaining('Notifications are off'),
        ),
        findsOneWidget,
      );
      await _shutDown(tester);
    });

    testWidgets('local midnight: the card re-reads the new day', (
      tester,
    ) async {
      await seed();
      await configureOn();
      platform.usage = const {_video: Duration(minutes: 70)};
      clock.current = DateTime(2026, 10, 1, 23, 59, 50);
      await launch(tester);
      await reveal(tester, _card);
      expect(_inCard('Budget reached'), findsOneWidget);
      platform.usage = const {};
      clock.current = DateTime(2026, 10, 2, 0, 0, 2);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await reveal(tester, _card);
      expect(_inCard('0 / 60 min'), findsOneWidget);
      expect(platform.queries.last.from, DateTime(2026, 10, 2));
      await _shutDown(tester);
    });

    testWidgets('accessible label, and 2× text without overflow', (
      tester,
    ) async {
      await seed();
      await configureOn();
      _textScale(tester, 2);
      platform.usage = const {_video: Duration(minutes: 38)};
      await launch(tester);
      await reveal(tester, _card);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Focus Guard\. 38 of 60 minutes used today\. 22 min '
            r'remaining\. Shield strong\.$',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('How it works'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });

    testWidgets('reaching the budget changes no habit, XP or streak data', (
      tester,
    ) async {
      await seed();
      await completeHabit(app, 'water');
      final session = (await app.winterArc.currentSession())!;
      await configureOn(budget: 1);
      await launch(tester);
      await reveal(tester, _card);
      expect(_inCard('Shield strong'), findsOneWidget);
      final before = await snapshotOf(db, session.id);
      platform.usage = const {_video: Duration(minutes: 300)};
      await _resume(tester);
      await reveal(tester, _card);
      expect(_inCard('Budget reached'), findsOneWidget);
      expect(await snapshotOf(db, session.id), before);
      await _shutDown(tester);
    });

    testWidgets('share cards carry no Focus Guard information', (tester) async {
      await seed();
      await configureOn();
      platform.usage = const {_video: Duration(minutes: 75)};
      await launch(tester);
      await _tap(tester, find.byTooltip('Share progress'));
      expect(find.byType(ShareChoiceSheet), findsOneWidget);
      await _tap(tester, find.text("Today's Progress"));
      final preview = find.byType(SharePreviewScreen);
      expect(preview, findsOneWidget);
      for (final text in ['Focus Guard', 'FOCUS GUARD', 'Budget', _video]) {
        expect(
          find.descendant(of: preview, matching: find.textContaining(text)),
          findsNothing,
        );
      }
      await _shutDown(tester);
    });
  });

  group('reachable without an active Arc', () {
    testWidgets('on onboarding while it is on (the last Arc deleted): '
        'it can be turned off from inside NextRep', (tester) async {
      await seed(arc: false);
      await configureOn();
      await launch(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await _tap(tester, find.text('Focus Guard is on'));
      expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
      await _tap(tester, _switch);
      expect(
        (await DriftFocusGuardSettingsRepository(db).load()).enabled,
        isFalse,
      );
      expect(background.scheduled, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Focus Guard is on'), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('off on a first install: onboarding stays as it was', (
      tester,
    ) async {
      await seed(arc: false);
      await launch(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Focus Guard is on'), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('from Arc History, next to Data & Backup', (tester) async {
      await seed();
      await launch(tester);
      await _tap(tester, find.text('History'));
      await _tap(tester, find.byTooltip('Focus Guard'));
      expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('no entry on unsupported platforms', (tester) async {
      await seed();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_app(db, clock));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('History'));
      expect(find.byTooltip('Data & Backup'), findsOneWidget);
      expect(find.byTooltip('Focus Guard'), findsNothing);
      await _shutDown(tester);
    });
  });

  group('nudge taps', () {
    testWidgets('a tap while running opens Today', (tester) async {
      await seed();
      final taps = StreamController<String?>.broadcast();
      addTearDown(taps.close);
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _app(db, clock, platform: platform, taps: taps.stream),
      );
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await reveal(tester, _card);
      await _tap(tester, _card);
      expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
      taps.add(focusGuardTapPayload);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(FocusGuardSettingsScreen), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('a cold-start tap opens Today', (tester) async {
      await seed();
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _app(
          db,
          clock,
          platform: platform,
          launchPayload: focusGuardTapPayload,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('without an active Arc it opens the home screen', (
      tester,
    ) async {
      await seed(arc: false);
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _app(
          db,
          clock,
          platform: platform,
          launchPayload: focusGuardTapPayload,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(TodayScreen), findsNothing);
      await _shutDown(tester);
    });
  });

  testWidgets('a restored device keeps Focus Guard off and the check '
      'cancelled at launch', (tester) async {
    await seed();
    await configureOn();
    // What a restore stores: configuration, off, no nudge on record.
    await db.customStatement(
      'UPDATE focus_guard_preferences SET enabled = 0, last_nudged_on = NULL',
    );
    background.scheduled = true; // a job left from before the restore
    await launch(tester);
    expect(background.scheduled, isFalse);
    expect(platform.settingsOpened, 0);
    expect(scheduler.permissionRequests, 0);
    final stored = await DriftFocusGuardSettingsRepository(db).load();
    expect(stored.enabled, isFalse);
    expect(stored.lastNudgedOn, isNull);
    expect(stored.selectedPackages, [_video, _chat]);
    expect(LocalDate.fromDateTime(clock.now()), LocalDate(2026, 10, 1));
    await _shutDown(tester);
  });
}
