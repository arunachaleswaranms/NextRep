import 'focus_guard_platform.dart';

/// Turns what the platform reports into the list a Focus Guard app picker
/// shows.
abstract final class LaunchableApps {
  /// One entry per package (an app can have several launcher entries),
  /// without [ownPackage] (NextRep can't guard against itself) or anything
  /// that isn't a well-formed package name, sorted by label.
  ///
  /// A blank label falls back to the package name, so every entry can be
  /// told apart.
  static List<LaunchableAppCandidate> forPicker(
    Iterable<LaunchableAppCandidate> reported, {
    required String ownPackage,
  }) {
    final byPackage = <String, LaunchableAppCandidate>{};
    for (final app in reported) {
      final packageName = app.packageName.trim();
      if (packageName == ownPackage || !isPackageName(packageName)) continue;
      final label = app.label.trim();
      final existing = byPackage[packageName];
      // The first entry with a real label wins.
      final hasRealLabel = existing != null && existing.label != packageName;
      if (existing != null && (hasRealLabel || label.isEmpty)) continue;
      byPackage[packageName] = LaunchableAppCandidate(
        packageName: packageName,
        label: label.isEmpty ? packageName : label,
      );
    }
    return byPackage.values.toList()..sort(_byLabel);
  }

  /// Whether [value] is a well-formed Android package name: two or more
  /// dot-separated segments, each starting with a letter.
  static bool isPackageName(String value) => _packageName.hasMatch(value);

  static final _packageName = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  static int _byLabel(LaunchableAppCandidate a, LaunchableAppCandidate b) {
    final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return byLabel != 0 ? byLabel : a.packageName.compareTo(b.packageName);
  }
}
