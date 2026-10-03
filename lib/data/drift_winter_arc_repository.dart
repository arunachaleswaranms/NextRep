import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/local_date.dart';
import '../domain/habit/habit.dart';
import '../domain/winter_arc/winter_arc_repository.dart';
import '../domain/winter_arc/winter_arc_session.dart';
import 'habit_mapping.dart';
import 'persistence_guard.dart';

final class DriftWinterArcRepository implements WinterArcRepository {
  const DriftWinterArcRepository(this._db);

  final AppDatabase _db;

  @override
  Future<WinterArcSession?> latestSession() =>
      guardPersistence('load latest session', () async {
        final row =
            await (_db.select(_db.winterArcSessions)
                  ..orderBy([(s) => OrderingTerm.desc(s.id)])
                  ..limit(1))
                .getSingleOrNull();
        return row == null ? null : _toDomain(row);
      });

  @override
  Future<WinterArcSession> createSetupSession({
    required LocalDate startDate,
    required LocalDate endDate,
    required DateTime createdAt,
    required List<Habit> habits,
  }) => guardPersistence(
    'create setup session',
    () => _db.transaction(() async {
      final row = await _db
          .into(_db.winterArcSessions)
          .insertReturning(
            WinterArcSessionsCompanion.insert(
              startDate: startDate,
              endDate: endDate,
              status: WinterArcStatus.setup,
              createdAt: createdAt,
            ),
          );
      await _db.batch((batch) {
        batch.insertAll(_db.habits, [
          for (final habit in habits) habitToCompanion(row.id, habit),
        ]);
      });
      return _toDomain(row);
    }),
  );

  @override
  Future<void> updateSession(WinterArcSession session) =>
      guardPersistence('update session ${session.id}', () async {
        final updated =
            await (_db.update(
              _db.winterArcSessions,
            )..where((s) => s.id.equals(session.id))).write(
              WinterArcSessionsCompanion(
                startDate: Value(session.startDate),
                endDate: Value(session.endDate),
                status: Value(session.status),
                startedAt: Value(session.startedAt),
              ),
            );
        if (updated != 1) {
          throw StateError('Session ${session.id} not found');
        }
      });

  WinterArcSession _toDomain(SessionRow row) => WinterArcSession(
    id: row.id,
    startDate: row.startDate,
    endDate: row.endDate,
    status: row.status,
    createdAt: row.createdAt,
    startedAt: row.startedAt,
  );
}
