/// How today's combined usage of the selected apps compares with the
/// budget. Visual only: no state here touches habits, XP, streaks,
/// achievements, Perfect Day or Minimum Day.
enum FocusGuardShield {
  /// Under [FocusGuardMeter.nearLimitPercent] of the budget.
  strong,

  /// At least [FocusGuardMeter.nearLimitPercent] of the budget, not yet all.
  nearLimit,

  /// The whole budget used: the day's nudge, if any, has been or will be
  /// sent. Tomorrow starts fresh.
  reached,
}

/// Today's measured usage against the combined daily budget.
///
/// Decisions use exact durations; minutes are for display only, so
/// rounding never moves a threshold. Used minutes round down and remaining
/// minutes round up, so the screen never shows "0 min remaining" before the
/// budget is actually reached, nor the full budget a moment early.
final class FocusGuardMeter {
  FocusGuardMeter({required this.used, required this.budgetMinutes})
    : assert(budgetMinutes > 0);

  /// "Near today's limit" from this share of the budget.
  static const nearLimitPercent = 80;

  final Duration used;
  final int budgetMinutes;

  Duration get budget => Duration(minutes: budgetMinutes);

  bool get reached => used >= budget;

  FocusGuardShield get shield {
    if (reached) return FocusGuardShield.reached;
    // used ≥ 80 % of budget, in whole microseconds.
    if (used.inMicroseconds * 100 >= budget.inMicroseconds * nearLimitPercent) {
      return FocusGuardShield.nearLimit;
    }
    return FocusGuardShield.strong;
  }

  /// Whole minutes used, rounded down.
  int get usedMinutes => used.isNegative ? 0 : used.inMinutes;

  /// Whole minutes left, rounded up; 0 once [reached].
  int get remainingMinutes {
    if (reached) return 0;
    final left = budget - (used.isNegative ? Duration.zero : used);
    return (left.inMicroseconds + Duration.microsecondsPerMinute - 1) ~/
        Duration.microsecondsPerMinute;
  }

  /// Share of the budget used, 0–1, for a progress bar.
  double get fraction {
    if (used <= Duration.zero) return 0;
    final value = used.inMicroseconds / budget.inMicroseconds;
    return value > 1 ? 1 : value;
  }
}
