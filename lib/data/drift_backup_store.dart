import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/achievement/achievement.dart';
import '../domain/backup/backup_document.dart';
import '../domain/backup/backup_store.dart';
import '../domain/backup/backup_validator.dart';
import '../domain/habit/habit_config.dart';
import '../domain/progress/daily_habit_progress.dart';
import '../domain/reflection/daily_reflection.dart';
import '../domain/reminder/reminder_preferences.dart';
import '../domain/winter_arc/winter_arc_session.dart';
import '../domain/xp/xp.dart';
import 'habit_mapping.dart';
import 'persistence_guard.dart';

/// [BackupStore] over the app's database.
///
/// Both operations touch reflections, so failures go through
/// [guardPrivatePersistence]: a database error can quote bound values, and
/// those must never reach an error report.
final class DriftBackupStore implements BackupStore {
  const DriftBackupStore(this._db);

  final AppDatabase _db;

  static const _reminderId = 1;

  @override
  Future<BackupData> read() => guardPrivatePersistence(
    'read backup snapshot',
    () => _db.transaction(() async {
      final sessions = await (_db.select(
        _db.winterArcSessions,
      )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
      final habits = _bySession(
        await (_db.select(_db.habits)..orderBy([
              (h) => OrderingTerm.asc(h.sortOrder),
              (h) => OrderingTerm.asc(h.id),
            ]))
            .get(),
        (r) => r.sessionId,
      );
      final revisions = _bySession(
        await (_db.select(_db.habitRevisions)..orderBy([
              (r) => OrderingTerm.asc(r.habitId),
              (r) => OrderingTerm.asc(r.effectiveFrom),
            ]))
            .get(),
        (r) => r.sessionId,
      );
      final modes = _bySession(
        await (_db.select(
          _db.dayModes,
        )..orderBy([(m) => OrderingTerm.asc(m.date)])).get(),
        (r) => r.sessionId,
      );
      final progress = _bySession(
        await (_db.select(_db.dailyHabitProgressEntries)..orderBy([
              (p) => OrderingTerm.asc(p.date),
              (p) => OrderingTerm.asc(p.habitId),
            ]))
            .get(),
        (r) => r.sessionId,
      );
      final xp = _bySession(
        await (_db.select(_db.xpTransactions)..orderBy([
              (x) => OrderingTerm.asc(x.date),
              (x) => OrderingTerm.asc(x.sourceKey),
            ]))
            .get(),
        (r) => r.sessionId,
      );
      final unlocks = _bySession(
        await (_db.select(_db.achievementUnlocks)..orderBy([
              (a) => OrderingTerm.asc(a.unlockedOn),
              (a) => OrderingTerm.asc(a.achievementKey),
            ]))
            .get(),
        (r) => r.sessionId,
      );
      final reflections = _bySession(
        await (_db.select(
          _db.dailyReflections,
        )..orderBy([(r) => OrderingTerm.asc(r.date)])).get(),
        (r) => r.sessionId,
      );
      final reminders = await (_db.select(
        _db.reminderPrefs,
      )..where((r) => r.id.equals(_reminderId))).getSingleOrNull();

      return BackupData(
        arcs: [
          for (final s in sessions)
            BackupArc(
              session: WinterArcSession(
                id: s.id,
                startDate: s.startDate,
                endDate: s.endDate,
                status: s.status,
                createdAt: s.createdAt,
                startedAt: s.startedAt,
              ),
              habits: [for (final h in habits[s.id] ?? []) habitFromRow(h)],
              revisions: [
                for (final r in revisions[s.id] ?? <HabitRevisionRow>[])
                  HabitRevision(
                    habitId: r.habitId,
                    effectiveFrom: r.effectiveFrom,
                    config: HabitConfig(
                      target: r.target,
                      minimumTarget: r.minimumTarget,
                      enabled: r.enabled,
                    ),
                    createdAt: r.createdAt,
                  ),
              ],
              dayModes: [
                for (final m in modes[s.id] ?? <DayModeRow>[])
                  BackupDayMode(
                    date: m.date,
                    mode: m.mode,
                    changedAt: m.changedAt,
                  ),
              ],
              progress: [
                for (final p in progress[s.id] ?? <HabitProgressRow>[])
                  BackupProgress(
                    progress: DailyHabitProgress(
                      habitId: p.habitId,
                      date: p.date,
                      currentValue: p.currentValue,
                      completed: p.completed,
                      completedAt: p.completedAt,
                    ),
                    updatedAt: p.updatedAt,
                  ),
              ],
              xp: [
                for (final x in xp[s.id] ?? <XpTransactionRow>[])
                  XpAward(
                    sourceKey: x.sourceKey,
                    reason: x.reason,
                    amount: x.amount,
                    habitId: x.habitId,
                    date: x.date,
                    awardedAt: x.createdAt,
                  ),
              ],
              achievements: [
                for (final a in unlocks[s.id] ?? <AchievementUnlockRow>[])
                  // A key this version doesn't know can't be restored by
                  // format 1, so it isn't exported (the app ignores it too).
                  if (AchievementKey.fromId(a.achievementKey) case final key?)
                    AchievementUnlock(
                      key: key,
                      unlockedOn: a.unlockedOn,
                      unlockedAt: a.unlockedAt,
                    ),
              ],
              reflections: [
                for (final r in reflections[s.id] ?? <ReflectionRow>[])
                  DailyReflection(
                    sessionId: r.sessionId,
                    date: r.date,
                    mood: Mood.fromKey(r.mood),
                    win: r.win,
                    improvement: r.improvement,
                    createdAt: r.createdAt,
                    updatedAt: r.updatedAt,
                  ),
              ],
            ),
        ],
        reminders: reminders == null
            ? null
            : BackupReminderTimes(
                daily: ReminderTime(reminders.dailyHour, reminders.dailyMinute),
                reflection: ReminderTime(
                  reminders.reflectionHour,
                  reminders.reflectionMinute,
                ),
              ),
      );
    }),
  );

  @override
  Future<void> replaceAll(ValidatedBackup backup) => guardPrivatePersistence(
    'restore backup',
    () => _db.transaction(() async {
      final data = backup.data;

      // Children first, so the order is safe even without cascades.
      await _db.delete(_db.dailyReflections).go();
      await _db.delete(_db.achievementUnlocks).go();
      await _db.delete(_db.xpTransactions).go();
      await _db.delete(_db.dayModes).go();
      await _db.delete(_db.dailyHabitProgressEntries).go();
      await _db.delete(_db.habitRevisions).go();
      await _db.delete(_db.habits).go();
      await _db.delete(_db.winterArcSessions).go();
      await _db.delete(_db.reminderPrefs).go();

      await _db.batch((batch) {
        for (final arc in data.arcs) {
          final s = arc.session;
          final id = s.id;
          batch
            ..insert(
              _db.winterArcSessions,
              WinterArcSessionsCompanion.insert(
                id: Value(id),
                startDate: s.startDate,
                endDate: s.endDate,
                status: s.status,
                createdAt: s.createdAt,
                startedAt: Value(s.startedAt),
              ),
            )
            ..insertAll(_db.habits, [
              for (final h in arc.habits) habitToCompanion(id, h),
            ])
            ..insertAll(_db.habitRevisions, [
              for (final r in arc.revisions)
                HabitRevisionsCompanion.insert(
                  sessionId: id,
                  habitId: r.habitId,
                  effectiveFrom: r.effectiveFrom,
                  target: r.config.target,
                  minimumTarget: r.config.minimumTarget,
                  enabled: r.config.enabled,
                  createdAt: r.createdAt,
                ),
            ])
            ..insertAll(_db.dayModes, [
              for (final m in arc.dayModes)
                DayModesCompanion.insert(
                  sessionId: id,
                  date: m.date,
                  mode: m.mode,
                  changedAt: m.changedAt,
                ),
            ])
            ..insertAll(_db.dailyHabitProgressEntries, [
              for (final row in arc.progress)
                DailyHabitProgressEntriesCompanion.insert(
                  sessionId: id,
                  habitId: row.progress.habitId,
                  date: row.progress.date,
                  currentValue: row.progress.currentValue,
                  completed: row.progress.completed,
                  completedAt: Value(row.progress.completedAt),
                  updatedAt: row.updatedAt,
                ),
            ])
            ..insertAll(_db.xpTransactions, [
              for (final x in arc.xp)
                XpTransactionsCompanion.insert(
                  sessionId: id,
                  sourceKey: x.sourceKey,
                  reason: x.reason,
                  amount: x.amount,
                  habitId: Value(x.habitId),
                  date: x.date,
                  createdAt: x.awardedAt,
                ),
            ])
            ..insertAll(_db.achievementUnlocks, [
              for (final a in arc.achievements)
                AchievementUnlocksCompanion.insert(
                  sessionId: id,
                  achievementKey: a.key.id,
                  unlockedOn: a.unlockedOn,
                  unlockedAt: a.unlockedAt,
                ),
            ])
            ..insertAll(_db.dailyReflections, [
              for (final r in arc.reflections)
                DailyReflectionsCompanion.insert(
                  sessionId: id,
                  date: r.date,
                  mood: Value(r.mood?.key),
                  win: Value(r.win),
                  improvement: Value(r.improvement),
                  createdAt: r.createdAt,
                  updatedAt: r.updatedAt,
                ),
            ]);
        }
        if (data.reminders case final times?) {
          // Times only: both reminders stay off until the user turns them
          // on again.
          batch.insert(
            _db.reminderPrefs,
            ReminderPrefsCompanion.insert(
              id: const Value(_reminderId),
              dailyEnabled: false,
              dailyHour: times.daily.hour,
              dailyMinute: times.daily.minute,
              reflectionEnabled: false,
              reflectionHour: times.reflection.hour,
              reflectionMinute: times.reflection.minute,
              updatedAt: backup.document.exportedAt,
            ),
          );
        }
      });

      await _verify(data);
    }),
  );

  /// Checks the restored state inside the transaction; throwing rolls the
  /// whole restore back.
  Future<void> _verify(BackupData data) async {
    int total(int Function(BackupArc) count) =>
        data.arcs.fold(0, (sum, arc) => sum + count(arc));
    final expected = <TableInfo, int>{
      _db.winterArcSessions: data.arcs.length,
      _db.habits: total((a) => a.habits.length),
      _db.habitRevisions: total((a) => a.revisions.length),
      _db.dayModes: total((a) => a.dayModes.length),
      _db.dailyHabitProgressEntries: total((a) => a.progress.length),
      _db.xpTransactions: total((a) => a.xp.length),
      _db.achievementUnlocks: total((a) => a.achievements.length),
      _db.dailyReflections: total((a) => a.reflections.length),
      _db.reminderPrefs: data.reminders == null ? 0 : 1,
    };
    for (final MapEntry(key: table, value: count) in expected.entries) {
      final stored = await _db
          .customSelect('SELECT COUNT(*) AS c FROM ${table.actualTableName}')
          .getSingle();
      if (stored.read<int>('c') != count) {
        throw StateError('Restore count mismatch in ${table.actualTableName}');
      }
    }
    final open =
        await (_db.select(_db.winterArcSessions)..where(
              (s) => s.status.isIn([
                WinterArcStatus.setup.name,
                WinterArcStatus.active.name,
              ]),
            ))
            .get();
    if (open.length > 1) throw StateError('More than one unfinished arc');
    final dangling = await _db.customSelect('PRAGMA foreign_key_check').get();
    if (dangling.isNotEmpty) throw StateError('Restore left broken references');
  }

  static Map<int, List<R>> _bySession<R>(
    List<R> rows,
    int Function(R) sessionOf,
  ) {
    final map = <int, List<R>>{};
    for (final row in rows) {
      (map[sessionOf(row)] ??= []).add(row);
    }
    return map;
  }
}
