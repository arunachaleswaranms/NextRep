import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/local_date.dart';
import '../domain/winter_arc/arc_clock_guard.dart';
import 'persistence_guard.dart';

/// [ArcActivityRepository] over the app's database: one read-only query.
final class DriftArcActivityRepository implements ArcActivityRepository {
  const DriftArcActivityRepository(this._db);

  final AppDatabase _db;

  @override
  Future<LocalDate?> lastActivityDate(int sessionId) => guardPersistence(
    'load last activity date of session $sessionId',
    () => queryLastActivityDate(_db, sessionId),
  );
}

/// The activity tables and their date column (addendum C7). Goal
/// revisions (`habit_revisions.effective_from`) are configuration and are
/// deliberately absent.
const _activity = [
  ('daily_habit_progress_entries', 'date'),
  ('day_modes', 'date'),
  ('xp_transactions', 'date'),
  ('daily_reflections', 'date'),
  ('achievement_unlocks', 'unlocked_on'),
];

/// The latest date of any activity row of session [sessionId], or null: one
/// read-only query. Run inside a transaction it reads that transaction's
/// view (the Freeze transaction re-checks the clock guard this way).
Future<LocalDate?> queryLastActivityDate(AppDatabase db, int sessionId) async {
  // ISO dates compare chronologically as text. Table and column names are
  // the constants above; the session id is bound.
  final union = _activity
      .map((t) => 'SELECT MAX(${t.$2}) AS d FROM ${t.$1} WHERE session_id = ?')
      .join(' UNION ALL ');
  final row = await db
      .customSelect(
        'SELECT MAX(d) AS d FROM ($union)',
        variables: [
          for (var i = 0; i < _activity.length; i++)
            Variable.withInt(sessionId),
        ],
      )
      .getSingle();
  final date = row.readNullable<String>('d');
  return date == null ? null : LocalDate.parse(date);
}
