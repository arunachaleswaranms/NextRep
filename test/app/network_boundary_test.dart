import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A static complement to the runtime proof in
/// `test/features/phase11d_about_flow_test.dart` (which counts real
/// requests): the source keeps NextRep's only network access in one place,
/// reachable from one button.
///
/// * one file talks HTTP, and only it constructs a client
/// * the feed is created only in `main.dart` (Android), read only by the
///   About controller and screen, and fetched only by the update checker
/// * no Kotlin code (Focus Guard's WorkManager check included) uses the
///   network, and TLS checks are never relaxed
Map<String, String> _sources(String root, String extension) => {
  for (final file in Directory(root).listSync(recursive: true))
    if (file is File && file.path.endsWith(extension))
      file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
};

Set<String> _filesMatching(Map<String, String> sources, Pattern pattern) => {
  for (final MapEntry(:key, :value) in sources.entries)
    if (value.contains(pattern)) key,
};

void main() {
  final dart = _sources('lib', '.dart');

  test('only the GitHub release feed uses an HTTP client', () {
    expect(_filesMatching(dart, RegExp(r"import 'package:http/")), {
      'lib/data/github_release_feed.dart',
    });
    expect(_filesMatching(dart, RegExp(r'\bHttpClient\b')), {
      'lib/data/github_release_feed.dart',
    });
    for (final api in [
      RegExp(r'\bWebSocket\b'),
      RegExp(r'\bSocket\.connect\b'),
      RegExp(r'\bRawSocket\b'),
      RegExp(r'\bHttpServer\b'),
      RegExp(r"package:(dio|chopper|retrofit|web_socket|grpc)"),
      'badCertificateCallback',
    ]) {
      expect(_filesMatching(dart, api), isEmpty, reason: '$api');
    }
  });

  test('the feed is built in main.dart only, and fetched only by the '
      'manual update check', () {
    expect(_filesMatching(dart, 'GitHubReleaseFeed('), {
      'lib/data/github_release_feed.dart',
      'lib/main.dart',
    });
    expect(_filesMatching(dart, 'releaseFeedProvider'), {
      'lib/app/dependencies.dart',
      'lib/main.dart',
      'lib/features/about/about_controller.dart',
      'lib/features/about/about_screen.dart',
    });
    expect(_filesMatching(dart, '.fetchLatest('), {
      'lib/domain/update/update_checker.dart',
    });
    expect(_filesMatching(dart, 'UpdateChecker('), {
      'lib/domain/update/update_checker.dart',
      'lib/features/about/about_controller.dart',
    });
    expect(_filesMatching(dart, 'updateCheckControllerProvider.notifier'), {
      'lib/features/about/about_screen.dart',
    });
  });

  test('no native code uses the network', () {
    final kotlin = _sources('android/app/src/main/kotlin', '.kt');
    expect(kotlin, isNotEmpty);
    for (final api in [
      'java.net',
      'javax.net',
      'okhttp',
      'HttpURLConnection',
      'android.net.http',
      'Cronet',
    ]) {
      expect(_filesMatching(kotlin, api), isEmpty, reason: api);
    }
  });

  test('the release manifest asks for INTERNET once, for the update check, '
      'and never for network state or package installs', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      RegExp(r'<uses-permission android:name="android.permission.INTERNET"/>')
          .allMatches(manifest),
      hasLength(1),
    );
    expect(
      manifest,
      contains(
        '<uses-permission\n'
        '        android:name="android.permission.ACCESS_NETWORK_STATE"\n'
        '        tools:node="remove" />',
      ),
    );
    for (final permission in [
      'REQUEST_INSTALL_PACKAGES',
      'QUERY_ALL_PACKAGES',
      'FOREGROUND_SERVICE',
      'ACCESS_NETWORK_STATE',
    ]) {
      expect(
        manifest,
        isNot(
          contains(
            '<uses-permission android:name="android.permission.$permission"',
          ),
        ),
        reason: permission,
      );
    }
  });
}
