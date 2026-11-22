import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import 'arc_clock_guard.dart';
import 'winter_arc_session.dart';

/// Why Freeze is not offered for an arc on a date (spec § 5.2 F1, F4).
enum PauseBlocker {
  /// The arc is in setup, completed or ended.
  notActive,

  /// A Seasonal Winter Arc is never paused.
  seasonal,

  /// Today is not one of the arc's challenge days (before its start or
  /// after its last day).
  notChallengeDay,

  /// Today is Day 92: no challenge day is left to pause.
  lastDay,

  /// A pause is already scheduled to start on a later date.
  scheduled,

  /// Today is a paused date.
  paused,
}

/// A change to a session's freeze intervals, decided by [ArcPauseRules] and
/// applied by `WinterArcRepository.changeFreezes` inside one transaction.
/// Freeze, Cancel and Resume change nothing else: no activity row, no goal
/// revision, no XP (spec § 5.2 F7).
sealed class FreezeChange {
  const FreezeChange();

  /// [session] with this change applied, in memory: what the stored session
  /// becomes. Used for previews, so a preview and the stored result come
  /// from the same decision.
  WinterArcSession applyTo(WinterArcSession session);
}

/// Nothing to write: the request is already in effect (a repeated tap, or a
/// second request that lost a race with the first).
final class FreezeUnchanged extends FreezeChange {
  const FreezeUnchanged();

  @override
  WinterArcSession applyTo(WinterArcSession session) => session;
}

/// Inserts the open freeze [freeze] (Freeze).
final class ScheduleFreeze extends FreezeChange {
  const ScheduleFreeze(this.freeze);

  final ArcFreeze freeze;

  @override
  WinterArcSession applyTo(WinterArcSession session) => session.copyWith(
    freezes: List.unmodifiable([...session.freezes, freeze]),
  );
}

/// Deletes the open freeze starting on [frozenFrom] (Cancel pause, or a
/// Resume on its first date, which would be an empty interval: addendum
/// § F3). No date was paused.
final class DeleteOpenFreeze extends FreezeChange {
  const DeleteOpenFreeze(this.frozenFrom);

  final LocalDate frozenFrom;

  @override
  WinterArcSession applyTo(WinterArcSession session) => session.copyWith(
    freezes: List.unmodifiable([
      for (final f in session.freezes)
        if (!(f.isOpen && f.frozenFrom == frozenFrom)) f,
    ]),
  );
}

/// Closes the open freeze starting on [frozenFrom] on [resumedOn] and moves
/// the stored end date to [endDate] (Resume, spec § 5.2 F5).
final class CloseFreeze extends FreezeChange {
  const CloseFreeze({
    required this.frozenFrom,
    required this.resumedOn,
    required this.resumedAt,
    required this.endDate,
  });

  final LocalDate frozenFrom;
  final LocalDate resumedOn;
  final DateTime resumedAt;
  final LocalDate endDate;

  @override
  WinterArcSession applyTo(WinterArcSession session) => session.copyWith(
    endDate: endDate,
    freezes: List.unmodifiable([
      for (final f in session.freezes)
        if (f.isOpen && f.frozenFrom == frozenFrom)
          ArcFreeze(
            frozenFrom: f.frozenFrom,
            requestedAt: f.requestedAt,
            resumedOn: resumedOn,
            resumedAt: resumedAt,
          )
        else
          f,
    ]),
  );
}

/// Pure rules of Freeze, Cancel pause and Resume (ARC_CONTROL_SPEC § 5,
/// addendum AD5–AD8, AD19). They read only their arguments; the service
/// calls them inside the repository's transaction with the stored session,
/// its last activity date and one clock read.
abstract final class ArcPauseRules {
  /// Why Freeze is not offered for [session] on [today], or null when it is
  /// (subject to the clock guard, which needs the stored activity).
  static PauseBlocker? blockerOn(WinterArcSession session, LocalDate today) {
    if (session.status != WinterArcStatus.active) return PauseBlocker.notActive;
    if (session.kind != ArcKind.rolling92) return PauseBlocker.seasonal;
    if (session.openFreeze case final open?) {
      return today.isBefore(open.frozenFrom)
          ? PauseBlocker.scheduled
          : PauseBlocker.paused;
    }
    if (session.isFrozenOn(today)) return PauseBlocker.paused;
    if (!session.isParticipatingOn(today)) return PauseBlocker.notChallengeDay;
    // A pause starts tomorrow, so a challenge day must still be to come.
    if (session.dayNumberOf(today)! >= session.lengthInDays) {
      return PauseBlocker.lastDay;
    }
    return null;
  }

  /// The first paused date of a pause requested on [today]: always the next
  /// calendar date (F2). Never moved by a goal revision or by activity.
  static LocalDate frozenFromFor(LocalDate today) => today.addDays(1);

  /// Freeze, requested on [today] at [now] for the pause start the user was
  /// shown ([shownFrozenFrom]).
  ///
  /// Throws, so that nothing is written:
  /// * [DomainRule.pauseDateChanged] when [shownFrozenFrom] is no longer
  ///   tomorrow (midnight passed while the sheet was open);
  /// * [DomainRule.pauseUnavailable] when [blockerOn] refuses;
  /// * [DomainRule.clockBehindHistory] when the clock guard refuses.
  ///
  /// A pause already scheduled for exactly [shownFrozenFrom] is
  /// [FreezeUnchanged] (a repeated request).
  static FreezeChange pause(
    WinterArcSession session, {
    required LocalDate today,
    required DateTime now,
    required LocalDate? lastActivityDate,
    required LocalDate shownFrozenFrom,
  }) {
    final frozenFrom = frozenFromFor(today);
    if (shownFrozenFrom != frozenFrom) {
      throw const DomainFailure(
        DomainRule.pauseDateChanged,
        'The pause start shown is no longer tomorrow',
      );
    }
    final open = session.openFreeze;
    if (session.status == WinterArcStatus.active &&
        open != null &&
        open.frozenFrom == frozenFrom) {
      return const FreezeUnchanged();
    }
    if (blockerOn(session, today) case final blocker?) {
      throw DomainFailure(
        DomainRule.pauseUnavailable,
        'Freeze is not available: ${blocker.name}',
      );
    }
    final guard = ArcClockGuard.check(
      session: session,
      lastActivityDate: lastActivityDate,
      today: today,
    );
    if (guard is ClockGuardBehind) {
      throw DomainFailure(
        DomainRule.clockBehindHistory,
        'Today is before the ${guard.bound.name} date',
      );
    }
    return ScheduleFreeze(ArcFreeze(frozenFrom: frozenFrom, requestedAt: now));
  }

  /// Cancel pause on [today]: deletes a pause that has not started yet
  /// (F3). With no pause scheduled there is nothing to cancel
  /// ([FreezeUnchanged]).
  ///
  /// Throws [DomainRule.pauseAlreadyStarted] once the pause has begun
  /// (midnight passed): it can only be resumed then.
  static FreezeChange cancel(
    WinterArcSession session, {
    required LocalDate today,
  }) {
    final open = session.openFreeze;
    if (open == null) return const FreezeUnchanged();
    if (!today.isBefore(open.frozenFrom)) {
      throw const DomainFailure(
        DomainRule.pauseAlreadyStarted,
        'The pause has already started',
      );
    }
    return DeleteOpenFreeze(open.frozenFrom);
  }

  /// Resume on [today] at [now], for the date the user was shown
  /// ([shownOn]) (F5, AD7): today becomes the next challenge day, the open
  /// pause is closed on today and the end date moves later by the paused
  /// dates. On the pause's first date the interval would be empty, so it is
  /// deleted instead ([DeleteOpenFreeze]): nothing was paused.
  ///
  /// An arc already running today (a repeated request) is
  /// [FreezeUnchanged].
  ///
  /// Throws, so that nothing is written:
  /// * [DomainRule.resumeDateChanged] when [shownOn] is no longer today;
  /// * [DomainRule.notPaused] when the arc isn't paused today (not active,
  ///   no open pause, or a pause that has not started: cancel it instead).
  static FreezeChange resume(
    WinterArcSession session, {
    required LocalDate today,
    required DateTime now,
    required LocalDate shownOn,
  }) {
    if (shownOn != today) {
      throw const DomainFailure(
        DomainRule.resumeDateChanged,
        'The resume date shown is no longer today',
      );
    }
    final open = session.openFreeze;
    if (session.status != WinterArcStatus.active) {
      throw const DomainFailure(DomainRule.notPaused, 'The arc is not active');
    }
    if (open == null) {
      if (session.isParticipatingOn(today)) return const FreezeUnchanged();
      throw const DomainFailure(DomainRule.notPaused, 'The arc is not paused');
    }
    if (today.isBefore(open.frozenFrom)) {
      throw const DomainFailure(
        DomainRule.notPaused,
        'The pause has not started yet',
      );
    }
    final paused = open.frozenFrom.daysUntil(today);
    if (paused == 0) return DeleteOpenFreeze(open.frozenFrom);
    return CloseFreeze(
      frozenFrom: open.frozenFrom,
      resumedOn: today,
      resumedAt: now,
      endDate: session.endDate.addDays(paused),
    );
  }
}

/// Pause facts about a session, for display.
extension ArcPauseFacts on WinterArcSession {
  /// The open freeze (scheduled or in effect), if any.
  ArcFreeze? get openFreeze => hasOpenFreeze ? freezes.last : null;

  /// The pause scheduled to start after [today], if any.
  ArcFreeze? scheduledPauseOn(LocalDate today) => switch (openFreeze) {
    final open? when today.isBefore(open.frozenFrom) => open,
    _ => null,
  };

  /// Paused dates of this arc as of [today]: every closed pause, plus the
  /// dates of an open pause before [today] (the dates a Resume today would
  /// close). Matches "Paused since … · N days" and "You paused for N
  /// days".
  int pausedDaysThrough(LocalDate today) {
    var days = pausedDays;
    if (openFreeze case final open? when open.frozenFrom.isBefore(today)) {
      days += open.frozenFrom.daysUntil(today);
    }
    return days;
  }
}

/// What the Pause sheet shows, read once when it opens (and again when the
/// date changes or a request is refused). Everything comes from one clock
/// read.
final class PausePreview {
  const PausePreview({
    required this.session,
    required this.today,
    required this.blocker,
    required this.guard,
  });

  final WinterArcSession session;
  final LocalDate today;

  /// Why Freeze is not offered, or null.
  final PauseBlocker? blocker;

  /// The clock guard on [today] (AD19).
  final ClockGuardVerdict guard;

  /// The first paused date: tomorrow.
  LocalDate get frozenFrom => ArcPauseRules.frozenFromFor(today);

  /// Today's challenge day number, when today is a challenge day.
  int? get todayDayNumber =>
      session.isParticipatingOn(today) ? session.dayNumberOf(today) : null;

  /// The challenge day the user continues on after the pause.
  int? get nextDayNumber => switch (todayDayNumber) {
    null => null,
    final day => day + 1,
  };

  bool get canPause => blocker == null && guard.isSafe;
}

/// What the Resume sheet shows, read once when it opens (and again when the
/// date changes). [resumed] is the arc exactly as Resume would store it.
final class ResumePreview {
  const ResumePreview({
    required this.session,
    required this.today,
    required this.resumed,
  });

  final WinterArcSession session;
  final LocalDate today;

  /// The arc after a Resume today, or null when it can't resume today (not
  /// paused, or a pause that has not started).
  final WinterArcSession? resumed;

  bool get canResume => resumed != null;

  /// The day number today becomes.
  int? get dayNumber => resumed?.dayNumberOf(today);

  /// The new last day (Day 92).
  LocalDate? get lastDay => resumed?.dateOfDay(resumed!.lengthInDays);

  /// Paused dates this pause covers if it ends today.
  int get pausedDays => switch (session.openFreeze) {
    final open? when open.frozenFrom.isBefore(today) =>
      open.frozenFrom.daysUntil(today),
    _ => 0,
  };

  /// Paused dates of the whole arc after a Resume today.
  int get totalPausedDays => session.pausedDaysThrough(today);
}
