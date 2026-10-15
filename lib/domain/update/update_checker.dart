import 'dart:convert';

import 'github_release.dart';
import 'official_source.dart';
import 'release_feed.dart';
import 'release_version.dart';

/// What one manual update check found. A failure is never reported as
/// "up to date".
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// The installed version is the latest published one.
final class UpToDate extends UpdateCheckResult {
  const UpToDate({required this.latest});

  final ReleaseVersion latest;
}

/// A newer release with its signed APK and checksum is published.
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({required this.installed, required this.latest});

  final ReleaseVersion installed;
  final ReleaseVersion latest;

  /// The official page of [latest]; built here, never taken from GitHub's
  /// response.
  Uri get releasePage => OfficialSource.releasePage(latest);
}

/// A newer release is listed, but its Android APK or checksum isn't
/// uploaded yet.
final class ReleaseNotReady extends UpdateCheckResult {
  const ReleaseNotReady({required this.installed, required this.latest});

  final ReleaseVersion installed;
  final ReleaseVersion latest;
}

/// The installed version is newer than the latest published release (a
/// build made before its release).
final class NewerBuildInstalled extends UpdateCheckResult {
  const NewerBuildInstalled({required this.installed, required this.latest});

  final ReleaseVersion installed;
  final ReleaseVersion latest;
}

/// GitHub has no published full release (404).
final class NoPublishedRelease extends UpdateCheckResult {
  const NoPublishedRelease();
}

/// No answer: offline, DNS, TLS failure or timeout.
final class CheckNetworkFailure extends UpdateCheckResult {
  const CheckNetworkFailure();
}

/// GitHub is limiting unauthenticated requests (429, or 403 with its
/// rate-limit headers).
final class CheckRateLimited extends UpdateCheckResult {
  const CheckRateLimited();
}

/// GitHub answered with an error of its own (5xx, or another unexpected
/// status).
final class CheckServiceUnavailable extends UpdateCheckResult {
  const CheckServiceUnavailable();
}

/// An answer arrived but isn't a valid official stable release: a
/// redirect, not JSON, too large, or malformed or unofficial metadata.
final class CheckInvalidRelease extends UpdateCheckResult {
  const CheckInvalidRelease();
}

/// Compares the installed version with the latest official release. One
/// [check] makes exactly one request through [feed]; nothing here retries,
/// caches or stores anything.
final class UpdateChecker {
  const UpdateChecker(this.feed);

  final ReleaseFeed feed;

  Future<UpdateCheckResult> check(ReleaseVersion installed) async {
    final ReleaseFeedResponse response;
    try {
      response = await feed.fetchLatest();
    } on ReleaseFeedUnavailable {
      return const CheckNetworkFailure();
    } on ReleaseFeedTooLarge {
      return const CheckInvalidRelease();
    }
    return switch (response.statusCode) {
      200 => _compare(installed, response),
      404 => const NoPublishedRelease(),
      429 => const CheckRateLimited(),
      403 when _isRateLimit(response.headers) => const CheckRateLimited(),
      // Redirects aren't followed: the official endpoint answers directly.
      >= 300 && < 400 => const CheckInvalidRelease(),
      _ => const CheckServiceUnavailable(),
    };
  }

  static UpdateCheckResult _compare(
    ReleaseVersion installed,
    ReleaseFeedResponse response,
  ) {
    if (!_isJson(response.contentType)) return const CheckInvalidRelease();
    final PublishedRelease release;
    try {
      release = PublishedRelease.parse(utf8.decode(response.body));
    } on FormatException {
      return const CheckInvalidRelease(); // not UTF-8
    } on InvalidReleaseMetadata {
      return const CheckInvalidRelease();
    }
    final latest = release.version;
    if (latest < installed) {
      return NewerBuildInstalled(installed: installed, latest: latest);
    }
    if (latest == installed) return UpToDate(latest: latest);
    return release.androidReady
        ? UpdateAvailable(installed: installed, latest: latest)
        : ReleaseNotReady(installed: installed, latest: latest);
  }

  /// GitHub's primary limit says `x-ratelimit-remaining: 0`; its secondary
  /// limits send `retry-after`.
  static bool _isRateLimit(Map<String, String> headers) =>
      headers['x-ratelimit-remaining']?.trim() == '0' ||
      headers.containsKey('retry-after');

  static bool _isJson(String? contentType) {
    final media = contentType?.split(';').first.trim().toLowerCase();
    return media == 'application/json' ||
        media == 'application/vnd.github+json';
  }
}
