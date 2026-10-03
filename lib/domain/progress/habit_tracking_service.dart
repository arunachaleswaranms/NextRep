import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../habit/habit_repository.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'daily_habit_progress.dart';
import 'day_summary.dart';
import 'habit_progress_rules.dart';
import 'progress_repository.dart';

/// Use cases for tracking habits on the current challenge day.
final class HabitTrackingService {
  const HabitTrackingService({
    required this._sessions,
    required this._habits,
    required this._progress,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final HabitRepository _habits;
  final ProgressRepository _progress;
  final Clock _clock;

  /// Builds the summary of today's progress for the active session.
  Future<DaySummary> today() async {
    final session = await _activeSession();
    final date = _clock.today();
    final habits = await _habits.habitsForSession(session.id);
    final progressById = {
      for (final p in await _progress.progressOn(session.id, date))
        p.habitId: p,
    };
    return DaySummary(
      session: session,
      date: date,
      entries: [
        for (final habit in habits.where((h) => h.enabled))
          HabitDayEntry(
            habit: habit,
            progress:
                progressById[habit.id] ??
                DailyHabitProgress.empty(habitId: habit.id, date: date),
          ),
      ],
      totalXp: await _progress.totalXp(session.id),
    );
  }

  /// Validates and applies [action] to [habitId] for [date].
  ///
  /// [date] is the day the user is looking at. If the calendar day has rolled
  /// over since, the action is rejected with [DomainRule.staleDay] rather than
  /// silently applied to a different day.
  Future<ProgressTransition> perform({
    required String habitId,
    required HabitAction action,
    required LocalDate date,
  }) async {
    final session = await _activeSession();
    final today = _clock.today();
    if (date != today) {
      throw const DomainFailure(
        DomainRule.staleDay,
        'The day changed; refresh before tracking',
      );
    }
    if (session.positionOn(today) is! ArcInProgress) {
      throw const DomainFailure(
        DomainRule.arcNotRunningToday,
        'Winter Arc is not running today',
      );
    }

    final habit = await _habits.habit(session.id, habitId);
    if (habit == null) {
      throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
    }
    if (!habit.enabled) {
      throw DomainFailure(DomainRule.habitDisabled, '"$habitId" is disabled');
    }

    return _progress.applyTransition(
      sessionId: session.id,
      habitId: habitId,
      date: today,
      build: (current) => HabitProgressRules.apply(
        habit: habit,
        current: current,
        action: action,
        now: _clock.now(),
      ),
    );
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
