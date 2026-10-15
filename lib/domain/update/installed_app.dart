import 'release_version.dart';

/// The installed app's own version, as the platform reports it (Android's
/// versionName and versionCode, iOS's short version and build).
final class InstalledApp {
  const InstalledApp({required this.version, required this.buildNumber});

  /// The version name, e.g. `1.1.0`.
  final String version;

  /// The build number, e.g. `2`.
  final String buildNumber;

  /// [version] for comparing with releases; null if it isn't a plain
  /// `MAJOR.MINOR.PATCH`.
  ReleaseVersion? get releaseVersion => ReleaseVersion.tryParse(version);
}

/// Reads [InstalledApp] from the platform. Local only.
abstract interface class InstalledAppSource {
  Future<InstalledApp> read();
}
