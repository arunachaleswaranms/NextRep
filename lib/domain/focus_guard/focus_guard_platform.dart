/// Whether Focus Guard can read how long apps were in the foreground.
///
/// This is Android's Usage Access, granted by the user on a system settings
/// page. It is a different permission from showing notifications: usage can
/// be measured while notifications are off, and the other way round.
enum UsageAccess {
  /// The platform has no Usage Access at all (iOS, tests). Focus Guard is
  /// unavailable and should be omitted or marked so.
  unsupported,

  /// Supported, but the user hasn't granted it, or has revoked it.
  notGranted,

  /// Granted right now.
  granted,
}

/// An app the user could choose for Focus Guard: one with a launcher entry
/// for the current user.
final class LaunchableAppCandidate {
  const LaunchableAppCandidate({
    required this.packageName,
    required this.label,
  });

  /// The Android package name, e.g. `com.example.app`.
  final String packageName;

  /// The name shown under the app's launcher icon.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is LaunchableAppCandidate &&
      other.packageName == packageName &&
      other.label == label;

  @override
  int get hashCode => Object.hash(packageName, label);

  @override
  String toString() => 'LaunchableAppCandidate($packageName, $label)';
}

/// The operating system's app-usage facilities, seen from the domain.
///
/// Everything stays on the device: nothing here talks to a server, reads
/// notifications or content, or controls another app. Android ships a
/// platform implementation; other platforms and tests use
/// [UnsupportedFocusGuardPlatform] or a fake.
abstract interface class FocusGuardPlatform {
  /// The current Usage Access state. Never prompts.
  ///
  /// Read it again before every use: Android doesn't restart the app when
  /// the user revokes access, so an earlier answer can be stale.
  Future<UsageAccess> usageAccess();

  /// Opens the system Usage Access page for NextRep, where the user grants
  /// or revokes it. Called only from an explicit user action.
  Future<void> openUsageAccessSettings();

  /// Whether Focus Guard's nudge could appear now: notifications are on for
  /// NextRep and its Focus Guard channel isn't blocked. The background
  /// check asks the same question before it nudges. Never prompts.
  Future<bool> nudgesAllowed();

  /// Apps with a launcher entry for the current user, as the platform
  /// reports them (possibly with duplicates and NextRep itself). Needs no
  /// broad package visibility.
  Future<List<LaunchableAppCandidate>> launchableApps();

  /// Foreground time from [from] to [to] for [packages] only. Packages
  /// without usage may be missing from the result.
  ///
  /// Without Usage Access Android returns no data rather than an error, so
  /// an empty result means nothing on its own: callers check [usageAccess]
  /// around it. Throws if the platform query fails.
  Future<Map<String, Duration>> foregroundTime(
    Set<String> packages, {
    required DateTime from,
    required DateTime to,
  });
}

/// No app-usage facilities: the default where no platform implementation
/// is wired in (iOS, widget and integration tests).
final class UnsupportedFocusGuardPlatform implements FocusGuardPlatform {
  const UnsupportedFocusGuardPlatform();

  @override
  Future<UsageAccess> usageAccess() async => UsageAccess.unsupported;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<bool> nudgesAllowed() async => false;

  @override
  Future<List<LaunchableAppCandidate>> launchableApps() async => const [];

  @override
  Future<Map<String, Duration>> foregroundTime(
    Set<String> packages, {
    required DateTime from,
    required DateTime to,
  }) async => const {};
}
