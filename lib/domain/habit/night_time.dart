/// A clock time in the night window 18:00 – 05:59, as one evening's night.
///
/// Stored as a normalized number of minutes so that times after midnight
/// sort after the evening: 18:00 is 1080, 23:59 is 1439, 00:00 is 1440,
/// 01:00 is 1500 and 05:59 is 1799. "At or before the target" is then a
/// plain `value <= target`, also across midnight (00:30 = 1470 is before
/// 01:00 = 1500, 23:10 = 1390 is before 23:30 = 1410).
///
/// 0 is never a valid time (midnight is 1440), which is why a stored
/// progress value of 0 can mean "not logged" for a clock-time habit.
///
/// Times between 06:00 and 17:59 can't be represented: the clock-time
/// habit type only supports this night window.
final class NightTime implements Comparable<NightTime> {
  const NightTime._(this.value);

  /// The time [hour]:[minute] (24-hour clock). Throws [ArgumentError] if it
  /// is outside the night window or not a time of day.
  factory NightTime(int hour, int minute) =>
      tryClock(hour, minute) ??
      (throw ArgumentError('Not a night time: $hour:$minute'));

  /// The time with normalized [value]. Throws [ArgumentError] if [value] is
  /// outside [minValue]..[maxValue].
  factory NightTime.fromValue(int value) {
    if (!isValidValue(value)) {
      throw ArgumentError.value(value, 'value', 'not a night time');
    }
    return NightTime._(value);
  }

  /// [hour]:[minute] as a night time, or null outside the window.
  static NightTime? tryClock(int hour, int minute) {
    if (minute < 0 || minute > 59) return null;
    if (hour >= eveningStartHour && hour <= 23) {
      return NightTime._(hour * 60 + minute);
    }
    if (hour >= 0 && hour < morningEndHour) {
      return NightTime._(_minutesPerDay + hour * 60 + minute);
    }
    return null;
  }

  /// The night time with normalized [value], or null if out of range.
  static NightTime? tryValue(int value) =>
      isValidValue(value) ? NightTime._(value) : null;

  /// The window starts at 18:00 ...
  static const int eveningStartHour = 18;

  /// ... and ends before 06:00.
  static const int morningEndHour = 6;

  static const int _minutesPerDay = 24 * 60;

  /// 18:00.
  static const int minValue = eveningStartHour * 60;

  /// 05:59 the next morning.
  static const int maxValue = _minutesPerDay + morningEndHour * 60 - 1;

  static bool isValidValue(int value) => value >= minValue && value <= maxValue;

  /// Normalized minutes, [minValue]..[maxValue].
  final int value;

  /// Hour of the clock, 0..23.
  int get hour => (value ~/ 60) % 24;

  int get minute => value % 60;

  /// Whether this is at or before [target] in the same night.
  bool isAtOrBefore(NightTime target) => value <= target.value;

  /// "00:45", "23:30".
  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(NightTime other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is NightTime && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NightTime($hhmm)';
}
