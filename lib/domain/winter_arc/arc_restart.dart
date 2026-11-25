import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import 'arc_clock_guard.dart';
import 'winter_arc_session.dart';

/// Why Restart is not offered for an arc on a date (ARC_CONTROL_SPEC § 6).
enum RestartBlocker {
  /// The arc is in setup, completed or ended: only the active arc can be
  /// restarted. A completed arc uses "Start New Arc → Reuse last setup"
  /// instead (spec § 6.4).
  notActive,

  /// Every challenge day is over on this date: the arc completes instead
  /// (the close-out runs at the next refresh). A paused arc is never over.
  over,

  /// Every habit is off, so the new arc would start with nothing to track
  /// (the start rule of `WinterArcService.startWinterArc`).
  noHabitsOn,
}

/// What Restart writes, decided by [ArcRestartRules.decide] inside the
/// repository's transaction (spec § 6.2):
///
/// * the old arc becomes [ended]: `status = ended`, `closedOn` = its last
///   lived day, an open (scheduled or in effect) freeze removed. Nothing
///   else of it changes: its planned `endDate`, closed freezes, habits,
///   goal revisions, progress, day modes, XP, unlocks and reflections stay
///   exactly as they are;
/// * a new Rolling arc starts, `active`, Day 1 = today, Day 92 = today +
///   91, with [habits] as its baseline and nothing else.
final class RestartPlan {
  const RestartPlan({
    required this.ended,
    required this.removedFreeze,
    required this.today,
    required this.now,
    required this.habits,
  });

  /// The old arc as it must be stored afterwards.
  final WinterArcSession ended;

  /// The first paused date of the open freeze that Restart removes, or
  /// null when the old arc had no open freeze.
  final LocalDate? removedFreeze;

  /// Day 1 of the new arc.
  final LocalDate today;

  /// The instant of the restart: the new arc's creation and start time.
  final DateTime now;

  /// The new arc's habits: each old habit at its latest configuration.
  final List<Habit> habits;

  /// The new arc as it must be stored, once the database has given it
  /// [id].
  WinterArcSession startedAs(int id) => WinterArcSession(
    id: id,
    kind: ArcKind.rolling92,
    startDate: today,
    endDate: WinterArcRules.endDateFor(today),
    status: WinterArcStatus.active,
    createdAt: now,
    participationStartDate: today,
    startedAt: now,
  );
}

/// What the Restart transaction reads before deciding.
final class RestartFacts {
  const RestartFacts({
    required this.session,
    required this.currentId,
    required this.habits,
    required this.lastActivityDate,
  });

  /// The arc the user asked to restart, as stored.
  final WinterArcSession session;

  /// The id of the unfinished (setup or active) arc, if any.
  final int? currentId;

  /// [session]'s habits with every goal revision.
  final HabitHistory habits;

  /// The latest date of any activity row of [session] (never a revision).
  final LocalDate? lastActivityDate;
}

/// The two arcs after a committed Restart.
final class RestartOutcome {
  const RestartOutcome({required this.ended, required this.started});

  /// The old arc, now ended early.
  final WinterArcSession ended;

  /// The new active Rolling arc, on Day 1.
  final WinterArcSession started;
}

/// Pure rules of Restart (ARC_CONTROL_SPEC § 6, addendum AD10–AD12,
/// AD19). They read only their arguments; the service calls [decide]
/// inside the repository's transaction with the stored arc, its habits and
/// its last activity date, and one clock read.
abstract final class ArcRestartRules {
  /// Why Restart is not offered for [session] on [today], or null when it
  /// is (subject to the clock guard, which needs the stored activity).
  static RestartBlocker? blockerOn(
    WinterArcSession session,
    LocalDate today, {
    HabitHistory? habits,
  }) {
    if (session.status != WinterArcStatus.active) {
      return RestartBlocker.notActive;
    }
    if (session.isOverOn(today)) return RestartBlocker.over;
    if (habits != null &&
        !habits.habits.any((h) => habits.latestConfig(h).enabled)) {
      return RestartBlocker.noHabitsOn;
    }
    return null;
  }

  /// The **last lived day** of [session] if it is restarted on [today]
  /// (spec § 6.2, addendum AD11): the first of
  ///
  /// 1. [today], when it is a challenge date and has activity
  ///    ([lastActivityDate] is today), or when it is the date the arc was
  ///    resumed on (Phase 12H correction, below);
  /// 2. the last challenge date before [today];
  /// 3. the participation start (a Day-1 restart with nothing logged: an
  ///    ended arc always has one counted day).
  ///
  /// **The resume date.** Like Day 1, a resume date starts a run of
  /// challenge days after a pause. Ending the arc on the day before that
  /// pause would leave the pause after `closed_on`, which no ended arc may
  /// hold (`ArcFreezeRules`, the format-4 backup rules), so the restart was
  /// refused on the resume date until something was logged (found in Phase
  /// 12H on the emulator). The resume date counts as lived on its own date
  /// instead: the same `closed_on` a restart the next morning gives, the
  /// pause kept as stored.
  ///
  /// A goal revision is never activity, so a date with only a waiting
  /// revision is never lived. The result is always a challenge date and
  /// never after [today]: never a paused date, never a future date.
  ///
  /// Assumes the clock guard holds (`lastActivityDate ≤ today`).
  static LocalDate lastLivedDay(
    WinterArcSession session, {
    required LocalDate today,
    required LocalDate? lastActivityDate,
  }) {
    if (session.isParticipatingOn(today) &&
        (lastActivityDate == today ||
            session.freezes.any((f) => f.resumedOn == today))) {
      return today;
    }
    final before = session.participatingDatesThrough(today.addDays(-1));
    if (before.isNotEmpty) return before.last;
    return session.participationStart;
  }

  /// Each habit of [history] at its **latest** configuration, as the new
  /// arc's baseline (addendum AD11): the latest goal revision of the
  /// habit, whatever its date (including one saved today that would have
  /// applied tomorrow), or its baseline when it has none. Copied per
  /// habit: id (built-in or custom), title, type, unit, icon, display
  /// order, target, Minimum Day target and on / off. No revision is
  /// copied; every habit is created at [createdAt].
  static List<Habit> baselineFrom(
    HabitHistory history, {
    required DateTime createdAt,
  }) => [
    for (final habit in history.habits)
      _withConfig(habit, history.latestConfig(habit), createdAt),
  ];

  static Habit _withConfig(Habit habit, HabitConfig config, DateTime at) =>
      Habit(
        id: habit.id,
        title: habit.title,
        type: habit.type,
        target: config.target,
        minimumTarget: config.minimumTarget,
        unit: habit.unit,
        iconKey: habit.iconKey,
        enabled: config.enabled,
        sortOrder: habit.sortOrder,
        createdAt: at,
      );

  /// Restart of [facts]' arc on [today] at [now], confirmed on a screen
  /// that showed [shownOn] as today and [shownClosedOn] as the old arc's
  /// last day.
  ///
  /// Throws, so that nothing is written:
  /// * [DomainRule.restartDateChanged] when [shownOn] is no longer today,
  ///   or the last lived day is no longer [shownClosedOn] (the arc changed
  ///   while the screen was open);
  /// * [DomainRule.arcCompleted] when the arc is completed, or over today
  ///   (it completes at the next refresh instead: never ended on Day 92's
  ///   next day);
  /// * [DomainRule.restartUnavailable] when it is not the active,
  ///   unfinished arc (setup, ended, or another arc is unfinished);
  /// * [DomainRule.clockBehindHistory] when the clock guard refuses
  ///   (today is before the participation start, the latest activity or
  ///   the latest resume: addendum AD19);
  /// * [DomainRule.noHabitsSelected] when every habit is off;
  /// * [DomainRule.invalidArc] when either arc would break an invariant,
  ///   or activity is stored after the last lived day (impossible for data
  ///   the app wrote; refused rather than leave it outside the arc).
  static RestartPlan decide(
    RestartFacts facts, {
    required LocalDate today,
    required DateTime now,
    required LocalDate shownOn,
    required LocalDate shownClosedOn,
  }) {
    final session = facts.session;
    if (shownOn != today) {
      throw const DomainFailure(
        DomainRule.restartDateChanged,
        'The restart date shown is no longer today',
      );
    }
    if (session.status == WinterArcStatus.completed ||
        (session.status == WinterArcStatus.active && session.isOverOn(today))) {
      throw const DomainFailure(
        DomainRule.arcCompleted,
        'The arc is complete and is not restarted',
      );
    }
    if (session.status != WinterArcStatus.active ||
        facts.currentId != session.id) {
      throw DomainFailure(
        DomainRule.restartUnavailable,
        'Session ${session.id} is not the active arc',
      );
    }
    final guard = ArcClockGuard.check(
      session: session,
      lastActivityDate: facts.lastActivityDate,
      today: today,
    );
    if (guard is ClockGuardBehind) {
      throw DomainFailure(
        DomainRule.clockBehindHistory,
        'Today is before the ${guard.bound.name} date',
      );
    }
    final closedOn = lastLivedDay(
      session,
      today: today,
      lastActivityDate: facts.lastActivityDate,
    );
    if (closedOn != shownClosedOn) {
      throw const DomainFailure(
        DomainRule.restartDateChanged,
        'The last lived day shown is no longer the last lived day',
      );
    }
    if (facts.lastActivityDate case final last? when last.isAfter(closedOn)) {
      throw const DomainFailure(
        DomainRule.invalidArc,
        'activity after the last lived day',
      );
    }
    final habits = baselineFrom(facts.habits, createdAt: now);
    if (!habits.any((h) => h.enabled)) {
      throw const DomainFailure(
        DomainRule.noHabitsSelected,
        'Every habit is off',
      );
    }
    final open = session.hasOpenFreeze ? session.freezes.last : null;
    final ended = session.copyWith(
      status: WinterArcStatus.ended,
      closedOn: closedOn,
      freezes: List.unmodifiable([
        for (final f in session.freezes)
          if (!f.isOpen) f,
      ]),
    );
    final plan = RestartPlan(
      ended: ended,
      removedFreeze: open?.frozenFrom,
      today: today,
      now: now,
      habits: List.unmodifiable(habits),
    );
    for (final arc in [ended, plan.startedAs(0)]) {
      if (WinterArcRules.problemWith(arc) case final problem?) {
        throw DomainFailure(DomainRule.invalidArc, problem);
      }
    }
    return plan;
  }
}

/// What the Restart screen shows, read once when it opens (and again when
/// the date changes or a request is refused). Everything comes from one
/// clock read.
final class RestartPreview {
  const RestartPreview({
    required this.session,
    required this.today,
    required this.blocker,
    required this.guard,
    required this.habits,
    required this.lastActivityDate,
  });

  /// The arc that would end.
  final WinterArcSession session;
  final LocalDate today;

  /// Why Restart is not offered, or null.
  final RestartBlocker? blocker;

  /// The clock guard on [today] (AD19).
  final ClockGuardVerdict guard;

  /// The new arc's habits, in display order: each at its latest
  /// configuration ([ArcRestartRules.baselineFrom], what the transaction
  /// copies).
  final List<Habit> habits;

  /// How many of [habits] the new arc starts with switched on: each
  /// habit's latest configuration, including a change still waiting for
  /// tomorrow, not what Today shows (Gate H copy C-2).
  int get habitsOn => habits.where((h) => h.enabled).length;

  /// The latest activity date of [session], as read for this preview.
  final LocalDate? lastActivityDate;

  bool get canRestart => blocker == null && guard.isSafe;

  /// The old arc's last lived day, when Restart is possible.
  LocalDate? get closedOn => canRestart
      ? ArcRestartRules.lastLivedDay(
          session,
          today: today,
          lastActivityDate: lastActivityDate,
        )
      : null;

  /// The challenge day of [closedOn]: "Your current Arc ends at Day 37".
  int? get closedDayNumber => switch (closedOn) {
    final last? => session.dayNumberOf(last),
    null => null,
  };

  /// The last day of the new arc: today + 91.
  LocalDate get newLastDay => WinterArcRules.endDateFor(today);

  /// Today is the old arc's Day 92 (spec § 6.4: "If you wait until
  /// tomorrow it will be completed").
  bool get isLastDay =>
      session.isParticipatingOn(today) &&
      session.dayNumberOf(today) == session.lengthInDays;

  /// Today is a paused date of the old arc.
  bool get isPausedToday => session.isFrozenOn(today);
}
