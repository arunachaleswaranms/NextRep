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

/// A habit with the configuration in effect on [date].
final class HabitSetting {
  const HabitSetting({required this.habit, required this.config});

  final Habit habit;
  final HabitConfig config;
}

/// Habit configuration as it applies today, for editing.
final class HabitSettings {
  const HabitSettings({
    required this.date,
    required this.habits,
    required this.editable,
  });

  final LocalDate date;
  final List<HabitSetting> habits;

  /// False when the arc is not running today.
  final bool editable;
}

/// Use cases of an active Winter Arc: tracking the current day, Minimum Day,
/// habit editing, and the derived history (Today, Journey).
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

  /// Builds the summary of today's progress for the active session.
  Future<DaySummary> today() async => DaySummary.fromHistory(await _history());

  /// Builds the Journey of the active session.
  Future<JourneyOverview> journey() async =>
      JourneyOverview.fromHistory(await _history());

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

  /// The active session's habits with today's configuration.
  Future<HabitSettings> habitSettings() async {
    final session = await _activeSession();
    final today = _clock.today();
    final records = await _progress.loadArc(session.id);
    return HabitSettings(
      date: today,
      editable: session.positionOn(today) is ArcInProgress,
      habits: [
        for (final habit in records.habits.habits)
          HabitSetting(
            habit: habit,
            config: records.habits.configOn(habit, today),
          ),
      ],
    );
  }

  /// Applies [edit] to [habitId] from [date] (which must be today) onwards.
  ///
  /// Target and enabled changes are stored as a revision effective from
  /// today, so earlier days keep the configuration they had. Today's
  /// completion and XP are reconciled against the new configuration in the
  /// same transaction. Renaming applies to every day.
  Future<DayCommit<void>> editHabit({
    required String habitId,
    required HabitEdit edit,
    required LocalDate date,
  }) async {
    final session = await _trackableSession(date);
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
        final current = habits.configOn(habit, date);
        final edited = HabitEditRules.apply(
          habit: habit,
          current: current,
          edit: edit,
          otherEnabledCount: habits.habits
              .where((h) => h.id != habitId && habits.configOn(h, date).enabled)
              .length,
        );
        final change = DayChange(
          revision: edited.config == current
              ? null
              : HabitRevision(
                  habitId: habitId,
                  effectiveFrom: date,
                  config: edited.config,
                  createdAt: now,
                ),
          rename: edited.title == null
              ? null
              : HabitRename(habitId, edited.title!),
        );
        return (DayRules.settle(day, change, now: now), null);
      },
    );
  }

  Future<ArcHistory> _history() async {
    final session = await _activeSession();
    final records = await _progress.loadArc(session.id);
    return ArcHistory(
      session: session,
      records: records,
      today: _clock.today(),
    );
  }

  /// The active session, provided [date] is today and inside the arc.
  Future<WinterArcSession> _trackableSession(LocalDate date) async {
    final session = await _activeSession();
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

  Future<WinterArcSession> _activeSession() async {
    final session = await _sessions.latestSession();
    if (session == null || session.status != WinterArcStatus.active) {
      throw const DomainFailure(
        DomainRule.noActiveSession,
        'No active Winter Arc',
      );
    }
    return session;
  }
}
