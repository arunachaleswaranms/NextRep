import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/errors/app_failure.dart';
import '../core/time/local_date.dart';
import '../domain/habit/habit.dart';
import '../domain/winter_arc/winter_arc_repository.dart';
import '../domain/winter_arc/winter_arc_session.dart';
import 'habit_mapping.dart';
import 'persistence_guard.dart';

final class DriftWinterArcRepository implements WinterArcRepository {
  const DriftWinterArcRepository(this._db);

  final AppDatabase _db;

  static const _unfinished = [WinterArcStatus.setup, WinterArcStatus.active];

  @override
  Future<WinterArcSession?> latestSession() =>
      guardPersistence('load latest session', () => _newest());

  @override
  Future<WinterArcSession?> currentSession() => guardPersistence(
    'load current session',
    () => _newest(statuses: _unfinished),
  );

  @override
  Future<WinterArcSession?> latestCompletedSession() => guardPersistence(
    'load latest completed session',
    () => _newest(statuses: [WinterArcStatus.completed]),
  );

  @override
  Future<WinterArcSession?> sessionById(int id) =>
      guardPersistence('load session $id', () async {
        final row = await (_db.select(
          _db.winterArcSessions,
        )..where((s) => s.id.equals(id))).getSingleOrNull();
        return row == null ? null : _toDomain(row);
      });

  @override
  Future<List<WinterArcSession>> listSessions() =>
      guardPersistence('list sessions', () async {
        final rows = await (_db.select(
          _db.winterArcSessions,
        )..orderBy([(s) => OrderingTerm.desc(s.id)])).get();
        return rows.map(_toDomain).toList(growable: false);
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
      // Checked inside the transaction so no other session can be created
      // in between; the single_open_session index backs this up.
      if (await _newest(statuses: _unfinished) != null) {
        throw const DomainFailure(
          DomainRule.arcInProgress,
          'An arc is already in setup or running',
        );
      }
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

  @override
  Future<void> deleteSession(int id, {required WinterArcStatus expected}) =>
      // Reflections go with the arc, so errors must not quote row values.
      guardPrivatePersistence(
        'delete session $id',
        () => _db.transaction(() async {
          final row = await (_db.select(
            _db.winterArcSessions,
          )..where((s) => s.id.equals(id))).getSingleOrNull();
          if (row == null) {
            throw DomainFailure(DomainRule.sessionNotFound, 'No session $id');
          }
          if (row.status != expected) {
            throw DomainFailure(
              expected == WinterArcStatus.setup
                  ? DomainRule.sessionNotInSetup
                  : DomainRule.arcNotDeletable,
              'Session $id is ${row.status.name}, not ${expected.name}',
            );
          }
          // Habits, modes, XP, unlocks and reflections reference the
          // session, and progress and revisions reference its habits, all
          // with ON DELETE CASCADE.
          await (_db.delete(
            _db.winterArcSessions,
          )..where((s) => s.id.equals(id))).go();
          for (final table in [
            'habits',
            'habit_revisions',
            'daily_habit_progress_entries',
            'day_modes',
            'xp_transactions',
            'achievement_unlocks',
            'daily_reflections',
          ]) {
            final left = await _db
                .customSelect(
                  'SELECT COUNT(*) AS c FROM $table WHERE session_id = ?',
                  variables: [Variable.withInt(id)],
                )
                .getSingle();
            if (left.read<int>('c') != 0) {
              // Rolls the deletion back rather than leave orphans.
              throw StateError('Session $id left rows in $table');
            }
          }
        }),
      );

  /// The most recently created session, optionally limited to [statuses].
  Future<WinterArcSession?> _newest({List<WinterArcStatus>? statuses}) async {
    final query = _db.select(_db.winterArcSessions)
      ..orderBy([(s) => OrderingTerm.desc(s.id)])
      ..limit(1);
    if (statuses != null) {
      query.where((s) => s.status.isIn(statuses.map((v) => v.name)));
    }
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  WinterArcSession _toDomain(SessionRow row) => WinterArcSession(
    id: row.id,
    startDate: row.startDate,
    endDate: row.endDate,
    status: row.status,
    createdAt: row.createdAt,
    startedAt: row.startedAt,
  );
}
