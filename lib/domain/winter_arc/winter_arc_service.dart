import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../habit/habit.dart';
import '../habit/habit_config.dart';
import '../habit/habit_repository.dart';
import '../habit/starter_habits.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Which habits a new arc starts from.
enum NewArcBaseline {
  /// The starter catalogue, exactly as on a first install.
  fresh,

  /// The final configuration of the most recently completed arc.
  reuseLast,
}

/// Use cases for configuring and starting a Winter Arc, including every arc
/// after the first.
///
/// Mutations run through a [SerialQueue] so that concurrent calls (e.g. a
/// double tap on "Let's Begin") observe each other's results instead of
/// racing, which keeps [beginSetup] and [startWinterArc] idempotent.
final class WinterArcService {
  WinterArcService({
    required this._sessions,
    required this._habits,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final HabitRepository _habits;
  final Clock _clock;
  final _mutations = SerialQueue();

  /// The unfinished arc (setup or active), or null.
  Future<WinterArcSession?> currentSession() => _sessions.currentSession();

  /// Ends first-time onboarding by creating a session in setup with the
  /// starter habits.
  ///
  /// Idempotent: if an unfinished session exists it is returned unchanged.
  Future<WinterArcSession> beginSetup() => _mutations.run(() async {
    final existing = await _sessions.currentSession();
    if (existing != null) return existing;
    return _createSetup(StarterHabits.seed(_clock.now()));
  });

  /// Creates the setup session of another arc, for a user who has finished
  /// one. The start date stays provisional until [startWinterArc].
  ///
  /// [NewArcBaseline.reuseLast] copies each habit's final effective
  /// configuration (see [reusableHabits]); nothing else carries over:
  /// progress, XP, streaks, day modes, revisions, achievements and
  /// reflections stay with the arc that earned them, which is never written.
  ///
  /// Throws [DomainRule.arcInProgress] if an arc is already in setup or
  /// running, and [DomainRule.noCompletedArc] when reusing without a
  /// completed arc.
  Future<WinterArcSession> startNewArc(NewArcBaseline baseline) =>
      _mutations.run(() async {
        if (await _sessions.currentSession() != null) {
          throw const DomainFailure(
            DomainRule.arcInProgress,
            'An arc is already in setup or running',
          );
        }
        final now = _clock.now();
        final habits = switch (baseline) {
          NewArcBaseline.fresh => StarterHabits.seed(now),
          NewArcBaseline.reuseLast => await _reusable(createdAt: now),
        };
        if (habits == null) {
          throw const DomainFailure(
            DomainRule.noCompletedArc,
            'No completed arc to reuse',
          );
        }
        return _createSetup(habits);
      });

  /// The habits "Reuse last setup" would start with, or null when no arc
  /// has been completed.
  Future<List<Habit>?> reusableHabits() => _reusable(createdAt: _clock.now());

  Future<List<Habit>> setupHabits() async {
    final session = await _requireSetup();
    return _habits.habitsForSession(session.id);
  }

  Future<void> setHabitEnabled(String habitId, {required bool enabled}) =>
      _mutations.run(() async {
        final session = await _requireSetup();
        final found = await _habits.setEnabled(
          session.id,
          habitId,
          enabled: enabled,
        );
        if (!found) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
      });

  /// Starts the current arc today. Day 1 is the current local date.
  ///
  /// Idempotent: calling it on an already active session returns that session.
  Future<WinterArcSession> startWinterArc() => _mutations.run(() async {
    final session = await _sessions.currentSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session to start');
    }
    if (session.status == WinterArcStatus.active) return session;

    final habits = await _habits.habitsForSession(session.id);
    if (!habits.any((h) => h.enabled)) {
      throw const DomainFailure(
        DomainRule.noHabitsSelected,
        'Select at least one habit to start',
      );
    }

    final start = _clock.today();
    final started = session.copyWith(
      startDate: start,
      endDate: WinterArcRules.endDateFor(start),
      status: WinterArcStatus.active,
      startedAt: _clock.now(),
    );
    await _sessions.updateSession(started);
    return started;
  });

  Future<WinterArcSession> _createSetup(List<Habit> habits) {
    final start = _clock.today();
    return _sessions.createSetupSession(
      startDate: start,
      endDate: WinterArcRules.endDateFor(start),
      createdAt: _clock.now(),
      habits: habits,
    );
  }

  /// Each habit of the latest completed arc as it stood on its last day:
  /// the current title and the configuration in effect on the end date
  /// (from its revision history, not the original baseline). These become
  /// the new arc's baseline.
  Future<List<Habit>?> _reusable({required DateTime createdAt}) async {
    final last = await _sessions.latestCompletedSession();
    if (last == null) return null;
    final history = await _habits.historyForSession(last.id);
    return [
      for (final habit in history.habits)
        _withConfig(habit, history.configOn(habit, last.endDate), createdAt),
    ];
  }

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

  Future<WinterArcSession> _requireSetup() async {
    final session = await _sessions.currentSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session exists');
    }
    if (session.status != WinterArcStatus.setup) {
      throw DomainFailure(
        DomainRule.sessionNotInSetup,
        'Expected setup session, found ${session.status.name}',
      );
    }
    return session;
  }
}
