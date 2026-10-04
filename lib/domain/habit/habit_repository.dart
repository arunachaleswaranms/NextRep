import 'habit.dart';
import 'habit_config.dart';

/// Persistence boundary for a session's habit configuration.
abstract interface class HabitRepository {
  /// All habits of [sessionId] ordered by [Habit.sortOrder].
  Future<List<Habit>> habitsForSession(int sessionId);

  /// The habits of [sessionId] with every dated configuration change.
  Future<HabitHistory> historyForSession(int sessionId);

  Future<Habit?> habit(int sessionId, String habitId);

  /// Returns false if no such habit exists.
  Future<bool> setEnabled(
    int sessionId,
    String habitId, {
    required bool enabled,
  });

  /// Adds [habit] to session [sessionId], which must be in setup.
  ///
  /// The session's status is checked in the same transaction: throws
  /// `DomainRule.sessionNotInSetup`, writing nothing, if it has started.
  Future<void> addSetupHabit(int sessionId, Habit habit);

  /// Replaces the baseline of [habit] (same id) in session [sessionId],
  /// which must be in setup. No revision is written: before the start there
  /// is no history to protect. Returns false if there is no such habit.
  Future<bool> updateSetupHabit(int sessionId, Habit habit);

  /// Deletes habit [habitId] of session [sessionId], which must be in
  /// setup. Returns false if there is no such habit.
  Future<bool> deleteSetupHabit(int sessionId, String habitId);
}
