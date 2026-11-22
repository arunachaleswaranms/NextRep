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

  /// Puts the habits of session [sessionId], which must be in setup, in the
  /// order of [orderedIds]: habit `orderedIds[i]` gets `sortOrder = i`.
  ///
  /// One transaction. [orderedIds] must name every stored habit of the
  /// session exactly once: a duplicate, a missing id, an extra id, another
  /// session's habit or a habit deleted meanwhile throws
  /// `DomainRule.invalidHabitOrder`, writing nothing. Throws
  /// `DomainRule.sessionNotFound` / `DomainRule.sessionNotInSetup` for a
  /// missing or started session (a running arc's order is fixed). Only
  /// `sortOrder` changes; nothing else of any habit, and no revision.
  Future<void> reorderSetupHabits(int sessionId, List<String> orderedIds);
}
