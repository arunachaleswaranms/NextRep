import 'package:package_info_plus/package_info_plus.dart';

import '../domain/update/installed_app.dart';

/// The installed package's version, from the platform (Android's
/// PackageManager, iOS's Info.plist) rather than a constant, so About shows
/// what is actually installed.
final class PlatformInstalledAppSource implements InstalledAppSource {
  const PlatformInstalledAppSource();

  @override
  Future<InstalledApp> read() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledApp(version: info.version, buildNumber: info.buildNumber);
  }
}
