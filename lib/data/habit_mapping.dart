import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/habit/habit.dart';
import '../domain/habit/habit_config.dart';

HabitsCompanion habitToCompanion(int sessionId, Habit habit) =>
    HabitsCompanion.insert(
      sessionId: sessionId,
      id: habit.id,
      title: habit.title,
      type: habit.type,
      target: habit.target,
      minimumTarget: Value(habit.minimumTarget),
      unit: Value(habit.unit),
      iconKey: habit.iconKey,
      enabled: habit.enabled,
      sortOrder: habit.sortOrder,
      createdAt: habit.createdAt,
    );

Habit habitFromRow(HabitRow row) => Habit(
  id: row.id,
  title: row.title,
  type: row.type,
  target: row.target,
  minimumTarget: row.minimumTarget,
  unit: row.unit,
  iconKey: row.iconKey,
  enabled: row.enabled,
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
);

/// The habits of [sessionId] in display order, with all their revisions.
/// Reads only that session's rows.
Future<HabitHistory> loadHabitHistory(AppDatabase db, int sessionId) async {
  final habits =
      await (db.select(db.habits)
            ..where((h) => h.sessionId.equals(sessionId))
            ..orderBy([(h) => OrderingTerm.asc(h.sortOrder)]))
          .get();
  final revisions = await (db.select(
    db.habitRevisions,
  )..where((r) => r.sessionId.equals(sessionId))).get();
  return HabitHistory(
    habits: habits.map(habitFromRow).toList(),
    revisions: [
      for (final row in revisions)
        HabitRevision(
          habitId: row.habitId,
          effectiveFrom: row.effectiveFrom,
          config: HabitConfig(
            target: row.target,
            minimumTarget: row.minimumTarget,
            enabled: row.enabled,
          ),
          createdAt: row.createdAt,
        ),
    ],
  );
}
