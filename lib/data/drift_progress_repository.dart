import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../core/time/clock.dart';
import '../core/time/local_date.dart';
import '../domain/habit/habit_config.dart';
import '../domain/progress/arc_history.dart';
import '../domain/progress/daily_habit_progress.dart';
import '../domain/progress/day_mode.dart';
import '../domain/progress/day_rules.dart';
import '../domain/progress/progress_repository.dart';
import 'habit_mapping.dart';
import 'persistence_guard.dart';

final class DriftProgressRepository implements ProgressRepository {
  const DriftProgressRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<ArcRecords> loadArc(int sessionId) => guardPersistence(
    'load arc $sessionId',
    // One transaction so the snapshot is consistent.
    () => _db.transaction(() async {
      final progress = await (_db.select(
        _db.dailyHabitProgressEntries,
      )..where((p) => p.sessionId.equals(sessionId))).get();
      final modes = await (_db.select(
        _db.dayModes,
      )..where((d) => d.sessionId.equals(sessionId))).get();

      final amount = _db.xpTransactions.amount.sum();
      final date = _db.xpTransactions.date;
      final xpRows =
          await (_db.selectOnly(_db.xpTransactions)
                ..addColumns([date, amount])
                ..where(_db.xpTransactions.sessionId.equals(sessionId))
                ..groupBy([date]))
              .get();
      final xpByDate = {
        for (final row in xpRows)
          LocalDate.parse(row.read(date)!): row.read(amount) ?? 0,
      };

      return ArcRecords(
        habits: await _habitHistory(sessionId),
        progress: progress.map(_toDomain),
        modes: {for (final row in modes) row.date: row.mode},
        xpByDate: xpByDate,
        totalXp: xpByDate.values.fold(0, (sum, xp) => sum + xp),
      );
    }),
  );

  @override
  Future<DayCommit<T>> commitDay<T>({
    required int sessionId,
    required LocalDate date,
    required DayCommitBuilder<T> build,
  }) => guardPersistence(
    'commit $date',
    // Drift runs transactions on one connection one at a time, so the
    // read-modify-write below cannot interleave with another commit.
    () => _db.transaction(() async {
      final context = await _dayContext(sessionId, date);
      final xpBefore = await _totalXp(sessionId);
      final (settlement, value) = build(context);
      if (!settlement.hasWrites) {
        return DayCommit(
          value: value,
          settlement: settlement,
          xpBefore: xpBefore,
          xpAfter: xpBefore,
        );
      }
      await _apply(sessionId, settlement);
      return DayCommit(
        value: value,
        settlement: settlement,
        xpBefore: xpBefore,
        xpAfter: await _totalXp(sessionId),
      );
    }),
  );

  @override
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date) =>
      guardPersistence('load progress for $date', () async {
        final rows = await _progressRows(sessionId, date);
        return rows.map(_toDomain).toList(growable: false);
      });

  @override
  Future<int> totalXp(int sessionId) =>
      guardPersistence('load total XP', () => _totalXp(sessionId));

  Future<DayContext> _dayContext(int sessionId, LocalDate date) async {
    final mode =
        await (_db.select(_db.dayModes)..where(
              (d) => d.sessionId.equals(sessionId) & d.date.equalsValue(date),
            ))
            .getSingleOrNull();
    final ledger =
        await (_db.select(_db.xpTransactions)..where(
              (x) =>
                  x.sessionId.equals(sessionId) &
                  x.date.equalsValue(date) &
                  x.reason.isIn(DayRules.managedReasons.map((r) => r.name)),
            ))
            .get();
    return DayContext(
      date: date,
      habits: await _habitHistory(sessionId),
      mode: mode?.mode ?? DayMode.normal,
      progress: (await _progressRows(sessionId, date)).map(_toDomain),
      ledger: [
        for (final row in ledger)
          XpLedgerEntry(
            sourceKey: row.sourceKey,
            reason: row.reason,
            amount: row.amount,
            habitId: row.habitId,
          ),
      ],
    );
  }

  Future<void> _apply(int sessionId, DaySettlement settlement) async {
    final date = settlement.date;
    final now = _clock.now();

    if (settlement.rename case final rename?) {
      final updated =
          await (_db.update(_db.habits)..where(
                (h) =>
                    h.sessionId.equals(sessionId) & h.id.equals(rename.habitId),
              ))
              .write(HabitsCompanion(title: Value(rename.title)));
      if (updated != 1) throw StateError('Habit ${rename.habitId} not found');
    }
    if (settlement.revision case final revision?) {
      await _db
          .into(_db.habitRevisions)
          .insertOnConflictUpdate(
            HabitRevisionsCompanion.insert(
              sessionId: sessionId,
              habitId: revision.habitId,
              effectiveFrom: revision.effectiveFrom,
              target: revision.config.target,
              minimumTarget: revision.config.minimumTarget,
              enabled: revision.config.enabled,
              createdAt: revision.createdAt,
            ),
          );
    }
    if (settlement.mode case final mode?) {
      await _db
          .into(_db.dayModes)
          .insertOnConflictUpdate(
            DayModesCompanion.insert(
              sessionId: sessionId,
              date: date,
              mode: mode,
              changedAt: now,
            ),
          );
    }
    for (final progress in settlement.progress) {
      await _db
          .into(_db.dailyHabitProgressEntries)
          .insertOnConflictUpdate(
            DailyHabitProgressEntriesCompanion.insert(
              sessionId: sessionId,
              habitId: progress.habitId,
              date: date,
              currentValue: progress.currentValue,
              completed: progress.completed,
              completedAt: Value(progress.completedAt),
              updatedAt: now,
            ),
          );
    }
    for (final award in settlement.ledger.granted) {
      // The unique (session_id, source_key) index makes a duplicate award a
      // no-op even if the settlement were applied twice.
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
    }
    final revoked = [for (final x in settlement.ledger.revoked) x.sourceKey];
    if (revoked.isNotEmpty) {
      await (_db.delete(_db.xpTransactions)..where(
            (x) => x.sessionId.equals(sessionId) & x.sourceKey.isIn(revoked),
          ))
          .go();
    }
  }

  Future<HabitHistory> _habitHistory(int sessionId) =>
      loadHabitHistory(_db, sessionId);

  Future<List<HabitProgressRow>> _progressRows(int sessionId, LocalDate date) =>
      (_db.select(_db.dailyHabitProgressEntries)..where(
            (p) => p.sessionId.equals(sessionId) & p.date.equalsValue(date),
          ))
          .get();

  Future<int> _totalXp(int sessionId) async {
    final sum = _db.xpTransactions.amount.sum();
    final row =
        await (_db.selectOnly(_db.xpTransactions)
              ..addColumns([sum])
              ..where(_db.xpTransactions.sessionId.equals(sessionId)))
            .getSingle();
    return row.read(sum) ?? 0;
  }

  DailyHabitProgress _toDomain(HabitProgressRow row) => DailyHabitProgress(
    habitId: row.habitId,
    date: row.date,
    currentValue: row.currentValue,
    completed: row.completed,
    completedAt: row.completedAt,
  );
}
