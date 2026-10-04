import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/errors/app_failure.dart';
import '../domain/habit/habit.dart';
import '../domain/habit/habit_config.dart';
import '../domain/habit/habit_repository.dart';
import '../domain/winter_arc/winter_arc_session.dart';
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
  Future<HabitHistory> historyForSession(int sessionId) => guardPersistence(
    'load habit history',
    // One transaction so habits and revisions are a consistent snapshot.
    () => _db.transaction(() => loadHabitHistory(_db, sessionId)),
  );

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

  @override
  // Titles are the user's own words, so errors never quote bound values.
  Future<void> addSetupHabit(int sessionId, Habit habit) =>
      guardPrivatePersistence(
        'add setup habit',
        () => _db.transaction(() async {
          await _requireSetup(sessionId);
          await _db.into(_db.habits).insert(habitToCompanion(sessionId, habit));
        }),
      );

  @override
  Future<bool> updateSetupHabit(int sessionId, Habit habit) =>
      guardPrivatePersistence(
        'update setup habit ${habit.id}',
        () => _db.transaction(() async {
          await _requireSetup(sessionId);
          final updated =
              await (_db.update(
                _db.habits,
              )..where(_matches(sessionId, habit.id))).write(
                HabitsCompanion(
                  title: Value(habit.title),
                  target: Value(habit.target),
                  minimumTarget: Value(habit.minimumTarget),
                  unit: Value(habit.unit),
                  iconKey: Value(habit.iconKey),
                  enabled: Value(habit.enabled),
                ),
              );
          return updated == 1;
        }),
      );

  @override
  Future<bool> deleteSetupHabit(int sessionId, String habitId) =>
      guardPersistence(
        'delete setup habit $habitId',
        () => _db.transaction(() async {
          await _requireSetup(sessionId);
          final deleted = await (_db.delete(
            _db.habits,
          )..where(_matches(sessionId, habitId))).go();
          return deleted == 1;
        }),
      );

  /// Throws unless session [sessionId] exists and is still in setup.
  Future<void> _requireSetup(int sessionId) async {
    final row = await (_db.select(
      _db.winterArcSessions,
    )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
    if (row == null) {
      throw DomainFailure(DomainRule.sessionNotFound, 'No session $sessionId');
    }
    if (row.status != WinterArcStatus.setup) {
      throw DomainFailure(
        DomainRule.sessionNotInSetup,
        'Habits of session $sessionId can no longer be added or removed',
      );
    }
  }

  Expression<bool> Function($HabitsTable) _matches(
    int sessionId,
    String habitId,
  ) =>
      (h) => h.sessionId.equals(sessionId) & h.id.equals(habitId);
}
