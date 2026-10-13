import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import 'focus_guard_platform.dart';

/// Today so far: from local midnight of [now]'s calendar date up to [now].
///
/// Computed afresh on every read, so it restarts at local midnight and
/// follows a time-zone change without anything being reset or stored.
final class LocalDayWindow {
  LocalDayWindow._(this.day, this.start, this.end);

  factory LocalDayWindow.endingAt(DateTime now) {
    final day = LocalDate.fromDateTime(now);
    // A local DateTime resolves midnight in the device's zone; where a
    // zone skips midnight for daylight saving time, Dart moves to the
    // first instant that exists.
    final start = now.isUtc
        ? DateTime.utc(day.year, day.month, day.day)
        : DateTime(day.year, day.month, day.day);
    return LocalDayWindow._(day, start, now);
  }

  /// The calendar day being measured.
  final LocalDate day;
  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);
}

/// Why today's usage can't be shown.
enum UsageUnavailableReason {
  /// The platform has no Usage Access (iOS, tests).
  unsupported,

  /// Usage Access isn't granted, or was revoked.
  accessRequired,

  /// The platform query failed or returned something unreadable.
  failed,
}

/// The result of reading today's usage of the selected apps.
///
/// There is deliberately no "last known value": when usage can't be read,
/// the answer is [UsageUnavailable], never an older total.
sealed class TodayUsage {
  const TodayUsage();
}

final class UsageUnavailable extends TodayUsage {
  const UsageUnavailable(this.reason);

  final UsageUnavailableReason reason;

  @override
  bool operator ==(Object other) =>
      other is UsageUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'UsageUnavailable(${reason.name})';
}

final class UsageMeasured extends TodayUsage {
  const UsageMeasured({required this.day, required this.total});

  /// The calendar day [total] belongs to.
  final LocalDate day;

  /// Combined foreground time of the selected apps since local midnight.
  final Duration total;

  @override
  bool operator ==(Object other) =>
      other is UsageMeasured && other.day == day && other.total == total;

  @override
  int get hashCode => Object.hash(day, total);

  @override
  String toString() => 'UsageMeasured($day, $total)';
}

/// Reads the combined foreground time of the selected apps for today.
///
/// It is derived from the platform on every call and kept nowhere: Focus
/// Guard holds no history of app usage. Usage Access is checked before and
/// after each query, because Android answers a query without access with
/// empty data rather than an error, which would otherwise read as
/// "0 minutes".
final class TodayUsageReader {
  const TodayUsageReader({required this._platform, required this._clock});

  final FocusGuardPlatform _platform;
  final Clock _clock;

  Future<TodayUsage> read(Set<String> selectedPackages) async {
    final before = await _access();
    if (before != UsageAccess.granted) return _unavailable(before);

    final window = LocalDayWindow.endingAt(_clock.now());
    if (selectedPackages.isEmpty || window.length <= Duration.zero) {
      return UsageMeasured(day: window.day, total: Duration.zero);
    }

    final Map<String, Duration> perPackage;
    try {
      perPackage = await _platform.foregroundTime(
        selectedPackages,
        from: window.start,
        to: window.end,
      );
    } catch (_) {
      final after = await _access();
      return after == UsageAccess.granted
          ? const UsageUnavailable(UsageUnavailableReason.failed)
          : _unavailable(after);
    }

    // Revoked while the query ran: its empty answer means nothing.
    final after = await _access();
    if (after != UsageAccess.granted) return _unavailable(after);

    return UsageMeasured(
      day: window.day,
      total: combine(perPackage, selectedPackages, window.length),
    );
  }

  /// The selected apps' time added up. Unselected packages and negative
  /// values are ignored, and no app or total exceeds [window] (split-screen
  /// apps can be in the foreground together).
  static Duration combine(
    Map<String, Duration> perPackage,
    Set<String> selectedPackages,
    Duration window,
  ) {
    var total = Duration.zero;
    for (final MapEntry(key: packageName, value: time) in perPackage.entries) {
      if (!selectedPackages.contains(packageName)) continue;
      if (time <= Duration.zero) continue;
      total += time > window ? window : time;
    }
    return total > window ? window : total;
  }

  /// A failing access check counts as no access.
  Future<UsageAccess> _access() async {
    try {
      return await _platform.usageAccess();
    } catch (_) {
      return UsageAccess.notGranted;
    }
  }

  static UsageUnavailable _unavailable(UsageAccess access) =>
      UsageUnavailable(switch (access) {
        UsageAccess.unsupported => UsageUnavailableReason.unsupported,
        UsageAccess.notGranted ||
        UsageAccess.granted => UsageUnavailableReason.accessRequired,
      });
}
