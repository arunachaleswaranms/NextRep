/// How demanding a challenge day is. Persisted by [name] per date; a date
/// with no stored mode is [normal]. A day returned to full targets stores an
/// explicit [normal].
enum DayMode {
  /// Full targets. Can become a Perfect Day.
  normal,

  /// Reduced targets for a hard day. Keeps habit streaks alive but never
  /// counts as a Perfect Day. While the date is still today it can be
  /// switched back to [normal]; a past date's mode never changes.
  minimum;

  bool get isMinimum => this == DayMode.minimum;
}
