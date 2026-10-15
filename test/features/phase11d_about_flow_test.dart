import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/app_info.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/features/about/about_controller.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';
import '../support/updates.dart';

/// Phase 11D: About and the manual update check, over the real controller,
/// checker and HTTP feed, with GitHub replaced by [FakeGitHubClient], which
/// counts every request. No test reaches the network.

const _upToDate = "You're using the latest published version.";
const _available = 'NextRep v1.2.0 is available.';
const _viewRelease = 'View official release';
const _check = 'Check for updates';
const _idle = 'Only checks GitHub when you tap.';

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).enabled;

/// Scrolls About until [finder] is built and visible.
Future<void> _seek(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .descendant(
          of: find.byType(AboutScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
);

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// About alone, for its states. [github] null: update checks not offered
/// (iOS).
Widget _aboutOnly({
  FakeGitHubClient? github,
  FakeInstalledAppSource? installed,
  FakeExternalLinks? links,
}) => ProviderScope(
  overrides: [
    ambientMotionProvider.overrideWithValue(false),
    installedAppSourceProvider.overrideWithValue(
      installed ?? FakeInstalledAppSource(),
    ),
    externalLinksProvider.overrideWithValue(links ?? FakeExternalLinks()),
    if (github != null)
      releaseFeedProvider.overrideWithValue(
        GitHubReleaseFeed(client: () => github),
      ),
  ],
  retry: (_, _) => null,
  child: MaterialApp(theme: buildWinterTheme(), home: const AboutScreen()),
);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TestApp app;
  late FakeGitHubClient github;
  late FakeInstalledAppSource installed;
  late FakeExternalLinks links;
  late FakeReminderScheduler scheduler;
  late FakeFocusGuardPlatform platform;
  late FakeFocusGuardBackgroundScheduler background;
  late FakeBackupFiles files;

  /// A fresh device on Thu 1 Oct 2026, 18:00; GitHub's latest is v1.2.0.
  void seed() {
    db = memoryDatabase();
    addTearDown(db.close);
    clock = FakeClock(DateTime(2026, 10, 1, 18));
    scheduler = FakeReminderScheduler(granted: true);
    app = TestApp(db, clock, scheduler: scheduler);
    github = FakeGitHubClient();
    installed = FakeInstalledAppSource();
    links = FakeExternalLinks();
    platform = FakeFocusGuardPlatform(
      apps: const [
        LaunchableAppCandidate(
          packageName: 'org.example.video',
          label: 'Video',
        ),
      ],
    );
    background = FakeFocusGuardBackgroundScheduler();
    files = FakeBackupFiles();
  }

  /// The whole app, as on Android: a GitHub feed is provided.
  Widget appWidget({bool android = true}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(clock),
      ambientMotionProvider.overrideWithValue(false),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      focusGuardPlatformProvider.overrideWithValue(platform),
      focusGuardSchedulerProvider.overrideWithValue(background),
      backupFilesProvider.overrideWithValue(files),
      installedAppSourceProvider.overrideWithValue(installed),
      externalLinksProvider.overrideWithValue(links),
      if (android)
        releaseFeedProvider.overrideWithValue(
          GitHubReleaseFeed(client: () => github),
        ),
    ],
    retry: (_, _) => null,
    child: const NextRepApp(),
  );

  Future<void> launch(WidgetTester tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
  }

  Future<void> startArc() async {
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  }

  Future<void> openAboutFromHistoryTab(WidgetTester tester) async {
    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('About NextRep'));
    expect(find.byType(AboutScreen), findsOneWidget);
  }

  group('manual-only networking', () {
    test('constructing dependencies and the About controller sends '
        'nothing', () async {
      final github = FakeGitHubClient();
      final container = ProviderContainer(
        overrides: [
          installedAppSourceProvider.overrideWithValue(
            FakeInstalledAppSource(),
          ),
          releaseFeedProvider.overrideWithValue(
            GitHubReleaseFeed(client: () => github),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(releaseFeedProvider);
      container.read(externalLinksProvider);
      await container.read(installedAppProvider.future);
      expect(
        container.read(updateCheckControllerProvider),
        isA<UpdateCheckIdle>(),
      );
      expect(github.requests, isEmpty);

      // Without a feed (iOS, and every test that doesn't supply one), a
      // check can't send anything at all.
      final ios = ProviderContainer(
        overrides: [
          installedAppSourceProvider.overrideWithValue(
            FakeInstalledAppSource(),
          ),
        ],
      );
      addTearDown(ios.dispose);
      expect(ios.read(releaseFeedProvider), isNull);
      final sub = ios.listen(updateCheckControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await ios.read(updateCheckControllerProvider.notifier).check();
      expect(ios.read(updateCheckControllerProvider), isA<UpdateCheckIdle>());
    });

    testWidgets('launch, Today, resume, a new day, Focus Guard, Hydration '
        'Coach and a restore send nothing', (tester) async {
      seed();
      await startArc();
      await launch(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(github.requests, isEmpty, reason: 'launch and Today');

      await _resume(tester);
      expect(github.requests, isEmpty, reason: 'resume');

      // Local midnight passes with the app open, then a resume a day later.
      clock.current = DateTime(2026, 10, 2, 0, 1);
      await tester.pump(const Duration(hours: 7));
      await tester.pumpAndSettle();
      clock.current = DateTime(2026, 10, 3, 9);
      await _resume(tester);
      expect(github.requests, isEmpty, reason: 'date changes');

      // Focus Guard on: its reconciliation schedules the background check.
      platform.access = UsageAccess.granted;
      await DriftFocusGuardSettingsRepository(db).save(
        const FocusGuardSettings(
          enabled: true,
          dailyBudgetMinutes: 30,
          selectedPackages: ['org.example.video'],
        ),
        at: clock.now(),
      );
      await _resume(tester);
      expect(background.scheduled, isTrue);
      expect(github.requests, isEmpty, reason: 'Focus Guard');

      // Hydration Coach on: reconciliation plans its nudges.
      await app.reminders.update((p) => p.copyWith(hydrationEnabled: true));
      await _resume(tester);
      expect(
        scheduler.pending.where((r) => r.kind == ReminderKind.hydration),
        isNotEmpty,
      );
      expect(github.requests, isEmpty, reason: 'Hydration Coach');

      // A full restore, which restarts the app on the restored data.
      files.toPick = (await app.backup.export()).bytes;
      await _openTab(tester, 'History');
      await _tap(tester, find.byTooltip('Data & Backup'));
      await _tap(tester, find.text('Restore Backup'));
      await _tap(tester, _button('Restore'));
      await _tap(tester, _button('Replace Data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Backup restored.'), findsOneWidget);
      expect(github.requests, isEmpty, reason: 'restore');

      // And the check still works, once, when asked for.
      await openAboutFromHistoryTab(tester);
      await _tap(tester, _button(_check));
      expect(github.requests, hasLength(1));
      await _shutDown(tester);
    });

    testWidgets('opening, rebuilding, leaving and reopening About sends '
        'nothing; each tap sends exactly one request', (tester) async {
      seed();
      await startArc();
      await launch(tester);

      await openAboutFromHistoryTab(tester);
      expect(find.text(_idle), findsOneWidget);
      expect(github.requests, isEmpty, reason: 'opening About');

      // Rebuilds: a resize, larger text, a resume.
      tester.view.physicalSize = const Size(1440, 2560);
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await tester.pumpAndSettle();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await _resume(tester);
      expect(github.requests, isEmpty, reason: 'rebuilding About');

      await _back(tester);
      expect(find.byType(AboutScreen), findsNothing);
      expect(github.requests, isEmpty, reason: 'leaving without checking');
      await _tap(tester, find.byTooltip('About NextRep'));
      expect(find.text(_idle), findsOneWidget);
      expect(github.requests, isEmpty, reason: 'reopening About');

      // The tap: one request, held in flight.
      final pending = github.hold();
      await tester.ensureVisible(_button(_check));
      await tester.pumpAndSettle();
      await tester.tap(_button(_check));
      await tester.pump();
      expect(github.requests, hasLength(1));
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_enabled(tester, 'Checking…'), isFalse);

      // Rebuilds and repeated taps while it runs add nothing.
      await tester.tap(_button('Checking…'), warnIfMissed: false);
      await tester.pump();
      tester.view.physicalSize = const Size(1080, 2400);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AboutScreen)),
      );
      await container.read(updateCheckControllerProvider.notifier).check();
      await tester.pump();
      expect(github.requests, hasLength(1));

      pending.complete(githubResponse(200, json: releaseJson(tag: 'v1.2.0')));
      await tester.pumpAndSettle();
      expect(find.text(_available), findsOneWidget);
      expect(github.requests, hasLength(1));
      expect(links.opened, isEmpty, reason: 'never opened by itself');

      // Viewing the release opens the browser and asks GitHub nothing.
      await _tap(tester, _button(_viewRelease));
      expect(links.opened, [
        Uri.parse(
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
      ]);
      expect(github.requests, hasLength(1));

      // Checking again is another explicit tap: one more request.
      github.respond = () async =>
          githubResponse(200, json: releaseJson(tag: 'v1.2.0'));
      await _tap(tester, _button(_check));
      expect(github.requests, hasLength(2));

      // Every request was the same anonymous metadata GET.
      for (final request in github.requests) {
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse(
            'https://api.github.com/repos/arunachaleswaranms/NextRep/releases/latest',
          ),
        );
        expect((request as http.Request).body, isEmpty);
        expect(request.headers.keys.map((k) => k.toLowerCase()).toSet(), {
          'accept',
          'x-github-api-version',
          'user-agent',
        });
      }
      await _shutDown(tester);
    });

    testWidgets('leaving About while a check runs: no error, the answer is '
        'dropped, and reopening does not check again', (tester) async {
      seed();
      await startArc();
      await launch(tester);
      await openAboutFromHistoryTab(tester);

      final pending = github.hold();
      await tester.ensureVisible(_button(_check));
      await tester.pumpAndSettle();
      await tester.tap(_button(_check));
      await tester.pump();
      expect(github.requests, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsNothing);

      pending.complete(githubResponse(200, json: releaseJson(tag: 'v1.2.0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _tap(tester, find.byTooltip('About NextRep'));
      expect(find.text(_idle), findsOneWidget);
      expect(find.text(_available), findsNothing);
      expect(github.requests, hasLength(1));
      await _shutDown(tester);
    });

    testWidgets('leaving and reopening About while a check runs, then '
        'tapping again, joins the running request', (tester) async {
      seed();
      await startArc();
      await launch(tester);
      await openAboutFromHistoryTab(tester);

      final pending = github.hold();
      await tester.ensureVisible(_button(_check));
      await tester.pumpAndSettle();
      await tester.tap(_button(_check));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('About NextRep'));
      expect(find.text(_idle), findsOneWidget);
      await tester.ensureVisible(_button(_check));
      await tester.pumpAndSettle();
      await tester.tap(_button(_check));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      expect(github.requests, hasLength(1));

      pending.complete(githubResponse(200, json: releaseJson(tag: 'v1.2.0')));
      await tester.pumpAndSettle();
      expect(find.text(_available), findsOneWidget);
      expect(github.requests, hasLength(1));
      expect(github.closes, 1);
      await _shutDown(tester);
    });

    testWidgets('a check that never answers ends after the timeout', (
      tester,
    ) async {
      final github = FakeGitHubClient()..hold();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: github));
      await tester.pumpAndSettle();
      await _seek(tester, _button(_check));
      await tester.tap(_button(_check));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Checking…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't check for updates."), findsOneWidget);
      expect(find.text(_upToDate), findsNothing);
      expect(github.closes, 1);
      expect(_enabled(tester, _check), isTrue);
      expect(github.requests, hasLength(1)); // never retried by itself
      await _shutDown(tester);
    });
  });

  group('About screen', () {
    testWidgets('shows the installed version and build from the platform, '
        'not a constant', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _aboutOnly(
          github: FakeGitHubClient(),
          installed: FakeInstalledAppSource(version: '1.4.2', buildNumber: '9'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ABOUT NEXTREP'), findsOneWidget);
      expect(find.text('NEXTREP'), findsOneWidget);
      expect(find.text('Every rep counts.'), findsOneWidget);
      expect(
        find.text(
          'Your Winter Arc companion for building better habits, one day '
          'at a time.',
        ),
        findsOneWidget,
      );
      expect(find.text('Version 1.4.2'), findsOneWidget);
      expect(find.text('Build 9'), findsOneWidget);
      expect(find.text('Version $appVersion'), findsNothing);
      expect(find.text(_check), findsOneWidget);
      expect(find.text(_idle), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('this build: Version 1.1.0, Build 2', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: FakeGitHubClient()));
      await tester.pumpAndSettle();
      expect(find.text('Version 1.1.0'), findsOneWidget);
      expect(find.text('Build 2'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('unreadable package metadata: said so, and no check is '
        'possible', (tester) async {
      final github = FakeGitHubClient();
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _aboutOnly(
          github: github,
          installed: FakeInstalledAppSource()..fail = true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version information is unavailable.'), findsOneWidget);
      expect(find.textContaining('Version 1.1.0'), findsNothing);
      expect(_enabled(tester, _check), isFalse);
      await tester.tap(_button(_check), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    group('every result has its own words', () {
      for (final (label, respond, version, title, detail) in [
        (
          'up to date (v1.1.0 is the latest)',
          () async => githubResponse(200, json: releaseJson(tag: 'v1.1.0')),
          '1.1.0',
          _upToDate,
          'Latest published: v1.1.0',
        ),
        (
          'update available',
          () async => githubResponse(200, json: releaseJson(tag: 'v1.2.0')),
          '1.1.0',
          _available,
          'Installed: v1.1.0 · Available: v1.2.0',
        ),
        (
          'release not ready',
          () async => githubResponse(
            200,
            json: releaseJson(tag: 'v1.2.0', assets: const []),
          ),
          '1.1.0',
          'A newer release is listed, but its Android download is not '
              'ready yet.',
          'Listed: v1.2.0 · Installed: v1.1.0. Please check again later.',
        ),
        (
          'newer build installed',
          () async => githubResponse(200, json: releaseJson(tag: 'v1.1.0')),
          '1.2.0',
          'This build is newer than the latest published release.',
          'Installed: v1.2.0 · Latest published: v1.1.0',
        ),
        (
          'no published release (404)',
          () async => githubResponse(404, json: {'message': 'Not Found'}),
          '1.1.0',
          'GitHub did not return a published NextRep release.',
          'Please try again later.',
        ),
        (
          'offline',
          () async => throw const SocketException('Failed host lookup'),
          '1.1.0',
          "Couldn't check for updates.",
          'Check your connection and try again.',
        ),
        (
          'TLS failure',
          () async => throw const HandshakeException('CERTIFICATE_VERIFY'),
          '1.1.0',
          "Couldn't check for updates.",
          'Check your connection and try again.',
        ),
        (
          'rate limited (429)',
          () async => githubResponse(429, json: {'message': 'Too many'}),
          '1.1.0',
          'GitHub is temporarily limiting update checks.',
          'Please try again later.',
        ),
        (
          'rate limited (403, no requests left)',
          () async => githubResponse(
            403,
            json: {'message': 'API rate limit exceeded'},
            headers: {'x-ratelimit-remaining': '0'},
          ),
          '1.1.0',
          'GitHub is temporarily limiting update checks.',
          'Please try again later.',
        ),
        (
          'GitHub error (503)',
          () async => githubResponse(503, body: 'Unavailable'),
          '1.1.0',
          "GitHub couldn't answer the update check.",
          'Please try again later.',
        ),
        (
          'HTML instead of JSON',
          () async => githubResponse(
            200,
            body: '<html><body>Portal login</body></html>',
            contentType: 'text/html',
          ),
          '1.1.0',
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
        (
          'a draft (even of the installed version)',
          () async => githubResponse(
            200,
            json: releaseJson(tag: 'v1.1.0', draft: true),
          ),
          '1.1.0',
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
        (
          'a page URL on another host',
          () async => githubResponse(
            200,
            json: releaseJson(htmlUrl: 'https://evil.example/v1.2.0'),
          ),
          '1.1.0',
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
        (
          'a redirect',
          () async => githubResponse(
            302,
            headers: {'location': 'https://evil.example/latest'},
          ),
          '1.1.0',
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
        (
          'an oversized answer',
          () async => http.StreamedResponse(
            Stream.value(List.filled(16, 0x20)),
            200,
            contentLength: 10 * 1024 * 1024,
            headers: {'content-type': 'application/json'},
          ),
          '1.1.0',
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
      ]) {
        testWidgets(label, (tester) async {
          final github = FakeGitHubClient(respond);
          final links = FakeExternalLinks();
          await _setPhoneSize(tester);
          await tester.pumpWidget(
            _aboutOnly(
              github: github,
              installed: FakeInstalledAppSource(version: version),
              links: links,
            ),
          );
          await tester.pumpAndSettle();
          await _tap(tester, _button(_check));
          expect(find.text(title), findsOneWidget);
          expect(find.text(detail), findsOneWidget);
          expect(github.requests, hasLength(1));
          if (title != _upToDate) expect(find.text(_upToDate), findsNothing);
          expect(
            find.text(_viewRelease),
            title == _available ? findsOneWidget : findsNothing,
          );
          expect(links.opened, isEmpty);
          expect(_enabled(tester, _check), isTrue);
          // No raw exception text reaches the screen.
          expect(find.textContaining('Exception'), findsNothing);
          expect(find.textContaining('evil.example'), findsNothing);
          await _shutDown(tester);
        });
      }
    });

    testWidgets('scrolling the Updates card away and back keeps a running '
        'check and its result', (tester) async {
      final github = FakeGitHubClient();
      final pending = github.hold();
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_aboutOnly(github: github));
      await tester.pumpAndSettle();
      await _seek(tester, _button(_check));
      await tester.tap(_button(_check));
      await tester.pump();

      // To the bottom (the card is no longer built), the answer arrives,
      // then back up.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -6000));
      await tester.pump();
      expect(find.text('Checking…'), findsNothing);
      pending.complete(githubResponse(200, json: releaseJson(tag: 'v1.2.0')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await _seek(tester, find.text(_available));
      expect(github.requests, hasLength(1));
      await _shutDown(tester);
    });

    testWidgets('after an error, an explicit tap tries again', (tester) async {
      final github = FakeGitHubClient(
        () async => throw const SocketException('offline'),
      );
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: github));
      await tester.pumpAndSettle();
      await _tap(tester, _button(_check));
      expect(find.text("Couldn't check for updates."), findsOneWidget);
      expect(github.requests, hasLength(1));

      await tester.pump(const Duration(minutes: 5));
      expect(github.requests, hasLength(1), reason: 'no automatic retry');

      github.respond = () async =>
          githubResponse(200, json: releaseJson(tag: 'v1.2.0'));
      await _tap(tester, _button(_check));
      expect(find.text(_available), findsOneWidget);
      expect(github.requests, hasLength(2));
      await _shutDown(tester);
    });

    testWidgets('View official release opens the canonical page, built from '
        'the validated tag, only on tap', (tester) async {
      final github = FakeGitHubClient(
        () async => githubResponse(
          200,
          json: releaseJson(
            htmlUrl: 'https://github.com/ARUNACHALESWARANMS/NEXTREP/releases/tag/v1.2.0',
          ),
        ),
      );
      final links = FakeExternalLinks();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: github, links: links));
      await tester.pumpAndSettle();
      await _tap(tester, _button(_check));
      expect(links.opened, isEmpty);
      await _tap(tester, _button(_viewRelease));
      expect(links.opened, [
        Uri.parse(
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
      ]);
      expect(github.requests, hasLength(1));
      await _shutDown(tester);
    });

    testWidgets('Open on GitHub opens the official repository', (tester) async {
      final github = FakeGitHubClient();
      final links = FakeExternalLinks();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: github, links: links));
      await tester.pumpAndSettle();
      expect(links.opened, isEmpty);
      await _seek(tester, _button('Open on GitHub'));
      await _tap(tester, _button('Open on GitHub'));
      expect(links.opened, [
        Uri.parse('https://github.com/arunachaleswaranms/NextRep'),
      ]);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('open-source licenses open in the app, offline', (
      tester,
    ) async {
      final github = FakeGitHubClient();
      final links = FakeExternalLinks();
      await _setPhoneSize(tester);
      await tester.pumpWidget(_aboutOnly(github: github, links: links));
      await tester.pumpAndSettle();
      await _seek(tester, _button('Open-source licenses'));
      await _tap(tester, _button('Open-source licenses'));
      expect(find.byType(LicensePage), findsOneWidget);
      expect(github.requests, isEmpty);
      expect(links.opened, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('no browser: a calm message with the address, nothing '
        'breaks', (tester) async {
      final links = FakeExternalLinks(opens: false);
      await _setPhoneSize(tester);
      await tester.pumpWidget(
        _aboutOnly(github: FakeGitHubClient(), links: links),
      );
      await tester.pumpAndSettle();
      await _tap(tester, _button(_check));
      await _tap(tester, _button(_viewRelease));
      expect(
        find.text(
          "Couldn't open a browser. Visit "
          'github.com/arunachaleswaranms/NextRep/releases in your browser.',
        ),
        findsOneWidget,
      );
      expect(find.text(_available), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });

    testWidgets('iOS: version and information, no update check, Android-only '
        'explained', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _setPhoneSize(tester);
        await tester.pumpWidget(_aboutOnly()); // no feed, as in main.dart
        await tester.pumpAndSettle();
        expect(find.text('Version 1.1.0'), findsOneWidget);
        expect(find.text('Build 2'), findsOneWidget);
        expect(find.text(_check), findsNothing);
        expect(find.textContaining('APK'), findsNothing);
        expect(
          find.text(
            'NextRep releases are published for Android only, so this '
            "device doesn't check for updates.",
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Only when you tap'), findsNothing);
        await _seek(tester, find.text('OFFICIAL SOURCE'));
        expect(tester.takeException(), isNull);
        await _shutDown(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a small phone at 2x text: everything reachable, no '
        'overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _aboutOnly(
          github: FakeGitHubClient(
            () async => githubResponse(
              200,
              json: releaseJson(tag: 'v1.2.0', assets: const []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _seek(tester, _button(_check));
      await _tap(tester, _button(_check));
      // From the top, in reading order.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await _seek(tester, find.text('UPDATES'));
      await _seek(tester, find.textContaining('A newer release is listed'));
      for (final text in [
        "Don't uninstall NextRep to update.",
        'PRIVACY',
        'OFFICIAL SOURCE',
        'Open on GitHub',
      ]) {
        await _seek(tester, find.text(text));
      }
      expect(tester.takeException(), isNull);
      await _shutDown(tester);
    });

    testWidgets('accessibility: labelled, 48dp tap targets, a heading, and '
        'the result is announced', (tester) async {
      final handle = tester.ensureSemantics();
      seed();
      await launch(tester); // first install: onboarding
      await _tap(tester, _button('About NextRep'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(
        find.bySemanticsLabel(RegExp(r'Version 1\.1\.0\s+Build 2')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('ABOUT NEXTREP')),
        matchesSemantics(isHeader: true, label: 'ABOUT NEXTREP'),
      );

      await _tap(tester, _button(_check));
      final status = find.ancestor(
        of: find.text(_available),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      );
      expect(status, findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
      await _shutDown(tester);
    });
  });

  group('entry points (Android and iOS alike; opening About changes '
      'nothing)', () {
    testWidgets('an active Arc: History tab → About → back', (tester) async {
      seed();
      await startArc();
      final arc = (await app.sessions.currentSession())!;
      final before = await snapshotOf(db, arc.id);
      await launch(tester);
      await openAboutFromHistoryTab(tester);
      expect(find.text('Version 1.1.0'), findsOneWidget);
      await _back(tester);
      expect(find.byType(ArcHistoryScreen), findsOneWidget);
      // Focus Guard and Data & Backup are still there beside it.
      expect(find.byTooltip('Focus Guard'), findsOneWidget);
      expect(find.byTooltip('Data & Backup'), findsOneWidget);
      expect(await snapshotOf(db, arc.id), before);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('a completed Arc (home): About from the summary and from '
        'Arc History', (tester) async {
      seed();
      final done = await runFirstArc(app);
      final before = await snapshotOf(db, done.id);
      await launch(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);

      await tester.scrollUntilVisible(
        _button('About NextRep'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, _button('About NextRep'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);

      await tester.scrollUntilVisible(
        _button('Arc History'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, _button('Arc History'));
      expect(find.byType(ArcHistoryScreen), findsOneWidget);
      await _tap(tester, find.byTooltip('About NextRep'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(ArcHistoryScreen), findsOneWidget);
      expect(find.byTooltip('Data & Backup'), findsOneWidget);
      expect(await snapshotOf(db, done.id), before);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('first install: About from onboarding, nothing stored', (
      tester,
    ) async {
      seed();
      await launch(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await _tap(tester, _button('About NextRep'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(await db.select(db.winterArcSessions).get(), isEmpty);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('setup: About and back keeps the setup as it was', (
      tester,
    ) async {
      seed();
      final setup = await app.winterArc.beginSetup();
      final before = await snapshotOf(db, setup.id);
      await launch(tester);
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        _button('About NextRep'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await _tap(tester, _button('About NextRep'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(find.text('Cancel setup'), findsOneWidget);
      expect(await snapshotOf(db, setup.id), before);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('Back up your data opens Data & Backup from About', (
      tester,
    ) async {
      seed();
      await launch(tester);
      await _tap(tester, _button('About NextRep'));
      await _seek(tester, _button('Back up your data'));
      await _tap(tester, _button('Back up your data'));
      expect(find.byType(DataBackupScreen), findsOneWidget);
      await _back(tester);
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(github.requests, isEmpty);
      await _shutDown(tester);
    });

    testWidgets('without a feed (iOS) the app is unchanged and About still '
        'opens', (tester) async {
      seed();
      await startArc();
      await _setPhoneSize(tester);
      await tester.pumpWidget(appWidget(android: false));
      await tester.pumpAndSettle();
      await openAboutFromHistoryTab(tester);
      expect(find.text(_check), findsNothing);
      expect(find.text('Version 1.1.0'), findsOneWidget);
      await _shutDown(tester);
    });
  });
}
