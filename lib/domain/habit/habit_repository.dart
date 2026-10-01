import 'habit.dart';

/// Persistence boundary for a session's habit configuration.
abstract interface class HabitRepository {
  /// All habits of [sessionId] ordered by [Habit.sortOrder].
  Future<List<Habit>> habitsForSession(int sessionId);

  Future<Habit?> habit(int sessionId, String habitId);

  /// Returns false if no such habit exists.
  Future<bool> setEnabled(
    int sessionId,
    String habitId, {
    required bool enabled,
  });
}
