import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/habit/habit.dart';
import '../../domain/progress/day_mode.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../domain/xp/xp.dart';
import '../time/local_date.dart';
import 'converters.dart';
import 'schema_versions.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The app's single local SQLite database.
///
/// Schema changes must bump [schemaVersion], add a step to [migration], and
/// add a schema snapshot (see docs/PHASE_2.md, "Schema evolution").
@DriftDatabase(
  tables: [
    WinterArcSessions,
    Habits,
    DailyHabitProgressEntries,
    XpTransactions,
    HabitRevisions,
    DayModes,
    AchievementUnlocks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database file.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'nextrep'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Each step runs against the frozen shape of its target version (see
    // schema_versions.dart), so old steps keep working as the schema grows.
    onUpgrade: stepByStep(from1To2: _from1To2, from2To3: _from2To3),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// v1 → v2: Minimum Day targets, habit revisions, day modes.
  ///
  /// Additive only: no existing row is rewritten except to fill the new
  /// `minimum_target` column, so sessions, habits, progress and the XP ledger
  /// survive unchanged. Values below are frozen as of schema v2 and must not
  /// follow later changes to the domain constants.
  static Future<void> _from1To2(Migrator m, Schema2 schema) async {
    await m.addColumn(schema.habits, schema.habits.minimumTarget);
    // Starter catalogue minimums. Unknown habits keep their full target.
    await m.database.customStatement('''
      UPDATE habits SET minimum_target = MIN(target, CASE id
        WHEN 'workout' THEN 10
        WHEN 'water' THEN 3
        WHEN 'learning' THEN 5
        WHEN 'english' THEN 5
        WHEN 'meditation' THEN 5
        ELSE target END)
    ''');
    await m.createTable(schema.habitRevisions);
    await m.createTable(schema.dayModes);

    // v1 had no revisions and no Minimum Days, so a stored date was perfect
    // iff every habit enabled in the session has a completed row for it.
    // Credit those dates the Perfect Day bonus introduced in v2, keyed like
    // XpRules.perfectDayKey, so every qualifying date has exactly one bonus.
    const perfectDayBonus = 30;
    await m.database.customStatement('''
      INSERT OR IGNORE INTO xp_transactions
        (session_id, source_key, reason, amount, habit_id, date, created_at)
      SELECT p.session_id, 'perfect_day:' || p.date, 'perfectDay',
             $perfectDayBonus, NULL, p.date,
             COALESCE(MAX(p.completed_at), MAX(p.updated_at))
      FROM daily_habit_progress_entries p
      JOIN habits h ON h.session_id = p.session_id AND h.id = p.habit_id
      JOIN winter_arc_sessions s ON s.id = p.session_id
      WHERE h.enabled = 1 AND p.completed = 1
        AND p.date BETWEEN s.start_date AND s.end_date
      GROUP BY p.session_id, p.date
      HAVING COUNT(*) = (
        SELECT COUNT(*) FROM habits e
        WHERE e.session_id = p.session_id AND e.enabled = 1)
    ''');
  }

  /// v2 → v3: achievement unlocks.
  ///
  /// Additive only: one new, empty table. Nothing is backfilled here; the
  /// app's achievement reconciliation derives what the existing history has
  /// earned and stores it on the next launch.
  static Future<void> _from2To3(Migrator m, Schema3 schema) async {
    await m.createTable(schema.achievementUnlocks);
  }
}
