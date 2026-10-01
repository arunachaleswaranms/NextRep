import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/clock.dart';
import '../core/time/local_date.dart';
import '../domain/progress/daily_habit_progress.dart';
import '../domain/progress/habit_progress_rules.dart';
import '../domain/progress/progress_repository.dart';
import 'persistence_guard.dart';

final class DriftProgressRepository implements ProgressRepository {
  const DriftProgressRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date) =>
      guardPersistence('load progress for $date', () async {
        final rows =
            await (_db.select(_db.dailyHabitProgressEntries)..where(
                  (p) =>
                      p.sessionId.equals(sessionId) & p.date.equalsValue(date),
                ))
                .get();
        return rows.map(_toDomain).toList(growable: false);
      });

  @override
  Future<ProgressTransition> applyTransition({
    required int sessionId,
    required String habitId,
    required LocalDate date,
    required ProgressTransitionBuilder build,
  }) => guardPersistence(
    'apply progress to $habitId on $date',
    // Drift runs transactions on one connection one at a time, so the
    // read-modify-write below cannot interleave with another call.
    () => _db.transaction(() async {
      final row =
          await (_db.select(_db.dailyHabitProgressEntries)..where(
                (p) =>
                    p.sessionId.equals(sessionId) &
                    p.habitId.equals(habitId) &
                    p.date.equalsValue(date),
              ))
              .getSingleOrNull();
      final current = row == null
          ? DailyHabitProgress.empty(habitId: habitId, date: date)
          : _toDomain(row);

      final transition = build(current);
      if (!transition.changed) return transition;

      final after = transition.after;
      await _db
          .into(_db.dailyHabitProgressEntries)
          .insertOnConflictUpdate(
            DailyHabitProgressEntriesCompanion.insert(
              sessionId: sessionId,
              habitId: habitId,
              date: date,
              currentValue: after.currentValue,
              completed: after.completed,
              completedAt: Value(after.completedAt),
              updatedAt: _clock.now(),
            ),
          );

      switch (transition.xpEffect) {
        case GrantXp(:final award):
          // The unique (session_id, source_key) index makes this a no-op if
          // the award already exists.
          await _db
              .into(_db.xpTransactions)
              .insert(
                XpTransactionsCompanion.insert(
                  sessionId: sessionId,
                  sourceKey: award.sourceKey,
                  reason: award.reason,
                  amount: award.amount,
                  habitId: Value(award.habitId),
                  date: award.date,
                  createdAt: award.awardedAt,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        case RevokeXp(:final sourceKey):
          await (_db.delete(_db.xpTransactions)..where(
                (x) =>
                    x.sessionId.equals(sessionId) &
                    x.sourceKey.equals(sourceKey),
              ))
              .go();
        case NoXpChange():
          break;
      }
      return transition;
    }),
  );

  @override
  Future<int> totalXp(int sessionId) =>
      guardPersistence('load total XP', () async {
        final sum = _db.xpTransactions.amount.sum();
        final row =
            await (_db.selectOnly(_db.xpTransactions)
                  ..addColumns([sum])
                  ..where(_db.xpTransactions.sessionId.equals(sessionId)))
                .getSingle();
        return row.read(sum) ?? 0;
      });

  DailyHabitProgress _toDomain(HabitProgressRow row) => DailyHabitProgress(
    habitId: row.habitId,
    date: row.date,
    currentValue: row.currentValue,
    completed: row.completed,
    completedAt: row.completedAt,
  );
}
