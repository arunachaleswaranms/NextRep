import '../../core/time/local_date.dart';
import 'winter_arc_session.dart';

/// One pause of a Rolling Arc (schema v7, `arc_freezes`): the calendar
/// dates `[frozenFrom, resumedOn)`.
///
/// [frozenFrom] is the first paused date. [resumedOn] is the first
/// challenge date after the pause (it is a day of the arc, not paused), or
/// null while the pause is open: an open pause has no known end, and every
/// date from [frozenFrom] on is paused until it is resumed.
///
/// A paused date is not a day of the arc: no day number, no record, no XP,
/// no Perfect Day, no reflection, never missed, and it neither grows nor
/// breaks a streak.
///
/// Created by Freeze, deleted by Cancel pause and closed by Resume
/// (`ArcPauseService`, Phase 12E2), or restored from a format-4 backup.
final class ArcFreeze {
  const ArcFreeze({
    required this.frozenFrom,
    required this.requestedAt,
    this.resumedOn,
    this.resumedAt,
  });

  final LocalDate frozenFrom;
  final LocalDate? resumedOn;

  /// When Freeze was confirmed. An instant, for information only.
  final DateTime requestedAt;

  /// When Resume was confirmed; null while open. For information only.
  final DateTime? resumedAt;

  bool get isOpen => resumedOn == null;

  /// The paused dates of a closed pause, `resumedOn − frozenFrom`; null
  /// while it is open.
  int? get pausedDays => switch (resumedOn) {
    null => null,
    final resumed => frozenFrom.daysUntil(resumed),
  };

  /// Whether [date] is paused by this interval.
  bool contains(LocalDate date) =>
      !date.isBefore(frozenFrom) &&
      (resumedOn == null || date.isBefore(resumedOn!));

  /// Whether the whole interval lies before [date] (it was resumed on or
  /// before it).
  bool endsOnOrBefore(LocalDate date) =>
      resumedOn != null && !resumedOn!.isAfter(date);

  @override
  bool operator ==(Object other) =>
      other is ArcFreeze &&
      other.frozenFrom == frozenFrom &&
      other.resumedOn == resumedOn &&
      other.requestedAt == requestedAt &&
      other.resumedAt == resumedAt;

  @override
  int get hashCode =>
      Object.hash(frozenFrom, resumedOn, requestedAt, resumedAt);

  @override
  String toString() =>
      'ArcFreeze(${frozenFrom.toIsoString()} – '
      '${resumedOn?.toIsoString() ?? 'open'})';
}

/// Rules over a session's freeze intervals.
abstract final class ArcFreezeRules {
  /// Total dates of the closed intervals in [freezes].
  static int closedPausedDays(Iterable<ArcFreeze> freezes) =>
      freezes.fold(0, (sum, f) => sum + (f.pausedDays ?? 0));

  /// Paused dates strictly before [date] in [freezes] (oldest first); of an
  /// open interval, the dates from its start up to [date]. Computed from
  /// the interval bounds, never by walking dates.
  static int pausedBefore(List<ArcFreeze> freezes, LocalDate date) {
    var paused = 0;
    for (final freeze in freezes) {
      if (!freeze.frozenFrom.isBefore(date)) break;
      final resumed = freeze.resumedOn;
      final until = resumed == null || date.isBefore(resumed) ? date : resumed;
      paused += freeze.frozenFrom.daysUntil(until);
    }
    return paused;
  }

  /// The first rule the freezes of [session] break, or null.
  ///
  /// * only a started rolling arc is ever paused
  /// * each interval has `resumedOn > frozenFrom` (an empty interval is
  ///   never stored), and a resume time exactly when it has a resume date
  /// * oldest first; each starts after the previous one was resumed and
  ///   after at least one challenge day lived since (Freeze always starts
  ///   the day after a lived day, and Resume makes its date a challenge
  ///   day), so intervals never overlap or touch
  /// * each starts after the participation start, and while a challenge
  ///   day is still to come (never after Day 92)
  /// * at most one is open; it is the last, and only an active arc has one
  /// * an ended arc has no pause after its last counted day
  ///
  /// The rolling end date that follows from the closed intervals is checked
  /// by [WinterArcRules.problemWith].
  static String? problemWith(WinterArcSession session) {
    final freezes = session.freezes;
    if (freezes.isEmpty) return null;
    if (session.kind != ArcKind.rolling92) {
      return 'a seasonal arc is not paused';
    }
    final joined = session.participationStartDate;
    if (joined == null) return 'an arc in setup is not paused';
    var paused = 0;
    LocalDate? previousResume;
    for (final (i, freeze) in freezes.indexed) {
      final resumed = freeze.resumedOn;
      if (resumed != null && !resumed.isAfter(freeze.frozenFrom)) {
        return 'a pause ends after it starts';
      }
      if ((resumed == null) != (freeze.resumedAt == null)) {
        return 'a resumed pause has a resume time';
      }
      if (resumed == null && i != freezes.length - 1) {
        return 'only the last pause is open';
      }
      if (previousResume != null &&
          !freeze.frozenFrom.isAfter(previousResume)) {
        return 'pauses overlap or are out of order';
      }
      if (!freeze.frozenFrom.isAfter(joined)) {
        return 'a pause starts after the first day';
      }
      // Challenge days before the pause starts: at least one was lived,
      // and at least one must remain.
      final daysBefore =
          session.startDate.daysUntil(freeze.frozenFrom) - paused;
      if (daysBefore >= WinterArcRules.lengthInDays) {
        return 'a pause after the last challenge day';
      }
      if (session.closedOn case final last?
          when freeze.frozenFrom.isAfter(last)) {
        return 'a pause after the arc closed';
      }
      paused += freeze.pausedDays ?? 0;
      previousResume = resumed;
    }
    if (freezes.last.isOpen && session.status != WinterArcStatus.active) {
      return 'only an active arc is paused';
    }
    return null;
  }
}
