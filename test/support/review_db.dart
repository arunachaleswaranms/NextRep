import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'fakes.dart';

/// Phase 12B database helpers: full-table snapshots for "nothing was
/// written" checks, and the lifecycle rows Freeze (12E2) and Restart (12F)
/// will store, written directly (nothing in the app creates them yet).
/// All data is synthetic.

typedef DbSnapshot = Map<String, List<Map<String, Object?>>>;

/// Every row and column of every table (sqlite_master's list, so a new
/// table can't be missed), in rowid order.
Future<DbSnapshot> snapshotAll(AppDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          row.data,
      ],
  };
}

/// Every XP ledger row (id, source key, reason, amount, habit, date,
/// created at), in id order.
Future<List<XpTransactionRow>> xpRows(AppDatabase db) => (db.select(
  db.xpTransactions,
)..orderBy([(x) => OrderingTerm.asc(x.id)])).get();

/// Sets [app]'s clock to 09:00 on [date].
void at(TestApp app, LocalDate date, {int hour = 9}) =>
    app.clock.current = DateTime(date.year, date.month, date.day, hour);

/// A freeze row of [sessionId] from [from]; open unless [resumedOn].
Future<void> addFreeze(
  AppDatabase db,
  int sessionId,
  LocalDate from, {
  LocalDate? resumedOn,
}) => db
    .into(db.arcFreezes)
    .insert(
      ArcFreezesCompanion.insert(
        sessionId: sessionId,
        frozenFrom: from,
        resumedOn: Value(resumedOn),
        requestedAt: DateTime(2026, 1, 1),
        resumedAt: Value(resumedOn == null ? null : DateTime(2026, 1, 2)),
      ),
    );

/// Resumes the open freeze of [sessionId] on [on] and moves the end date,
/// as Resume (12E2) will.
Future<void> resume(
  TestApp app,
  int sessionId,
  LocalDate frozenFrom,
  LocalDate on,
) async {
  await (app.db.update(app.db.arcFreezes)..where(
        (f) =>
            f.sessionId.equals(sessionId) &
            f.frozenFrom.equalsValue(frozenFrom),
      ))
      .write(
        ArcFreezesCompanion(
          resumedOn: Value(on),
          resumedAt: Value(DateTime(2026, 1, 2)),
        ),
      );
  final session = (await app.sessions.sessionById(sessionId))!;
  await (app.db.update(
    app.db.winterArcSessions,
  )..where((s) => s.id.equals(sessionId))).write(
    WinterArcSessionsCompanion(
      endDate: Value(session.endDate.addDays(frozenFrom.daysUntil(on))),
    ),
  );
}

/// Ends arc [id] on [closedOn], as Restart (12F) will store it.
Future<WinterArcSession> endArc(TestApp app, int id, LocalDate closedOn) async {
  final session = (await app.sessions.sessionById(id))!;
  await app.sessions.updateSession(
    session.copyWith(status: WinterArcStatus.ended, closedOn: closedOn),
  );
  return (await app.sessions.sessionById(id))!;
}
