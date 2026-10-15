import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/update/github_release.dart';
import 'package:nextrep/domain/update/official_source.dart';
import 'package:nextrep/domain/update/release_feed.dart';
import 'package:nextrep/domain/update/release_version.dart';
import 'package:nextrep/domain/update/update_checker.dart';

import '../support/updates.dart';

/// Answers each fetch with [next], or throws [error]. Counts fetches.
final class _Feed implements ReleaseFeed {
  _Feed({this.next, this.error});

  ReleaseFeedResponse? next;
  ReleaseFeedException? error;
  int fetches = 0;

  @override
  Future<ReleaseFeedResponse> fetchLatest() async {
    fetches++;
    if (error case final error?) throw error;
    return next!;
  }
}

ReleaseFeedResponse _json(
  Object? json, {
  int status = 200,
  String contentType = 'application/json; charset=utf-8',
  Map<String, String> headers = const {},
}) => _raw(
  json == null ? '' : jsonEncode(json),
  status: status,
  contentType: contentType,
  headers: headers,
);

ReleaseFeedResponse _raw(
  String body, {
  int status = 200,
  String contentType = 'application/json; charset=utf-8',
  Map<String, String> headers = const {},
}) => ReleaseFeedResponse(
  statusCode: status,
  headers: {'content-type': contentType, ...headers},
  body: Uint8List.fromList(utf8.encode(body)),
);

const _installed = ReleaseVersion(1, 1, 0);

Future<UpdateCheckResult> _check(
  ReleaseFeedResponse response, {
  ReleaseVersion installed = _installed,
}) => UpdateChecker(_Feed(next: response)).check(installed);

void main() {
  group('PublishedRelease.parse', () {
    PublishedRelease parse(Map<String, Object?> json) =>
        PublishedRelease.parse(jsonEncode(json));

    final invalid = throwsA(isA<InvalidReleaseMetadata>());

    test('a published stable release with its APK and checksum', () {
      final release = parse(releaseJson(tag: 'v1.2.0'));
      expect(release.version, const ReleaseVersion(1, 2, 0));
      expect(release.androidReady, isTrue);
    });

    test('the real v1.1.0 shape (assets in either order, extra assets)', () {
      final release = parse(
        releaseJson(
          tag: 'v1.1.0',
          assets: [
            asset('notes.txt', tag: 'v1.1.0'),
            ...androidAssets('v1.1.0').reversed,
          ],
        ),
      );
      expect(release.version, const ReleaseVersion(1, 1, 0));
      expect(release.androidReady, isTrue);
    });

    test('drafts and prereleases are never stable releases', () {
      expect(() => parse(releaseJson(draft: true)), invalid);
      expect(() => parse(releaseJson(prerelease: true)), invalid);
    });

    test('draft and prerelease must be present booleans', () {
      expect(() => parse(releaseJson(omit: {'draft'})), invalid);
      expect(() => parse(releaseJson(omit: {'prerelease'})), invalid);
      expect(() => parse(releaseJson(draft: 'false')), invalid);
      expect(() => parse(releaseJson(prerelease: 0)), invalid);
      expect(() => parse(releaseJson(draft: null)), invalid);
    });

    test('tag_name must be a stable version string', () {
      expect(() => parse(releaseJson(omit: {'tag_name'})), invalid);
      for (final tag in ['v1.2.0-beta', 'v1.2.0-rc.1', '1.2.0', 'v1.2', '']) {
        expect(() => parse(releaseJson(tag: tag)), invalid, reason: tag);
      }
      final numeric = releaseJson()..['tag_name'] = 120;
      expect(() => parse(numeric), invalid);
      final list = releaseJson()..['tag_name'] = ['v1.2.0'];
      expect(() => parse(list), invalid);
    });

    group('html_url must be the tag page of the official repository', () {
      for (final (label, url) in [
        ('missing', null),
        ('not a string', 42),
        (
          'http',
          'http://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'another host',
          'https://evil.example/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'a lookalike host',
          'https://github.com.evil.example/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'a subdomain',
          'https://gist.github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'credentials',
          'https://user@github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'another port',
          'https://github.com:8443/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
        ),
        (
          'another owner',
          'https://github.com/someone/NextRep/releases/tag/v1.2.0',
        ),
        (
          'another repository',
          'https://github.com/arunachaleswaranms/NextRep-fork/releases/tag/v1.2.0',
        ),
        (
          'another tag',
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v9.9.9',
        ),
        (
          'a download',
          'https://github.com/arunachaleswaranms/NextRep/releases/download/v1.2.0/NextRep-v1.2.0-android.apk',
        ),
        (
          'a query',
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0?x=1',
        ),
        (
          'a fragment',
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0#x',
        ),
        (
          'an extra segment',
          'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0/extra',
        ),
        ('javascript', 'javascript:alert(1)'),
        ('an intent', 'intent://github.com/#Intent;scheme=https;end'),
        ('a file', 'file:///sdcard/NextRep.apk'),
        ('empty', ''),
      ]) {
        test(label, () {
          final json = releaseJson();
          if (url == null) {
            json.remove('html_url');
          } else {
            json['html_url'] = url;
          }
          expect(() => parse(json), invalid);
        });
      }

      test('GitHub may differ in owner and repository case', () {
        final release = parse(
          releaseJson(
            htmlUrl: 'https://github.com/ArunachaleswaranMS/nextrep/releases/tag/v1.2.0',
          ),
        );
        expect(release.version, const ReleaseVersion(1, 2, 0));
      });
    });

    group('Android assets', () {
      test('missing or malformed assets make the release invalid', () {
        expect(() => parse(releaseJson(omit: {'assets'})), invalid);
        expect(() => parse(releaseJson(assets: 'none')), invalid);
        expect(() => parse(releaseJson(assets: ['x'])), invalid);
        expect(
          () => parse(
            releaseJson(
              assets: [
                {'state': 'uploaded'},
              ],
            ),
          ),
          invalid,
        );
      });

      test('no assets yet: listed, not ready', () {
        expect(parse(releaseJson(assets: const [])).androidReady, isFalse);
      });

      test('the APK without its checksum, or the reverse, is not ready', () {
        final [apk, checksum] = androidAssets('v1.2.0');
        expect(parse(releaseJson(assets: [apk])).androidReady, isFalse);
        expect(parse(releaseJson(assets: [checksum])).androidReady, isFalse);
      });

      test('an asset still uploading is not ready', () {
        expect(
          parse(
            releaseJson(assets: androidAssets('v1.2.0', apkState: 'starter')),
          ).androidReady,
          isFalse,
        );
        expect(
          parse(
            releaseJson(assets: androidAssets('v1.2.0', checksumState: 'open')),
          ).androidReady,
          isFalse,
        );
      });

      test('an empty or unsized asset is not ready', () {
        for (final size in [0, -1, null, '93', 1.5]) {
          final assets = [
            androidAssets('v1.2.0').first,
            asset(
              'NextRep-v1.2.0-android.apk.sha256',
              tag: 'v1.2.0',
              size: size,
            ),
          ];
          expect(
            parse(releaseJson(assets: assets)).androidReady,
            isFalse,
            reason: '$size',
          );
        }
      });

      test('assets of another version or naming are not this release', () {
        expect(
          parse(releaseJson(tag: 'v1.2.0', assets: androidAssets('v1.1.0')))
              .androidReady,
          isFalse,
        );
        expect(
          parse(
            releaseJson(
              assets: [
                asset('NextRep-v1.2.0.apk', tag: 'v1.2.0'),
                asset('NextRep-v1.2.0-android.APK', tag: 'v1.2.0'),
              ],
            ),
          ).androidReady,
          isFalse,
        );
      });

      test('an official asset served from elsewhere makes it invalid', () {
        for (final url in [
          'https://evil.example/NextRep-v1.2.0-android.apk',
          'https://github.com/someone/NextRep/releases/download/v1.2.0/NextRep-v1.2.0-android.apk',
          'http://github.com/arunachaleswaranms/NextRep/releases/download/v1.2.0/NextRep-v1.2.0-android.apk',
          'https://github.com/arunachaleswaranms/NextRep/releases/download/v1.1.0/NextRep-v1.2.0-android.apk',
        ]) {
          final assets = [
            asset(
              'NextRep-v1.2.0-android.apk',
              tag: 'v1.2.0',
              downloadUrl: url,
            ),
            androidAssets('v1.2.0').last,
          ];
          expect(
            () => parse(releaseJson(assets: assets)),
            invalid,
            reason: url,
          );
        }
      });
    });

    test('not JSON, not an object, or empty', () {
      for (final body in [
        '',
        '<!DOCTYPE html><html><body>GitHub</body></html>',
        '{"tag_name": "v1.2.0"',
        '[]',
        '"v1.2.0"',
        'null',
        '42',
      ]) {
        expect(() => PublishedRelease.parse(body), invalid, reason: body);
      }
    });

    test('the error carries no part of the response', () {
      const secret = 'SYNTHETIC-RESPONSE-TEXT';
      try {
        PublishedRelease.parse('{"tag_name": "$secret"}');
        fail('expected InvalidReleaseMetadata');
      } on InvalidReleaseMetadata catch (error) {
        expect('$error', isNot(contains(secret)));
      }
    });
  });

  group('UpdateChecker', () {
    test(
      'a newer release with its APK: update available, canonical page',
      () async {
        final result = await _check(_json(releaseJson(tag: 'v1.2.0')));
        expect(result, isA<UpdateAvailable>());
        final available = result as UpdateAvailable;
        expect(available.installed, _installed);
        expect(available.latest, const ReleaseVersion(1, 2, 0));
        expect(
          available.releasePage,
          Uri.parse(
            'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
          ),
        );
      },
    );

    test('the release page is built, not copied from the response', () async {
      final result = await _check(
        _json(
          releaseJson(
            htmlUrl: 'https://github.com/ARUNACHALESWARANMS/NEXTREP/releases/tag/v1.2.0',
          ),
        ),
      );
      expect(
        (result as UpdateAvailable).releasePage.toString(),
        'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
      );
    });

    test('the same version: up to date', () async {
      final result = await _check(_json(releaseJson(tag: 'v1.1.0')));
      expect(result, isA<UpToDate>());
      expect((result as UpToDate).latest, _installed);
    });

    test('the same version is up to date even without assets', () async {
      final result = await _check(
        _json(releaseJson(tag: 'v1.1.0', assets: const [])),
      );
      expect(result, isA<UpToDate>());
    });

    test('an older release: this build is newer, never an update', () async {
      final result = await _check(
        _json(releaseJson(tag: 'v1.1.0')),
        installed: const ReleaseVersion(1, 2, 0),
      );
      expect(result, isA<NewerBuildInstalled>());
      final newer = result as NewerBuildInstalled;
      expect(newer.installed, const ReleaseVersion(1, 2, 0));
      expect(newer.latest, _installed);
    });

    test('a newer release without its Android files: not ready', () async {
      for (final assets in [
        const <Object>[],
        [androidAssets('v1.2.0').first],
        androidAssets('v1.2.0', apkState: 'starter'),
      ]) {
        final result = await _check(_json(releaseJson(assets: assets)));
        expect(result, isA<ReleaseNotReady>());
        expect(
          (result as ReleaseNotReady).latest,
          const ReleaseVersion(1, 2, 0),
        );
      }
    });

    test('10 > 9: v1.10.0 is an update over 1.9.9', () async {
      final result = await _check(
        _json(releaseJson(tag: 'v1.10.0')),
        installed: const ReleaseVersion(1, 9, 9),
      );
      expect(result, isA<UpdateAvailable>());
    });

    test('drafts, prereleases and malformed metadata are invalid, never '
        'up to date', () async {
      for (final json in [
        releaseJson(tag: 'v1.1.0', draft: true),
        releaseJson(tag: 'v1.1.0', prerelease: true),
        releaseJson(tag: 'v1.2.0-beta'),
        releaseJson(omit: {'tag_name'}),
        releaseJson(omit: {'assets'}),
        releaseJson(htmlUrl: 'https://evil.example/'),
      ]) {
        expect(await _check(_json(json)), isA<CheckInvalidRelease>());
      }
    });

    test('HTML, an empty body or broken UTF-8 are invalid', () async {
      expect(
        await _check(_raw('<html>Sign in</html>', contentType: 'text/html')),
        isA<CheckInvalidRelease>(),
      );
      expect(
        await _check(_raw('<html>Sign in</html>')),
        isA<CheckInvalidRelease>(),
      );
      expect(await _check(_raw('')), isA<CheckInvalidRelease>());
      expect(
        await _check(
          ReleaseFeedResponse(
            statusCode: 200,
            headers: const {'content-type': 'application/json'},
            body: Uint8List.fromList([0x7b, 0xff, 0xfe, 0x7d]),
          ),
        ),
        isA<CheckInvalidRelease>(),
      );
    });

    test('valid JSON with an unexpected content type is invalid', () async {
      for (final type in ['text/plain', 'application/octet-stream', '']) {
        expect(
          await _check(_json(releaseJson(), contentType: type)),
          isA<CheckInvalidRelease>(),
          reason: type,
        );
      }
      expect(
        await _check(
          _json(releaseJson(), contentType: 'application/vnd.github+json'),
        ),
        isA<UpdateAvailable>(),
      );
    });

    test('404: no published release', () async {
      expect(
        await _check(_json({'message': 'Not Found'}, status: 404)),
        isA<NoPublishedRelease>(),
      );
    });

    test('429, or 403 with rate-limit headers: rate limited', () async {
      expect(await _check(_json(null, status: 429)), isA<CheckRateLimited>());
      expect(
        await _check(
          _json(null, status: 403, headers: {'x-ratelimit-remaining': '0'}),
        ),
        isA<CheckRateLimited>(),
      );
      expect(
        await _check(_json(null, status: 403, headers: {'retry-after': '60'})),
        isA<CheckRateLimited>(),
      );
    });

    test('another 403 or a 5xx: GitHub unavailable, not offline', () async {
      for (final status in [403, 500, 502, 503, 504, 418, 204]) {
        expect(
          await _check(
            _json(
              null,
              status: status,
              headers: {'x-ratelimit-remaining': '42'},
            ),
          ),
          isA<CheckServiceUnavailable>(),
          reason: '$status',
        );
      }
    });

    test('a redirect is not followed and not trusted', () async {
      for (final status in [301, 302, 303, 307, 308]) {
        expect(
          await _check(
            _json(
              null,
              status: status,
              headers: {'location': 'https://evil.example/releases/latest'},
            ),
          ),
          isA<CheckInvalidRelease>(),
          reason: '$status',
        );
      }
    });

    test('no answer: network failure; too large: invalid', () async {
      expect(
        await UpdateChecker(
          _Feed(error: const ReleaseFeedUnavailable('offline')),
        ).check(_installed),
        isA<CheckNetworkFailure>(),
      );
      expect(
        await UpdateChecker(_Feed(error: const ReleaseFeedTooLarge()))
            .check(_installed),
        isA<CheckInvalidRelease>(),
      );
    });

    test('one check, one fetch', () async {
      final feed = _Feed(next: _json(releaseJson()));
      final checker = UpdateChecker(feed);
      expect(feed.fetches, 0); // constructing fetches nothing
      await checker.check(_installed);
      expect(feed.fetches, 1);
      await checker.check(_installed);
      expect(feed.fetches, 2);
    });
  });

  group('OfficialSource', () {
    test('the API endpoint and pages are the official repository', () {
      expect(
        OfficialSource.latestReleaseApi.toString(),
        'https://api.github.com/repos/arunachaleswaranms/NextRep/releases/latest',
      );
      expect(
        OfficialSource.repositoryPage.toString(),
        'https://github.com/arunachaleswaranms/NextRep',
      );
      expect(
        OfficialSource.releasesPage.toString(),
        'https://github.com/arunachaleswaranms/NextRep/releases',
      );
      expect(
        OfficialSource.apkName(const ReleaseVersion(1, 2, 0)),
        'NextRep-v1.2.0-android.apk',
      );
      expect(
        OfficialSource.checksumName(const ReleaseVersion(1, 2, 0)),
        'NextRep-v1.2.0-android.apk.sha256',
      );
    });

    test('only the repository, its releases and stable release pages may '
        'be opened', () {
      for (final page in [
        OfficialSource.repositoryPage,
        OfficialSource.releasesPage,
        OfficialSource.releasePage(const ReleaseVersion(1, 2, 0)),
      ]) {
        expect(OfficialSource.isTrustedPage(page), isTrue, reason: '$page');
      }
      for (final page in [
        'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0-beta',
        'https://github.com/arunachaleswaranms/NextRep/releases/download/v1.2.0/NextRep-v1.2.0-android.apk',
        'https://github.com/arunachaleswaranms/NextRep/issues',
        'https://github.com/arunachaleswaranms',
        'https://github.com/someone/NextRep',
        'https://api.github.com/repos/arunachaleswaranms/NextRep/releases/latest',
        'http://github.com/arunachaleswaranms/NextRep',
        'https://evil.example/arunachaleswaranms/NextRep',
        'https://github.com/arunachaleswaranms/NextRep?tab=readme',
        'intent://github.com/arunachaleswaranms/NextRep',
      ]) {
        expect(
          OfficialSource.isTrustedPage(Uri.parse(page)),
          isFalse,
          reason: page,
        );
      }
    });
  });
}
