import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../habit/habit_edit.dart';
import '../journey/journey_overview.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'arc_history.dart';
import 'day_mode.dart';
import 'day_rules.dart';
import 'day_summary.dart';
import 'habit_progress_rules.dart';
import 'progress_repository.dart';

/// A habit with its configuration today and from the next challenge day.
final class HabitSetting {
  const HabitSetting({
    required this.habit,
    required this.config,
    required this.upcoming,
  });

  final Habit habit;

  /// In effect today. Fixed for the rest of the day.
  final HabitConfig config;

  /// In effect from the next challenge day, where edits land. Null on the
  /// arc's last day.
  final HabitConfig? upcoming;

  /// An edit is waiting to take effect tomorrow.
  bool get hasPendingChange => upcoming != null && upcoming != config;

  /// The configuration an edit starts from.
  HabitConfig get editable => upcoming ?? config;
}

/// Habit configuration for editing, as of [date] (today).
final class HabitSettings {
  const HabitSettings({
    required this.date,
    required this.habits,
    required this.editable,
    required this.configEditable,
  });

  final LocalDate date;
  final List<HabitSetting> habits;

  /// False when the arc is not running today or is complete.
  final bool editable;

  /// Goals and on/off can change (from tomorrow). False on the last day,
  /// when only names can still be edited.
  final bool configEditable;
}

/// What a habit edit changed.
final class HabitEditOutcome {
  const HabitEditOutcome({required this.renamed, required this.configFrom});

  final bool renamed;

  /// The date the new configuration applies from, if it changed.
  final LocalDate? configFrom;
}

/// Use cases of a Winter Arc: tracking the current day, Minimum Day, habit
/// editing, and the derived history (Today, Journey, summary). Writes need
/// an active arc; a completed arc stays readable.
///
/// Every mutation goes through [ProgressRepository.commitDay]: the day's
/// state is read inside a transaction, [DayRules.settle] computes the exact
/// writes (progress, completion, XP), and they are applied atomically.
final class HabitTrackingService {
  const HabitTrackingService({
    required this._sessions,
    required this._progress,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final ProgressRepository _progress;
  final Clock _clock;

  /// Builds the summary of today's progress for the current arc. A
  /// completed arc is read-only ([DaySummary.isTrackable] is false).
  Future<DaySummary> today() async => DaySummary.fromHistory(await history());

  /// Builds the Journey of the current (active or completed) arc.
  Future<JourneyOverview> journey() async =>
      JourneyOverview.fromHistory(await history());

  /// The derived history of the current (active or completed) arc.
  Future<ArcHistory> history() async {
    final session = await _startedSession();
    final records = await _progress.loadArc(session.id);
    return ArcHistory(
      session: session,
      records: records,
      today: _clock.today(),
    );
  }

  /// Validates and applies [action] to [habitId] for [date].
  ///
  /// [date] is the day the user is looking at. If the calendar day has rolled
  /// over since, the action is rejected with [DomainRule.staleDay] rather than
  /// silently applied to a different day.
  Future<DayCommit<ProgressTransition>> perform({
    required String habitId,
    required HabitAction action,
    required LocalDate date,
  }) async {
    final session = await _trackableSession(date);
    final now = _clock.now();
    return _progress.commitDay(
      sessionId: session.id,
      date: date,
      build: (day) {
        if (day.habits.habit(habitId) == null) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
        final entry = day.record.entryFor(habitId);
        if (entry == null) {
          throw DomainFailure(
            DomainRule.habitDisabled,
            '"$habitId" is disabled',
          );
        }
        final transition = HabitProgressRules.apply(
          habit: entry.habit,
          target: entry.target,
          current: entry.progress,
          action: action,
          now: now,
        );
        final change = DayChange(
          progress: [if (transition.changed) transition.after],
        );
        return (DayRules.settle(day, change, now: now), transition);
      },
    );
  }

  /// Switches [date] (which must be today) to a Minimum Day.
  ///
  /// Effective targets drop to each habit's minimum target. Progress is kept;
  /// habits whose progress already meets the minimum become complete and earn
  /// their XP. One-way: there is no switch back to normal for that date.
  /// Idempotent: the value is false if the day already was a Minimum Day.
  /// Rejected if the day is already a Perfect Day.
  Future<DayCommit<bool>> activateMinimumDay({required LocalDate date}) async {
    final session = await _trackableSession(date);
    final now = _clock.now();
    return _progress.commitDay(
      sessionId: session.id,
      date: date,
      build: (day) {
        if (day.mode == DayMode.minimum) {
          return (DayRules.settle(day, const DayChange(), now: now), false);
        }
        if (day.record.isPerfect) {
          throw const DomainFailure(
            DomainRule.dayAlreadyPerfect,
            'Today is already a Perfect Day',
          );
        }
        const change = DayChange(mode: DayMode.minimum);
        return (DayRules.settle(day, change, now: now), true);
      },
    );
  }

  /// The current arc's habits with today's and the next day's
  /// configuration.
  Future<HabitSettings> habitSettings() async {
    final session = await _startedSession();
    final today = _clock.today();
    final next = _nextChallengeDay(session, today);
    final records = await _progress.loadArc(session.id);
    final editable =
        session.status == WinterArcStatus.active &&
        session.positionOn(today) is ArcInProgress;
    return HabitSettings(
      date: today,
      editable: editable,
      configEditable: editable && next != null,
      habits: [
        for (final habit in records.habits.habits)
          HabitSetting(
            habit: habit,
            config: records.habits.configOn(habit, today),
            upcoming: next == null
                ? null
                : records.habits.configOn(habit, next),
          ),
      ],
    );
  }

  /// Applies [edit] to [habitId]. [date] must be today.
  ///
  /// * A new title applies immediately and everywhere (it is cosmetic).
  /// * Target, minimum target and enabled are stored as a revision effective
  ///   from the **next** challenge day. Today keeps the configuration it
  ///   started with, so an edit can never change today's completion, XP or
  ///   Perfect Day, and past days are never touched. A second edit on the
  ///   same day replaces that pending revision.
  /// * On the arc's last day there is no next day: configuration changes are
  ///   rejected with [DomainRule.noNextChallengeDay]; renaming still works.
  Future<DayCommit<HabitEditOutcome>> editHabit({
    required String habitId,
    required HabitEdit edit,
    required LocalDate date,
  }) async {
    final session = await _trackableSession(date);
    final next = _nextChallengeDay(session, date);
    final now = _clock.now();
    return _progress.commitDay(
      sessionId: session.id,
      date: date,
      build: (day) {
        final habits = day.habits;
        final habit = habits.habit(habitId);
        if (habit == null) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
        // Edits build on the configuration that will apply next, including
        // an edit already made today.
        final configDate = next ?? date;
        final current = habits.configOn(habit, configDate);
        final edited = HabitEditRules.apply(
          habit: habit,
          current: current,
          edit: edit,
          otherEnabledCount: habits.habits
              .where(
                (h) =>
                    h.id != habitId && habits.configOn(h, configDate).enabled,
              )
              .length,
        );
        final configChanged = edited.config != current;
        if (configChanged && next == null) {
          throw const DomainFailure(
            DomainRule.noNextChallengeDay,
            'No challenge day left for a configuration change',
          );
        }
        final change = DayChange(
          revision: configChanged
              ? HabitRevision(
                  habitId: habitId,
                  effectiveFrom: next!,
                  config: edited.config,
                  createdAt: now,
                )
              : null,
          rename: edited.title == null
              ? null
              : HabitRename(habitId, edited.title!),
        );
        return (
          DayRules.settle(day, change, now: now),
          HabitEditOutcome(
            renamed: edited.title != null,
            configFrom: configChanged ? next : null,
          ),
        );
      },
    );
  }

  /// The challenge day after [date], or null if [date] is the last one.
  LocalDate? _nextChallengeDay(WinterArcSession session, LocalDate date) {
    final next = date.addDays(1);
    return session.positionOn(next) is ArcInProgress ? next : null;
  }

  /// The active session, provided [date] is today and inside the arc.
  Future<WinterArcSession> _trackableSession(LocalDate date) async {
    final session = await _startedSession();
    if (session.status == WinterArcStatus.completed) {
      throw const DomainFailure(
        DomainRule.arcCompleted,
        'Winter Arc is complete',
      );
    }
    if (date != _clock.today()) {
      throw const DomainFailure(
        DomainRule.staleDay,
        'The day changed; refresh before tracking',
      );
    }
    if (session.positionOn(date) is! ArcInProgress) {
      throw const DomainFailure(
        DomainRule.arcNotRunningToday,
        'Winter Arc is not running today',
      );
    }
    return session;
  }

  /// The latest session once it has started: active or completed.
  Future<WinterArcSession> _startedSession() async {
    final session = await _sessions.latestSession();
    if (session == null || session.status == WinterArcStatus.setup) {
      throw const DomainFailure(
        DomainRule.noActiveSession,
        'No started Winter Arc',
      );
    }
    return session;
  }
}
