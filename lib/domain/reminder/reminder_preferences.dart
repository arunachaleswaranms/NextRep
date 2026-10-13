import '../../core/errors/app_failure.dart';

/// A local wall-clock time of day, e.g. 21:00.
final class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour must be 0..23'),
      assert(minute >= 0 && minute < 60, 'minute must be 0..59');

  final int hour;
  final int minute;

  /// Minutes since local midnight, `0..1439`.
  int get minuteOfDay => hour * 60 + minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// How many hydration nudges a day Hydration Coach may send at most.
/// Persisted by [name], so never rename values.
enum HydrationMode {
  /// Up to 3 nudges a day.
  gentle(3),

  /// Up to 4 nudges a day. The default.
  balanced(4),

  /// Up to 5 nudges a day.
  supportive(5);

  const HydrationMode(this.maxNudges);

  /// A ceiling, not a promise: a day on pace gets fewer, or none.
  final int maxNudges;

  /// The mode stored as [name], or null if unknown.
  static HydrationMode? fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

/// Hydration Coach's active hours: a window inside one local day.
///
/// Only valid windows exist: [start] is before [end] on the same day (no
/// overnight window) and the window lasts [minMinutes] to [maxMinutes].
/// The unnamed constructor enforces it, so an invalid window can't be
/// saved, restored or planned with.
final class HydrationWindow {
  /// Throws [DomainFailure] with [DomainRule.invalidHydrationWindow] unless
  /// [isValid].
  factory HydrationWindow(ReminderTime start, ReminderTime end) {
    if (!isValid(start, end)) {
      throw const DomainFailure(
        DomainRule.invalidHydrationWindow,
        'Active hours must be a same-day window of 8 to 18 hours',
      );
    }
    return HydrationWindow._(start, end);
  }

  const HydrationWindow._(this.start, this.end);

  /// 08:00 – 20:00.
  static const defaults = HydrationWindow._(
    ReminderTime(8, 0),
    ReminderTime(20, 0),
  );

  /// Shortest window: 8 hours.
  static const minMinutes = 8 * 60;

  /// Longest window: 18 hours.
  static const maxMinutes = 18 * 60;

  /// Whether [start] – [end] is a same-day window of [minMinutes] to
  /// [maxMinutes]. A positive length also means [start] is before [end].
  static bool isValid(ReminderTime start, ReminderTime end) {
    final length = end.minuteOfDay - start.minuteOfDay;
    return length >= minMinutes && length <= maxMinutes;
  }

  /// The window, or null if [start] – [end] isn't [isValid].
  static HydrationWindow? tryCreate(ReminderTime start, ReminderTime end) =>
      isValid(start, end) ? HydrationWindow._(start, end) : null;

  final ReminderTime start;
  final ReminderTime end;

  int get lengthInMinutes => end.minuteOfDay - start.minuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is HydrationWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start–$end';
}

/// The user's reminder choices. They belong to the app, not to an arc, and
/// only ever produce reminders for the active arc.
///
/// Every reminder, Hydration Coach included, is off until the user turns
/// it on.
final class ReminderPreferences {
  const ReminderPreferences({
    required this.dailyEnabled,
    required this.dailyTime,
    required this.reflectionEnabled,
    required this.reflectionTime,
    this.hydrationEnabled = false,
    this.hydrationWindow = HydrationWindow.defaults,
    this.hydrationMode = HydrationMode.balanced,
  });

  /// Everything off. The times are only the suggested starting values for
  /// the time pickers.
  static const defaults = ReminderPreferences(
    dailyEnabled: false,
    dailyTime: ReminderTime(8, 0),
    reflectionEnabled: false,
    reflectionTime: ReminderTime(21, 0),
  );

  /// "Your Winter Arc is waiting", opening Today.
  final bool dailyEnabled;
  final ReminderTime dailyTime;

  /// "How did today go?", opening today's reflection in the Journal.
  final bool reflectionEnabled;
  final ReminderTime reflectionTime;

  /// Hydration Coach: nudges only when today's Water progress is behind
  /// pace, within [hydrationWindow], at most [HydrationMode.maxNudges] a
  /// day. Its target is always the Arc's own Water target.
  final bool hydrationEnabled;
  final HydrationWindow hydrationWindow;
  final HydrationMode hydrationMode;

  bool get anyEnabled => dailyEnabled || reflectionEnabled || hydrationEnabled;

  ReminderPreferences copyWith({
    bool? dailyEnabled,
    ReminderTime? dailyTime,
    bool? reflectionEnabled,
    ReminderTime? reflectionTime,
    bool? hydrationEnabled,
    HydrationWindow? hydrationWindow,
    HydrationMode? hydrationMode,
  }) => ReminderPreferences(
    dailyEnabled: dailyEnabled ?? this.dailyEnabled,
    dailyTime: dailyTime ?? this.dailyTime,
    reflectionEnabled: reflectionEnabled ?? this.reflectionEnabled,
    reflectionTime: reflectionTime ?? this.reflectionTime,
    hydrationEnabled: hydrationEnabled ?? this.hydrationEnabled,
    hydrationWindow: hydrationWindow ?? this.hydrationWindow,
    hydrationMode: hydrationMode ?? this.hydrationMode,
  );

  @override
  bool operator ==(Object other) =>
      other is ReminderPreferences &&
      other.dailyEnabled == dailyEnabled &&
      other.dailyTime == dailyTime &&
      other.reflectionEnabled == reflectionEnabled &&
      other.reflectionTime == reflectionTime &&
      other.hydrationEnabled == hydrationEnabled &&
      other.hydrationWindow == hydrationWindow &&
      other.hydrationMode == hydrationMode;

  @override
  int get hashCode => Object.hash(
    dailyEnabled,
    dailyTime,
    reflectionEnabled,
    reflectionTime,
    hydrationEnabled,
    hydrationWindow,
    hydrationMode,
  );
}

/// Persistence boundary for [ReminderPreferences].
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class ReminderPreferencesRepository {
  /// The stored preferences, or [ReminderPreferences.defaults] if none were
  /// ever saved.
  Future<ReminderPreferences> load();

  Future<void> save(ReminderPreferences preferences, {required DateTime at});
}
