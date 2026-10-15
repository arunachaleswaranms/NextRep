/// A stable NextRep version, `MAJOR.MINOR.PATCH`, compared numerically
/// (1.10.0 is newer than 1.9.9).
///
/// Only plain stable versions parse: no prerelease or build suffix
/// (`1.2.0-beta`, `1.2.0+3`), no leading zeros, no signs or spaces, and at
/// most six digits per part, so a hostile tag can't overflow or slow the
/// parser. Anything else is rejected rather than guessed at.
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Longest text either parser looks at; longer input is rejected before
  /// the pattern runs.
  static const _maxLength = 24;

  static final _pattern = RegExp(
    r'^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$',
  );

  /// Parses a version name such as `1.2.0` (the installed app's), or null.
  static ReleaseVersion? tryParse(String text) {
    if (text.length > _maxLength) return null;
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return ReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Parses an official release tag, `v` plus a version (`v1.2.0`), or
  /// null.
  static ReleaseVersion? tryParseTag(String tag) {
    if (tag.length > _maxLength + 1 || !tag.startsWith('v')) return null;
    return tryParse(tag.substring(1));
  }

  /// The release tag for this version, e.g. `v1.2.0`.
  String get tag => 'v$this';

  @override
  int compareTo(ReleaseVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(ReleaseVersion other) => compareTo(other) > 0;

  bool operator <(ReleaseVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
