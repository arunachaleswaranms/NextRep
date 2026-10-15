import 'release_version.dart';

/// Where official NextRep releases are published, and the only pages the
/// app ever opens for them.
///
/// Every page is built here from validated parts. A URL taken from a
/// GitHub response is checked against these, never opened as is.
abstract final class OfficialSource {
  static const owner = 'arunachaleswaranms';
  static const repository = 'NextRep';

  /// The latest published full release (GitHub skips drafts and
  /// prereleases here, and answers 404 when there is none).
  static final latestReleaseApi = Uri.https(
    'api.github.com',
    '/repos/$owner/$repository/releases/latest',
  );

  static final repositoryPage = Uri.https('github.com', '/$owner/$repository');

  static final releasesPage = Uri.https(
    'github.com',
    '/$owner/$repository/releases',
  );

  /// `github.com/arunachaleswaranms/NextRep`, for display.
  static const repositoryLabel = 'github.com/$owner/$repository';

  /// Release metadata is about 12 KB; anything near this is not a release.
  static const maxMetadataBytes = 256 * 1024;

  /// The release page of [version], e.g. `.../releases/tag/v1.2.0`.
  static Uri releasePage(ReleaseVersion version) => Uri.https(
    'github.com',
    '/$owner/$repository/releases/tag/${version.tag}',
  );

  /// The signed Android APK every release publishes, and its checksum.
  static String apkName(ReleaseVersion version) =>
      'NextRep-${version.tag}-android.apk';

  static String checksumName(ReleaseVersion version) =>
      '${apkName(version)}.sha256';

  /// Where GitHub serves [assetName] of [version]. Only compared against,
  /// never fetched.
  static Uri assetDownload(ReleaseVersion version, String assetName) =>
      Uri.https(
        'github.com',
        '/$owner/$repository/releases/download/${version.tag}/$assetName',
      );

  /// Whether [uri] is [version]'s release page, as GitHub may spell it
  /// (owner and repository names are case-insensitive there).
  static bool isReleasePage(Uri uri, ReleaseVersion version) =>
      _isOfficial(uri, ['releases', 'tag', version.tag]);

  /// Whether [uri] is [version]'s download of [assetName].
  static bool isAssetDownload(
    Uri uri,
    ReleaseVersion version,
    String assetName,
  ) => _isOfficial(uri, ['releases', 'download', version.tag, assetName]);

  /// Whether the app may open [uri] in a browser: the repository, its
  /// releases, or one stable release's page. Nothing else, on any host.
  static bool isTrustedPage(Uri uri) {
    final rest = _officialRest(uri);
    if (rest == null) return false;
    return switch (rest) {
      [] || ['releases'] => true,
      ['releases', 'tag', final tag] => ReleaseVersion.tryParseTag(tag) != null,
      _ => false,
    };
  }

  static bool _isOfficial(Uri uri, List<String> expectedRest) {
    final rest = _officialRest(uri);
    if (rest == null || rest.length != expectedRest.length) return false;
    for (var i = 0; i < rest.length; i++) {
      if (rest[i] != expectedRest[i]) return false;
    }
    return true;
  }

  /// The path after `/<owner>/<repository>` of an https github.com URL with
  /// nothing else on it (no port, credentials, query or fragment), or null.
  static List<String>? _officialRest(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasPort && uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 2 ||
        segments[0].toLowerCase() != owner.toLowerCase() ||
        segments[1].toLowerCase() != repository.toLowerCase()) {
      return null;
    }
    return segments.sublist(2);
  }
}
