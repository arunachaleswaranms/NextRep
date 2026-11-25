import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app_info.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/data/platform_app_info.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/update/release_version.dart';
import 'package:nextrep/domain/update/update_checker.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fakes.dart';
import '../support/updates.dart';

/// Phase 12I: the v1.3.0 release identity (`1.3.0+4`), and how this build
/// behaves against GitHub while v1.2.0 is still the latest published
/// release, after v1.3.0 is published, and against a synthetic later
/// release. GitHub is always [FakeGitHubClient]; no test reaches the
/// network, and no release here is real.

const _release = ReleaseVersion(1, 3, 0);
const _published = ReleaseVersion(1, 2, 0);
const _check = 'Check for updates';
const _upToDate = "You're using the latest published version.";
const _newer = 'This build is newer than the latest published release.';

Widget _about({
  required FakeGitHubClient github,
  required FakeInstalledAppSource installed,
}) => ProviderScope(
  overrides: [
    ambientMotionProvider.overrideWithValue(false),
    installedAppSourceProvider.overrideWithValue(installed),
    externalLinksProvider.overrideWithValue(FakeExternalLinks()),
    releaseFeedProvider.overrideWithValue(
      GitHubReleaseFeed(client: () => github),
    ),
  ],
  retry: (_, _) => null,
  child: MaterialApp(theme: buildWinterTheme(), home: const AboutScreen()),
);

/// This build as Android reports it: pubspec.yaml's name and code.
FakeInstalledAppSource _thisBuild() {
  final (name, build) = pubspecVersion();
  return FakeInstalledAppSource(version: name, buildNumber: build);
}

Future<UpdateCheckResult> _checkAgainst(Map<String, Object?> latest) =>
    UpdateChecker(
      GitHubReleaseFeed(
        client: () =>
            FakeGitHubClient(() async => githubResponse(200, json: latest)),
      ),
    ).check(_release);

/// The source manifest's `<uses-permission>` names, split into those it
/// requests and those it removes from the libraries' manifests
/// (`tools:node="remove"`).
({Set<String> requested, Set<String> removed}) _manifestPermissions() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  final requested = <String>{};
  final removed = <String>{};
  for (final m in RegExp(r'<uses-permission\b([^>]*)>').allMatches(manifest)) {
    final attributes = m.group(1)!;
    final name = RegExp(r'android:name="([^"]+)"')
        .firstMatch(attributes)!
        .group(1)!;
    (attributes.contains('tools:node="remove"') ? removed : requested).add(
      name,
    );
  }
  return (requested: requested, removed: removed);
}

void main() {
  group('release identity', () {
    test('pubspec.yaml is 1.3.0+4: versionName 1.3.0, versionCode 4', () {
      expect(pubspecVersion(), ('1.3.0', '4'));
    });

    test('appVersion is 1.3.0', () {
      expect(appVersion, '1.3.0');
      expect(ReleaseVersion.tryParse(appVersion), _release);
    });

    test('Android takes versionName and versionCode from pubspec.yaml; the '
        'package id is unchanged and has no suffix', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));
      expect(gradle, contains('applicationId = "com.nextrep.nextrep"'));
      expect(gradle, contains('namespace = "com.nextrep.nextrep"'));
      expect(gradle, isNot(contains('applicationIdSuffix')));
      expect(gradle, isNot(contains('versionNameSuffix')));
    });

    test('schema v7; backups write format 4 and read 1, 2, 3 and 4; 32 '
        'achievements', () {
      final db = memoryDatabase();
      addTearDown(db.close);
      expect(db.schemaVersion, 7);
      expect(BackupFormat.formatVersion, 4);
      expect(BackupFormat.readableVersions, {1, 2, 3, 4});
      expect(AchievementCatalog.all, hasLength(32));
    });

    test('the source manifest is unchanged from v1.2.0: three requested, '
        'two removed', () {
      // The other four of the seven (VIBRATE, POST_NOTIFICATIONS, WAKE_LOCK
      // and the app-private receiver permission) come from the plugins'
      // manifests. The exact merged set is checked on the built APK by the
      // release script and CI.
      final permissions = _manifestPermissions();
      expect(permissions.requested, {
        'android.permission.INTERNET',
        'android.permission.RECEIVE_BOOT_COMPLETED',
        'android.permission.PACKAGE_USAGE_STATS',
      });
      expect(permissions.removed, {
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.ACCESS_NETWORK_STATE',
      });
    });

    test('v1.2.0 < v1.3.0, by version and by tag; numeric ordering', () {
      expect(_published < _release, isTrue);
      expect(ReleaseVersion.tryParseTag('v1.2.0')! < _release, isTrue);
      expect(ReleaseVersion.tryParseTag('v1.3.0'), _release);
      expect(_release.tag, 'v1.3.0');
      expect(const ReleaseVersion(1, 3, 1) > _release, isTrue);
      expect(const ReleaseVersion(1, 10, 0) > _release, isTrue);
      expect(const ReleaseVersion(1, 2, 9) < _release, isTrue);
    });
  });

  group('installed version comes from the platform', () {
    test('the v1.3.0 APK reports 1.3.0 (4)', () async {
      PackageInfo.setMockInitialValues(
        appName: 'NextRep',
        packageName: 'com.nextrep.nextrep',
        version: '1.3.0',
        buildNumber: '4',
        buildSignature: '',
      );
      final app = await const PlatformInstalledAppSource().read();
      expect((app.version, app.buildNumber), pubspecVersion());
      expect(app.releaseVersion, _release);
    });
  });

  group('v1.3.0 against GitHub', () {
    test('before publication (latest v1.2.0): this build is newer, never '
        'an update or up to date', () async {
      final result = await _checkAgainst(releaseJson(tag: 'v1.2.0'));
      expect(result, isA<NewerBuildInstalled>());
      final newer = result as NewerBuildInstalled;
      expect(newer.installed, _release);
      expect(newer.latest, _published);
    });

    test('a v1.2.0 draft or prerelease is still invalid', () async {
      for (final json in [
        releaseJson(tag: 'v1.2.0', draft: true),
        releaseJson(tag: 'v1.2.0', prerelease: true),
      ]) {
        expect(await _checkAgainst(json), isA<CheckInvalidRelease>());
      }
    });

    test('after publication (latest v1.3.0): up to date', () async {
      final result = await _checkAgainst(releaseJson(tag: 'v1.3.0'));
      expect(result, isA<UpToDate>());
      expect((result as UpToDate).latest, _release);
    });

    test('a synthetic future v1.3.1 / v1.4.0 / v1.10.0 with both official '
        'assets: available, pointing at its official page', () async {
      for (final tag in ['v1.3.1', 'v1.4.0', 'v1.10.0']) {
        final result = await _checkAgainst(releaseJson(tag: tag));
        expect(result, isA<UpdateAvailable>(), reason: tag);
        final available = result as UpdateAvailable;
        expect(available.installed, _release);
        expect(available.latest.tag, tag);
        expect(
          available.releasePage.toString(),
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/$tag',
        );
      }
    });

    test('a future v1.4.0 missing either asset: not ready', () async {
      for (final assets in [
        const <Object>[],
        [androidAssets('v1.4.0').first],
        [androidAssets('v1.4.0').last],
        androidAssets('v1.4.0', apkState: 'starter'),
        androidAssets('v1.4.0', checksumState: 'starter'),
        androidAssets('v1.3.0'), // another release's files
      ]) {
        expect(
          await _checkAgainst(releaseJson(tag: 'v1.4.0', assets: assets)),
          isA<ReleaseNotReady>(),
        );
      }
    });

    test('drafts, prereleases and malformed future releases are rejected, '
        'never up to date or available', () async {
      for (final json in [
        releaseJson(tag: 'v1.3.0', draft: true),
        releaseJson(tag: 'v1.3.0', prerelease: true),
        releaseJson(tag: 'v1.4.0', draft: true),
        releaseJson(tag: 'v1.4.0', prerelease: true),
        releaseJson(tag: 'v1.4.0-rc1'),
        releaseJson(tag: '1.4.0'),
        releaseJson(tag: 'v1.4.0', prerelease: 'false'),
        releaseJson(htmlUrl: 'https://evil.example/releases/tag/v1.4.0'),
      ]) {
        expect(await _checkAgainst(json), isA<CheckInvalidRelease>());
      }
    });
  });

  group('About on this build', () {
    Future<void> setPhone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> shutDown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    Future<void> tapCheck(WidgetTester tester) async {
      final button = find.ancestor(
        of: find.text(_check),
        matching: find.bySubtype<ButtonStyleButton>(),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('before publication: Version 1.3.0 / Build 4, no request '
        'until the tap, then exactly one, "newer than published v1.2.0"', (
      tester,
    ) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.2.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      expect(find.text('Version 1.3.0'), findsOneWidget);
      expect(find.text('Build 4'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(github.requests, isEmpty);

      await tapCheck(tester);
      expect(github.requests, hasLength(1));
      expect(find.text(_newer), findsOneWidget);
      expect(
        find.text('Installed: v1.3.0 · Latest published: v1.2.0'),
        findsOneWidget,
      );
      expect(find.text(_upToDate), findsNothing);
      expect(find.textContaining('is available'), findsNothing);
      await tester.pump(const Duration(minutes: 5));
      expect(github.requests, hasLength(1));
      await shutDown(tester);
    });

    testWidgets('after publication: "latest published v1.3.0"', (tester) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.3.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      await tapCheck(tester);
      expect(github.requests, hasLength(1));
      expect(find.text(_upToDate), findsOneWidget);
      expect(find.text('Latest published: v1.3.0'), findsOneWidget);
      await shutDown(tester);
    });

    testWidgets('a synthetic future v1.4.0: available', (tester) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.4.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      await tapCheck(tester);
      expect(find.text('NextRep v1.4.0 is available.'), findsOneWidget);
      expect(
        find.text('Installed: v1.3.0 · Available: v1.4.0'),
        findsOneWidget,
      );
      await shutDown(tester);
    });
  });

  group('backups from this build', () {
    test('record appVersion 1.3.0 in format 4; inspect, restore on a fresh '
        'install and re-export the same data', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 11, 25, 9));
      final app = TestApp(db, clock);
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      // Wired as in dependencies.dart, with the real appVersion.
      final backup = BackupService(
        store: app.backupStore,
        scheduler: app.scheduler,
        clock: clock,
        appVersion: appVersion,
      );
      final export = await backup.export();
      final root = jsonDecode(utf8.decode(export.bytes)) as Map;
      expect(root['appVersion'], '1.3.0');
      expect(root['formatVersion'], 4);
      expect(root['product'], 'NextRep');
      final document = BackupCodec.decode(export.bytes);
      expect(document.appVersion, '1.3.0');
      expect(BackupValidator.validate(document).summary.arcCount, 1);

      final target = memoryDatabase();
      addTearDown(target.close);
      final fresh = TestApp(target, clock);
      final restoreInto = BackupService(
        store: fresh.backupStore,
        scheduler: fresh.scheduler,
        clock: clock,
        appVersion: appVersion,
      );
      await restoreInto.restore(await restoreInto.inspect(export.bytes));
      final again =
          jsonDecode(utf8.decode((await restoreInto.export()).bytes)) as Map;
      expect(again['formatVersion'], 4);
      expect(jsonEncode(again['data']), jsonEncode(root['data']));
    });
  });
}
