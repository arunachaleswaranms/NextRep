import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../habit/habit.dart';
import '../habit/habit_repository.dart';
import '../habit/starter_habits.dart';
import 'winter_arc_repository.dart';
import 'winter_arc_session.dart';

/// Use cases for configuring and starting a Winter Arc.
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

  Future<WinterArcSession?> currentSession() => _sessions.latestSession();

  /// Ends onboarding by creating a session in setup with the starter habits.
  ///
  /// Idempotent: if a session already exists it is returned unchanged.
  Future<WinterArcSession> beginSetup() => _mutations.run(() async {
    final existing = await _sessions.latestSession();
    if (existing != null) return existing;

    final now = _clock.now();
    final start = _clock.today();
    return _sessions.createSetupSession(
      startDate: start,
      endDate: WinterArcRules.endDateFor(start),
      createdAt: now,
      habits: StarterHabits.seed(now),
    );
  });

  Future<List<Habit>> setupHabits() async {
    final session = await _requireSession(WinterArcStatus.setup);
    return _habits.habitsForSession(session.id);
  }

  Future<void> setHabitEnabled(String habitId, {required bool enabled}) =>
      _mutations.run(() async {
        final session = await _requireSession(WinterArcStatus.setup);
        final found = await _habits.setEnabled(
          session.id,
          habitId,
          enabled: enabled,
        );
        if (!found) {
          throw DomainFailure(DomainRule.habitNotFound, 'No habit "$habitId"');
        }
      });

  /// Starts the arc today. Day 1 is the current local date.
  ///
  /// Idempotent: calling it on an already active session returns that session.
  Future<WinterArcSession> startWinterArc() => _mutations.run(() async {
    final session = await _sessions.latestSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session to start');
    }
    if (session.status == WinterArcStatus.active) return session;
    if (session.status != WinterArcStatus.setup) {
      throw DomainFailure(
        DomainRule.sessionNotInSetup,
        'Cannot start a session in ${session.status.name}',
      );
    }

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

  Future<WinterArcSession> _requireSession(WinterArcStatus status) async {
    final session = await _sessions.latestSession();
    if (session == null) {
      throw const DomainFailure(DomainRule.noSession, 'No session exists');
    }
    if (session.status != status) {
      throw DomainFailure(
        DomainRule.sessionNotInSetup,
        'Expected ${status.name} session, found ${session.status.name}',
      );
    }
    return session;
  }
}
