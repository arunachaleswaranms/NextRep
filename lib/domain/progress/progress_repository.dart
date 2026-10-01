import '../../core/time/local_date.dart';
import 'daily_habit_progress.dart';
import 'habit_progress_rules.dart';

/// Computes a transition from the freshly read current progress.
typedef ProgressTransitionBuilder = ProgressTransition Function(
  DailyHabitProgress current,
);

/// Persistence boundary for daily progress and the XP ledger.
abstract interface class ProgressRepository {
  /// Progress rows recorded for [date]. Habits with no row have no progress.
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date);

  /// Atomically reads the current progress of [habitId] on [date], passes it
  /// to [build], and persists the resulting progress and XP effect in the same
  /// transaction. Concurrent calls are serialised, so each one observes the
  /// result of the previous one.
  ///
  /// If [build] throws, nothing is written and the error propagates.
  Future<ProgressTransition> applyTransition({
    required int sessionId,
    required String habitId,
    required LocalDate date,
    required ProgressTransitionBuilder build,
  });

  /// Sum of all XP ledger entries for [sessionId].
  Future<int> totalXp(int sessionId);
}
