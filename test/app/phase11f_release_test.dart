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
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/update/github_release.dart';
import 'package:nextrep/domain/update/release_version.dart';
import 'package:nextrep/domain/update/update_checker.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fakes.dart';
import '../support/updates.dart';

/// Phase 11F: the v1.2.0 release identity, and how this build behaves
/// against GitHub before and after v1.2.0 is published. GitHub is always
/// [FakeGitHubClient]; no test reaches the network, and no release here is
/// real.

const _release = ReleaseVersion(1, 2, 0);
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

void main() {
  group('release identity', () {
    test('pubspec.yaml is 1.2.0+3: versionName 1.2.0, versionCode 3', () {
      expect(pubspecVersion(), ('1.2.0', '3'));
    });

    test('appVersion is 1.2.0', () {
      expect(appVersion, '1.2.0');
      expect(ReleaseVersion.tryParse(appVersion), _release);
    });

    test('Android takes versionName and versionCode from pubspec.yaml', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('versionCode = flutter.versionCode'));
      expect(gradle, contains('versionName = flutter.versionName'));
      expect(gradle, contains('applicationId = "com.nextrep.nextrep"'));
      expect(gradle, isNot(contains('applicationIdSuffix')));
    });

    test('schema stays v6; backups write format 3 and read 1, 2 and 3', () {
      final db = memoryDatabase();
      addTearDown(db.close);
      expect(db.schemaVersion, 6);
      expect(BackupFormat.formatVersion, 3);
      expect(BackupFormat.readableVersions, {1, 2, 3});
    });

    test('v1.1.0 is older than v1.2.0', () {
      expect(const ReleaseVersion(1, 1, 0) < _release, isTrue);
      expect(ReleaseVersion.tryParseTag('v1.1.0')! < _release, isTrue);
    });
  });

  group('installed version comes from the platform', () {
    test('package metadata, not the appVersion constant', () async {
      // A value that differs from appVersion, so a constant can't pass.
      PackageInfo.setMockInitialValues(
        appName: 'NextRep',
        packageName: 'com.nextrep.nextrep',
        version: '9.8.7',
        buildNumber: '42',
        buildSignature: '',
      );
      final app = await const PlatformInstalledAppSource().read();
      expect(app.version, '9.8.7');
      expect(app.buildNumber, '42');
      expect(app.releaseVersion, const ReleaseVersion(9, 8, 7));
    });

    test('the v1.2.0 APK reports 1.2.0 (3)', () async {
      PackageInfo.setMockInitialValues(
        appName: 'NextRep',
        packageName: 'com.nextrep.nextrep',
        version: '1.2.0',
        buildNumber: '3',
        buildSignature: '',
      );
      final app = await const PlatformInstalledAppSource().read();
      expect((app.version, app.buildNumber), pubspecVersion());
      expect(app.releaseVersion, _release);
    });
  });

  group('v1.2.0 against GitHub', () {
    test('before publication (latest v1.1.0): this build is newer', () async {
      final result = await _checkAgainst(releaseJson(tag: 'v1.1.0'));
      expect(result, isA<NewerBuildInstalled>());
      final newer = result as NewerBuildInstalled;
      expect(newer.installed, _release);
      expect(newer.latest, const ReleaseVersion(1, 1, 0));
    });

    test('after publication (latest v1.2.0): up to date', () async {
      final result = await _checkAgainst(releaseJson(tag: 'v1.2.0'));
      expect(result, isA<UpToDate>());
      expect((result as UpToDate).latest, _release);
    });

    test('a future v1.3.0 with both official assets: available, pointing '
        'at its official page', () async {
      final result = await _checkAgainst(releaseJson(tag: 'v1.3.0'));
      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.installed, _release);
      expect(available.latest, const ReleaseVersion(1, 3, 0));
      expect(
        available.releasePage.toString(),
        'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.3.0',
      );
    });

    test('a future v1.3.0 missing either asset: not ready', () async {
      for (final assets in [
        const <Object>[],
        [androidAssets('v1.3.0').first],
        [androidAssets('v1.3.0').last],
        androidAssets('v1.3.0', checksumState: 'starter'),
        androidAssets('v1.2.0'), // another release's files
      ]) {
        expect(
          await _checkAgainst(releaseJson(tag: 'v1.3.0', assets: assets)),
          isA<ReleaseNotReady>(),
        );
      }
    });

    test('drafts, prereleases and invalid metadata are rejected, never '
        'up to date or available', () async {
      for (final json in [
        releaseJson(tag: 'v1.2.0', draft: true),
        releaseJson(tag: 'v1.2.0', prerelease: true),
        releaseJson(tag: 'v1.3.0', draft: true),
        releaseJson(tag: 'v1.3.0', prerelease: true),
        releaseJson(tag: 'v1.3.0-rc1'),
        releaseJson(tag: '1.3.0'),
        releaseJson(tag: 'v1.3.0', draft: 'false'),
        releaseJson(omit: {'tag_name'}),
        releaseJson(omit: {'draft'}),
        releaseJson(omit: {'assets'}),
        releaseJson(htmlUrl: 'https://evil.example/releases/tag/v1.3.0'),
      ]) {
        expect(await _checkAgainst(json), isA<CheckInvalidRelease>());
      }
      expect(
        () => PublishedRelease.parse(jsonEncode(releaseJson(draft: true))),
        throwsA(isA<InvalidReleaseMetadata>()),
      );
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

    testWidgets('before publication: Version 1.2.0 / Build 3, no request '
        'until the tap, then exactly one, "newer than published v1.1.0"', (
      tester,
    ) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.1.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      expect(find.text('Version 1.2.0'), findsOneWidget);
      expect(find.text('Build 3'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(github.requests, isEmpty);

      await tapCheck(tester);
      expect(github.requests, hasLength(1));
      expect(find.text(_newer), findsOneWidget);
      expect(
        find.text('Installed: v1.2.0 · Latest published: v1.1.0'),
        findsOneWidget,
      );
      expect(find.text(_upToDate), findsNothing);
      await tester.pump(const Duration(minutes: 5));
      expect(github.requests, hasLength(1));
      await shutDown(tester);
    });

    testWidgets('after publication: "latest published v1.2.0"', (tester) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.2.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      await tapCheck(tester);
      expect(github.requests, hasLength(1));
      expect(find.text(_upToDate), findsOneWidget);
      expect(find.text('Latest published: v1.2.0'), findsOneWidget);
      await shutDown(tester);
    });

    testWidgets('a future v1.3.0: available', (tester) async {
      final github = FakeGitHubClient(
        () async => githubResponse(200, json: releaseJson(tag: 'v1.3.0')),
      );
      await setPhone(tester);
      await tester.pumpWidget(_about(github: github, installed: _thisBuild()));
      await tester.pumpAndSettle();
      await tapCheck(tester);
      expect(find.text('NextRep v1.3.0 is available.'), findsOneWidget);
      expect(
        find.text('Installed: v1.2.0 · Available: v1.3.0'),
        findsOneWidget,
      );
      await shutDown(tester);
    });
  });

  group('backups from this build', () {
    test('record appVersion 1.2.0 in format 3, and restore here', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final clock = FakeClock(DateTime(2026, 10, 16, 9));
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
      expect(root['appVersion'], '1.2.0');
      expect(root['formatVersion'], 3);
      expect(root['product'], 'NextRep');
      final document = BackupCodec.decode(export.bytes);
      expect(document.appVersion, '1.2.0');
      expect(BackupValidator.validate(document).summary.arcCount, 1);
    });

    test('v1.0 and v1.1 era files (formats 1 and 2) still validate; their '
        'appVersion is information only', () {
      for (final name in ['phase5_backup_v1', 'v1_1_backup_v2']) {
        final bytes = File('test/fixtures/$name.nextrep').readAsBytesSync();
        final document = BackupCodec.decode(bytes);
        expect(document.appVersion, '1.0.0', reason: name);
        expect(
          BackupValidator.validate(document).summary.arcCount,
          2,
          reason: name,
        );
      }
    });
  });
}
