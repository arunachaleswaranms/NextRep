import 'dart:convert';

import 'official_source.dart';
import 'release_version.dart';

/// The response wasn't a valid official stable release. Carries no part of
/// the response, so it is safe to log.
final class InvalidReleaseMetadata implements Exception {
  const InvalidReleaseMetadata(this.reason);

  final String reason;

  @override
  String toString() => 'InvalidReleaseMetadata: $reason';
}

/// A published, stable, official release, read from GitHub's "latest
/// release" response.
final class PublishedRelease {
  const PublishedRelease({required this.version, required this.androidReady});

  final ReleaseVersion version;

  /// Both the signed APK and its checksum are uploaded under their official
  /// names. A release without them can't be installed yet.
  final bool androidReady;

  /// Validates GitHub's release JSON ([body]) field by field. Throws
  /// [InvalidReleaseMetadata] unless it is a stable official release:
  ///
  /// * `tag_name` is a stable `vMAJOR.MINOR.PATCH` tag
  /// * `draft` and `prerelease` are present and false
  /// * `html_url` is that tag's page in the official repository
  /// * `assets` is a list of well-formed assets, and any official Android
  ///   asset is served from the official repository
  ///
  /// Only names, flags and URLs are read; release notes are ignored and
  /// nothing is fetched.
  static PublishedRelease parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const InvalidReleaseMetadata('not JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const InvalidReleaseMetadata('not a JSON object');
    }

    final tag = json['tag_name'];
    if (tag is! String) throw const InvalidReleaseMetadata('no tag_name');
    final version = ReleaseVersion.tryParseTag(tag);
    if (version == null) {
      throw const InvalidReleaseMetadata('tag_name is not a stable version');
    }
    if (json['draft'] != false) {
      throw const InvalidReleaseMetadata('draft is not false');
    }
    if (json['prerelease'] != false) {
      throw const InvalidReleaseMetadata('prerelease is not false');
    }
    final page = _uri(json['html_url']);
    if (page == null || !OfficialSource.isReleasePage(page, version)) {
      throw const InvalidReleaseMetadata('html_url is not the official page');
    }

    final assets = json['assets'];
    if (assets is! List<Object?>) {
      throw const InvalidReleaseMetadata('assets is not a list');
    }
    final apk = OfficialSource.apkName(version);
    final checksum = OfficialSource.checksumName(version);
    var apkReady = false;
    var checksumReady = false;
    for (final asset in assets) {
      if (asset is! Map<String, Object?>) {
        throw const InvalidReleaseMetadata('an asset is not an object');
      }
      final name = asset['name'];
      if (name is! String) {
        throw const InvalidReleaseMetadata('an asset has no name');
      }
      if (name != apk && name != checksum) continue;
      final download = _uri(asset['browser_download_url']);
      if (download == null ||
          !OfficialSource.isAssetDownload(download, version, name)) {
        throw const InvalidReleaseMetadata(
          'an Android asset is not served from the official repository',
        );
      }
      final size = asset['size'];
      final ready = asset['state'] == 'uploaded' && size is int && size > 0;
      if (name == apk) {
        apkReady = ready;
      } else {
        checksumReady = ready;
      }
    }
    return PublishedRelease(
      version: version,
      androidReady: apkReady && checksumReady,
    );
  }

  static Uri? _uri(Object? value) =>
      value is String && value.length <= 512 ? Uri.tryParse(value) : null;
}
