/// How demanding a challenge day is. Persisted by [name] per date; a date
/// with no stored mode is [normal].
enum DayMode {
  /// Full targets. Can become a Perfect Day.
  normal,

  /// Reduced targets for a hard day. Keeps habit streaks alive but never
  /// counts as a Perfect Day. Once chosen for a date it cannot be reverted.
  minimum;

  bool get isMinimum => this == DayMode.minimum;
}
