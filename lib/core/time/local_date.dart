/// A calendar date with no time-of-day and no time zone.
///
/// Challenge days are calendar days in the user's local time, so all day
/// arithmetic is done on [LocalDate] rather than [DateTime]. Internally the
/// arithmetic runs on UTC midnights, which never shift for daylight saving
/// time, so "days between" is always an exact integer.
final class LocalDate implements Comparable<LocalDate> {
  /// Creates a date and validates it (e.g. `LocalDate(2026, 2, 30)` throws).
  factory LocalDate(int year, int month, int day) {
    final utc = DateTime.utc(year, month, day);
    if (utc.year != year || utc.month != month || utc.day != day) {
      throw ArgumentError('Invalid calendar date: $year-$month-$day');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// The calendar date of [dateTime] in whatever zone [dateTime] is expressed.
  ///
  /// For a local [DateTime] this is the user's local calendar date.
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate._(dateTime.year, dateTime.month, dateTime.day);

  /// Parses the ISO-8601 `YYYY-MM-DD` form produced by [toIsoString].
  factory LocalDate.parse(String value) {
    final match = _isoPattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected YYYY-MM-DD', value);
    }
    return LocalDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static final _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  DateTime get _utcMidnight => DateTime.utc(year, month, day);

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(_utcMidnight.add(Duration(days: days)));

  /// Number of whole days from this date to [other] (negative if earlier).
  int daysUntil(LocalDate other) =>
      other._utcMidnight.difference(_utcMidnight).inDays;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  /// Local midnight of this date, for display formatting only.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  String toIsoString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIsoString();
}
