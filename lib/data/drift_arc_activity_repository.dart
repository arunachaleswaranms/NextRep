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

/// Every instant column the app stores for an Arc (all Arc-owned tables),
/// each with the column that ties it to the session. Instants are stored
/// as Unix seconds (Drift's default), so they compare as absolute times,
/// whatever the device's time zone.
const _instants = [
  ('winter_arc_sessions', 'created_at', 'id'),
  ('winter_arc_sessions', 'started_at', 'id'),
  ('arc_freezes', 'requested_at', 'session_id'),
  ('arc_freezes', 'resumed_at', 'session_id'),
  ('habits', 'created_at', 'session_id'),
  ('habit_revisions', 'created_at', 'session_id'),
  ('daily_habit_progress_entries', 'completed_at', 'session_id'),
  ('daily_habit_progress_entries', 'updated_at', 'session_id'),
  ('day_modes', 'changed_at', 'session_id'),
  ('xp_transactions', 'created_at', 'session_id'),
  ('achievement_unlocks', 'unlocked_at', 'session_id'),
  ('daily_reflections', 'created_at', 'session_id'),
  ('daily_reflections', 'updated_at', 'session_id'),
];

/// The latest instant at which anything of session [sessionId] was
/// written (its creation and start, a freeze request or resume, a habit,
/// a goal revision, progress, a day mode, XP, an unlock, a reflection), or
/// null. A clock reading earlier than this proves the device clock moved
/// back after that write. Read-only; inside a transaction it reads that
/// transaction's view. App-level tables (reminders, Focus Guard, sound
/// settings) are deliberately not consulted: Arc lifecycle rules stay
/// independent of them (addendum AD9).
Future<DateTime?> queryLatestRecordedInstant(
  AppDatabase db,
  int sessionId,
) async {
  final union = _instants
      .map((t) => 'SELECT MAX(${t.$2}) AS i FROM ${t.$1} WHERE ${t.$3} = ?')
      .join(' UNION ALL ');
  final row = await db
      .customSelect(
        'SELECT MAX(i) AS i FROM ($union)',
        variables: [
          for (var i = 0; i < _instants.length; i++)
            Variable.withInt(sessionId),
        ],
      )
      .getSingle();
  final seconds = row.readNullable<int>('i');
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
