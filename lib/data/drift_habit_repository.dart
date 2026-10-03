import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/habit/habit.dart';
import '../domain/habit/habit_repository.dart';
import 'habit_mapping.dart';
import 'persistence_guard.dart';

final class DriftHabitRepository implements HabitRepository {
  const DriftHabitRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Habit>> habitsForSession(int sessionId) =>
      guardPersistence('load habits', () async {
        final rows =
            await (_db.select(_db.habits)
                  ..where((h) => h.sessionId.equals(sessionId))
                  ..orderBy([(h) => OrderingTerm.asc(h.sortOrder)]))
                .get();
        return rows.map(habitFromRow).toList(growable: false);
      });

  @override
  Future<Habit?> habit(int sessionId, String habitId) =>
      guardPersistence('load habit $habitId', () async {
        final row = await (_db.select(
          _db.habits,
        )..where(_matches(sessionId, habitId))).getSingleOrNull();
        return row == null ? null : habitFromRow(row);
      });

  @override
  Future<bool> setEnabled(
    int sessionId,
    String habitId, {
    required bool enabled,
  }) => guardPersistence('set habit $habitId enabled=$enabled', () async {
    final updated =
        await (_db.update(_db.habits)..where(_matches(sessionId, habitId)))
            .write(HabitsCompanion(enabled: Value(enabled)));
    return updated == 1;
  });

  Expression<bool> Function($HabitsTable) _matches(
    int sessionId,
    String habitId,
  ) =>
      (h) => h.sessionId.equals(sessionId) & h.id.equals(habitId);
}
