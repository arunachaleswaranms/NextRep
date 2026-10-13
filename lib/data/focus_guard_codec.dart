import '../domain/focus_guard/focus_guard_platform.dart';

/// Decodes the values the Android Focus Guard platform channel sends.
///
/// Plain Dart, so malformed or empty platform results are tested without a
/// device. Anything unreadable fails closed: access reads as not granted,
/// and unreadable usage is an error rather than zero.
abstract final class FocusGuardCodec {
  /// `'granted'`, `'notGranted'` or `'unsupported'`; anything else reads as
  /// [UsageAccess.notGranted].
  static UsageAccess usageAccess(Object? raw) => switch (raw) {
    'granted' => UsageAccess.granted,
    'unsupported' => UsageAccess.unsupported,
    _ => UsageAccess.notGranted,
  };

  /// A list of `{packageName, label}` maps. Entries that aren't such a map,
  /// or have no package name, are skipped; a missing label is blank.
  static List<LaunchableAppCandidate> launchableApps(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry case {'packageName': final String packageName} && final map
            when packageName.isNotEmpty)
          LaunchableAppCandidate(
            packageName: packageName,
            label: switch (map['label']) {
              final String label => label,
              _ => '',
            },
          ),
    ];
  }

  /// A map from package name to foreground milliseconds, limited to
  /// [requested]. Throws [FormatException] if [raw] isn't a map; skips
  /// entries whose value isn't a non-negative integer.
  static Map<String, Duration> foregroundTime(
    Object? raw,
    Set<String> requested,
  ) {
    if (raw is! Map) {
      throw FormatException('Expected a map of foreground time', raw);
    }
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String &&
            requested.contains(key) &&
            value is int &&
            value >= 0)
          key: Duration(milliseconds: value),
    };
  }
}
