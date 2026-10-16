import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:nextrep/data/external_links.dart';
import 'package:nextrep/domain/update/installed_app.dart';

/// Synthetic GitHub "latest release" JSON for [tag], shaped like the real
/// API's (only the fields NextRep reads, plus a few it ignores). Every
/// part can be replaced or removed (pass [omit]).
Map<String, Object?> releaseJson({
  String tag = 'v1.2.0',
  Object? draft = false,
  Object? prerelease = false,
  Object? htmlUrl,
  Object? assets,
  Set<String> omit = const {},
}) {
  final json = <String, Object?>{
    'url': 'https://api.github.com/repos/arunachaleswaranms/NextRep/releases/1',
    'html_url':
        htmlUrl ??
        'https://github.com/arunachaleswaranms/NextRep/releases/tag/$tag',
    'id': 1,
    'tag_name': tag,
    'name': 'NextRep $tag',
    'draft': draft,
    'prerelease': prerelease,
    'body': 'Synthetic release notes. <script>never rendered</script>',
    'assets': assets ?? androidAssets(tag),
  };
  for (final key in omit) {
    json.remove(key);
  }
  return json;
}

/// The official APK and checksum assets of [tag].
List<Map<String, Object?>> androidAssets(
  String tag, {
  String apkState = 'uploaded',
  String checksumState = 'uploaded',
}) => [
  asset('NextRep-$tag-android.apk', tag: tag, state: apkState, size: 63684809),
  asset(
    'NextRep-$tag-android.apk.sha256',
    tag: tag,
    state: checksumState,
    size: 93,
  ),
];

Map<String, Object?> asset(
  String name, {
  required String tag,
  String state = 'uploaded',
  Object? size = 1,
  String? downloadUrl,
}) => {
  'name': name,
  'state': state,
  'size': size,
  'content_type': 'application/octet-stream',
  'browser_download_url':
      downloadUrl ??
      'https://github.com/arunachaleswaranms/NextRep/releases/download/$tag/$name',
};

/// A GitHub answer with a JSON (or other) body.
http.StreamedResponse githubResponse(
  int status, {
  Object? json,
  String? body,
  String contentType = 'application/json; charset=utf-8',
  Map<String, String> headers = const {},
}) {
  final bytes = utf8.encode(body ?? (json == null ? '' : jsonEncode(json)));
  return http.StreamedResponse(
    Stream.value(bytes),
    status,
    contentLength: bytes.length,
    headers: {'content-type': contentType, ...headers},
  );
}

/// An HTTP client standing in for GitHub. Records every request it is
/// sent and how often it was closed; [respond] decides each answer (by
/// default, the latest release is [releaseJson]'s v1.2.0).
final class FakeGitHubClient extends http.BaseClient {
  FakeGitHubClient([Future<http.StreamedResponse> Function()? respond])
    : respond =
          respond ?? (() async => githubResponse(200, json: releaseJson()));

  Future<http.StreamedResponse> Function() respond;
  final requests = <http.BaseRequest>[];
  int closes = 0;

  /// Makes the next answers wait until the returned completer completes.
  Completer<http.StreamedResponse> hold() {
    final pending = Completer<http.StreamedResponse>();
    respond = () => pending.future;
    return pending;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond();
  }

  @override
  void close() => closes++;
}

/// The installed package, as the platform would report it. By default a
/// fake installed **v1.1.0 (2)**, the release before the 1.2 line, so that
/// [releaseJson]'s default v1.2.0 reads as a newer release. This is
/// deliberate and does not follow `pubspec.yaml`; tests about this build
/// pass [pubspecVersion].
final class FakeInstalledAppSource implements InstalledAppSource {
  FakeInstalledAppSource({this.version = '1.1.0', this.buildNumber = '2'});

  final String version;
  final String buildNumber;
  bool fail = false;
  int reads = 0;

  @override
  Future<InstalledApp> read() async {
    reads++;
    if (fail) throw StateError('package metadata unavailable');
    return InstalledApp(version: version, buildNumber: buildNumber);
  }
}

/// Records the pages the app asked to open; [opens] says whether a browser
/// "opened" them.
final class FakeExternalLinks implements ExternalLinks {
  FakeExternalLinks({this.opens = true});

  bool opens;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri page) async {
    opened.add(page);
    return opens;
  }
}

/// `pubspec.yaml`'s version name and build number, e.g. `('1.2.0', '3')`:
/// Android's versionName and versionCode for this source.
(String, String) pubspecVersion() {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
  return (match.group(1)!, match.group(2)!);
}
