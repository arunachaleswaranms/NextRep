import '../../core/time/local_date.dart';
import '../habit/habit.dart';
import 'winter_arc_session.dart';

/// Persistence boundary for Winter Arc sessions.
///
/// Implementations throw `PersistenceFailure` on storage errors.
abstract interface class WinterArcRepository {
  /// The most recently created session, or null if none exists.
  Future<WinterArcSession?> latestSession();

  /// Atomically creates a session in [WinterArcStatus.setup] together with
  /// its initial habit configuration.
  Future<WinterArcSession> createSetupSession({
    required LocalDate startDate,
    required LocalDate endDate,
    required DateTime createdAt,
    required List<Habit> habits,
  });

  /// Persists [session]'s status, dates and start timestamp.
  Future<void> updateSession(WinterArcSession session);
}
