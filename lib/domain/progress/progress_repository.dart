import '../../core/time/local_date.dart';
import 'arc_history.dart';
import 'daily_habit_progress.dart';
import 'day_rules.dart';

/// Computes the settlement for a day from its freshly read state, plus a
/// value to hand back to the caller.
typedef DayCommitBuilder<T> = (DaySettlement, T) Function(DayContext context);

/// The persisted result of [ProgressRepository.commitDay].
final class DayCommit<T> {
  const DayCommit({
    required this.value,
    required this.settlement,
    required this.xpBefore,
    required this.xpAfter,
  });

  final T value;

  /// What was written (empty if nothing changed) and the resulting day.
  final DaySettlement settlement;

  /// Session XP total before and after the commit, read in the same
  /// transaction.
  final int xpBefore;
  final int xpAfter;
}

/// Persistence boundary for tracking: daily progress, day modes, habit
/// revisions and the XP ledger.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class ProgressRepository {
  /// A consistent snapshot of everything history is derived from.
  Future<ArcRecords> loadArc(int sessionId);

  /// Atomically reads [date]'s [DayContext], passes it to [build], and
  /// applies the returned [DaySettlement] in the same transaction.
  /// Concurrent calls are serialised, so each one observes the result of the
  /// previous one.
  ///
  /// If [build] throws, nothing is written and the error propagates.
  Future<DayCommit<T>> commitDay<T>({
    required int sessionId,
    required LocalDate date,
    required DayCommitBuilder<T> build,
  });

  /// Progress rows recorded for [date]. Habits with no row have no progress.
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date);

  /// Sum of all XP ledger entries for [sessionId].
  Future<int> totalXp(int sessionId);
}
