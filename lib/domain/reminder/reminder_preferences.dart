/// A local wall-clock time of day, e.g. 21:00.
final class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour must be 0..23'),
      assert(minute >= 0 && minute < 60, 'minute must be 0..59');

  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// The user's reminder choices. They belong to the app, not to an arc, and
/// only ever produce reminders for the active arc.
///
/// Both reminders are off until the user turns them on.
final class ReminderPreferences {
  const ReminderPreferences({
    required this.dailyEnabled,
    required this.dailyTime,
    required this.reflectionEnabled,
    required this.reflectionTime,
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

  bool get anyEnabled => dailyEnabled || reflectionEnabled;

  ReminderPreferences copyWith({
    bool? dailyEnabled,
    ReminderTime? dailyTime,
    bool? reflectionEnabled,
    ReminderTime? reflectionTime,
  }) => ReminderPreferences(
    dailyEnabled: dailyEnabled ?? this.dailyEnabled,
    dailyTime: dailyTime ?? this.dailyTime,
    reflectionEnabled: reflectionEnabled ?? this.reflectionEnabled,
    reflectionTime: reflectionTime ?? this.reflectionTime,
  );

  @override
  bool operator ==(Object other) =>
      other is ReminderPreferences &&
      other.dailyEnabled == dailyEnabled &&
      other.dailyTime == dailyTime &&
      other.reflectionEnabled == reflectionEnabled &&
      other.reflectionTime == reflectionTime;

  @override
  int get hashCode =>
      Object.hash(dailyEnabled, dailyTime, reflectionEnabled, reflectionTime);
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
