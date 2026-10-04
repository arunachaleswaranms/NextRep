import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/local_date.dart';
import '../domain/reflection/daily_reflection.dart';
import '../domain/reflection/reflection_repository.dart';
import 'persistence_guard.dart';

/// Reflections in the local database only. Failures go through
/// [guardPrivatePersistence], so neither the operation name nor the cause in
/// an error report can contain reflection text.
final class DriftReflectionRepository implements ReflectionRepository {
  const DriftReflectionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<DailyReflection>> reflectionsFor(int sessionId) =>
      guardPrivatePersistence('load reflections', () async {
        final rows =
            await (_db.select(_db.dailyReflections)
                  ..where((r) => r.sessionId.equals(sessionId))
                  ..orderBy([(r) => OrderingTerm.desc(r.date)]))
                .get();
        return rows.map(_toDomain).toList(growable: false);
      });

  @override
  Future<DailyReflection?> reflectionOn(int sessionId, LocalDate date) =>
      guardPrivatePersistence('load reflection', () async {
        final row = await (_db.select(
          _db.dailyReflections,
        )..where(_matches(sessionId, date))).getSingleOrNull();
        return row == null ? null : _toDomain(row);
      });

  @override
  Future<int> countFor(int sessionId) =>
      guardPrivatePersistence('count reflections', () async {
        final count = _db.dailyReflections.date.count();
        final row =
            await (_db.selectOnly(_db.dailyReflections)
                  ..addColumns([count])
                  ..where(_db.dailyReflections.sessionId.equals(sessionId)))
                .getSingle();
        return row.read(count) ?? 0;
      });

  @override
  Future<DailyReflection> save({
    required int sessionId,
    required LocalDate date,
    required ReflectionContent content,
    required DateTime at,
  }) => guardPrivatePersistence(
    'save reflection',
    () => _db.transaction(() async {
      final existing = await (_db.select(
        _db.dailyReflections,
      )..where(_matches(sessionId, date))).getSingleOrNull();
      final row = await _db
          .into(_db.dailyReflections)
          .insertReturning(
            DailyReflectionsCompanion.insert(
              sessionId: sessionId,
              date: date,
              mood: Value(content.mood?.key),
              win: Value(content.win),
              improvement: Value(content.improvement),
              createdAt: existing?.createdAt ?? at,
              updatedAt: at,
            ),
            mode: InsertMode.insertOrReplace,
          );
      return _toDomain(row);
    }),
  );

  Expression<bool> Function($DailyReflectionsTable) _matches(
    int sessionId,
    LocalDate date,
  ) =>
      (r) => r.sessionId.equals(sessionId) & r.date.equalsValue(date);

  DailyReflection _toDomain(ReflectionRow row) => DailyReflection(
    sessionId: row.sessionId,
    date: row.date,
    // An unknown stored key reads as "no mood" rather than failing.
    mood: Mood.fromKey(row.mood),
    win: row.win,
    improvement: row.improvement,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
