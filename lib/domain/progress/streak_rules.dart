/// How one challenge day affects a streak.
enum StreakMark {
  /// The day counts: the streak grows.
  hit,

  /// An eligible day that was not achieved: the streak resets.
  miss,

  /// The day does not apply (e.g. the habit was disabled that day). It
  /// neither grows nor breaks the streak.
  skip,

  /// Today, not achieved yet. It does not break the streak, since the day
  /// is not over.
  pending,
}

/// A current and best run.
final class Streak {
  const Streak({required this.current, required this.best})
    : assert(current >= 0 && best >= current);

  static const none = Streak(current: 0, best: 0);

  /// Length of the run that is still alive today.
  final int current;

  /// Longest run so far in the arc (including [current]).
  final int best;

  @override
  bool operator ==(Object other) =>
      other is Streak && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'Streak(current: $current, best: $best)';
}

abstract final class StreakRules {
  /// Computes a streak from [marks], one per challenge day in date order
  /// from Day 1 up to and including today. Callers never pass days outside
  /// the arc or after today, so those can never affect a streak.
  static Streak compute(Iterable<StreakMark> marks) {
    var run = 0;
    var best = 0;
    for (final mark in marks) {
      switch (mark) {
        case StreakMark.hit:
          run++;
          if (run > best) best = run;
        case StreakMark.miss:
          run = 0;
        case StreakMark.skip:
        case StreakMark.pending:
          break;
      }
    }
    return Streak(current: run, best: best);
  }

  /// Index of the first mark at which a run reaches [length] days, or null
  /// if no run ever does. Uses the same counting as [compute].
  static int? firstReaching(List<StreakMark> marks, int length) {
    var run = 0;
    for (final (index, mark) in marks.indexed) {
      switch (mark) {
        case StreakMark.hit:
          if (++run >= length) return index;
        case StreakMark.miss:
          run = 0;
        case StreakMark.skip:
        case StreakMark.pending:
          break;
      }
    }
    return null;
  }
}
