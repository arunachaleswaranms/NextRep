import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/achievements/achievements_controller.dart';
import 'package:nextrep/features/celebration/celebration_queue.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

/// Review finding R2: an ended arc is read-only history (ARC_CONTROL_SPEC
/// § 3, invariant 4). No achievement path (sync, reconcile, the catalog
/// backfill, the app's startup run) adds, revokes or re-dates any of its
/// unlocks, on any date, whether it is the home arc or older history, and
/// whether this app ended it or a format-4 restore brought it. Active and
/// completed arcs keep their reconciliation exactly. Real services over a
/// real in-memory SQLite database; all data is synthetic.
///
/// Nothing in Phase 12E1 ends an arc: the tests end one as Restart (12F)
/// will store it, through the repository primitive.

final _d1 = LocalDate(2026, 10, 7);
final _d2 = LocalDate(2026, 10, 8);
final _closed = LocalDate(2026, 10, 9); // Day 3

void _at(TestApp app, LocalDate date, {int hour = 9}) =>
    app.clock.current = DateTime(date.year, date.month, date.day, hour);

/// Every row of every table: "nothing was written" checks.
Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
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

/// Every stored row of arc [sessionId], in every table that holds one: its
/// session row, freezes, habits, revisions, progress, day modes, XP,
/// unlocks and reflections.
Future<Map<String, List<Map<String, Object?>>>> _arcRows(
  AppDatabase db,
  int sessionId,
) async {
  final all = await _snapshot(db);
  return {
    for (final MapEntry(key: table, value: rows) in all.entries)
      table: [
        for (final row in rows)
          if (table == 'winter_arc_sessions'
              ? row['id'] == sessionId
              : row['session_id'] == sessionId)
            row,
      ],
  };
}

Future<Map<String, LocalDate>> _unlocks(AppDatabase db, int sessionId) async =>
    {
      for (final r in await (db.select(
        db.achievementUnlocks,
      )..where((a) => a.sessionId.equals(sessionId))).get())
        r.achievementKey: r.unlockedOn,
    };

Future<void> _plant(TestApp app, int sessionId, String key, LocalDate on) => app
    .db
    .into(app.db.achievementUnlocks)
    .insert(
      AchievementUnlocksCompanion.insert(
        sessionId: sessionId,
        achievementKey: key,
        unlockedOn: on,
        unlockedAt: DateTime(2026, 10, 9, 21),
      ),
    );

Future<void> _forget(TestApp app, int sessionId, String key) =>
    (app.db.delete(app.db.achievementUnlocks)..where(
          (a) => a.sessionId.equals(sessionId) & a.achievementKey.equals(key),
        ))
        .go();

/// Ends arc [id] on [closedOn], as Restart (12F) will store it.
Future<WinterArcSession> _end(TestApp app, int id, LocalDate closedOn) async {
  final session = (await app.sessions.sessionById(id))!;
  await app.sessions.updateSession(
    session.copyWith(status: WinterArcStatus.ended, closedOn: closedOn),
  );
  return (await app.sessions.sessionById(id))!;
}

/// The review's arc: Rolling, from 7 Oct 2026, three Perfect Days lived
/// through the real services with achievements synced each day, then ended
/// on 9 Oct (`closedOn`, Day 3). Its stored unlocks then hold every case a
/// recalculation would change:
///
/// * valid unlocks from Day 1 (First Rep) and from closedOn (3-Day Streak,
///   Perfect Trio);
/// * a missing one, as if the catalog had grown since: Clean Sweep is
///   removed, and a sync or the backfill would add it back on Day 1;
/// * unearned rows dated closedOn (7-Day Streak) and Day 2 (Perfect 10),
///   which a reconciliation on those dates would revoke as "today's";
/// * a Summit dated closedOn, which an ended arc can never earn: the
///   unusual state an imported history may hold.
Future<WinterArcSession> _endedArc(TestApp app) async {
  _at(app, _d1);
  await app.winterArc.beginSetup();
  final arc = await app.winterArc.startWinterArc();
  for (final day in [_d1, _d2, _closed]) {
    _at(app, day);
    await completeAll(app);
    await app.achievements.sync();
  }
  await _forget(app, arc.id, AchievementKey.firstPerfect.id);
  final ended = await _end(app, arc.id, _closed);
  await _plant(app, arc.id, AchievementKey.streak7.id, _closed);
  await _plant(app, arc.id, AchievementKey.perfect10.id, _d2);
  await _plant(app, arc.id, AchievementKey.summit.id, _closed);
  final stored = await _unlocks(app.db, arc.id);
  expect(stored[AchievementKey.firstRep.id], _d1);
  expect(stored[AchievementKey.streak3.id], _closed);
  expect(stored[AchievementKey.perfect3.id], _closed);
  expect(stored, isNot(contains(AchievementKey.firstPerfect.id)));
  return ended;
}

/// The UI's achievement sync over [app], as a fresh app launch builds it.
ProviderContainer _launch(TestApp app) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(app.db),
      clockProvider.overrideWithValue(app.clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Each achievement entry point, run as the app runs it. Each returns
/// whether it reported a change (anything stored, revoked or celebrated).
final _entryPoints = <String, Future<bool> Function(TestApp app)>{
  'sync()': (app) async => !(await app.achievements.sync()).isEmpty,
  'reconcile()': (app) async => (await app.achievements.reconcile()).isNotEmpty,
  'backfillCatalog()': (app) async {
    final backfill = await app.achievements.backfillCatalog();
    return !backfill.celebratable.isEmpty || backfill.historical.isNotEmpty;
  },
  // Launch: the first run is the catalog backfill, later runs (Today,
  // Journey refreshes) are syncs. Each launch is a new container.
  'app launch and refreshes': (app) async {
    final container = _launch(app);
    final sync = container.read(achievementSyncProvider);
    final stored = [...await sync.run(), ...await sync.run()];
    return stored.isNotEmpty ||
        container.read(celebrationQueueProvider).isNotEmpty;
  },
};

/// Runs every entry point three times on [app]'s current date and requires
/// that the whole database stays byte-identical and nothing is reported.
Future<void> _expectEveryEntryPointReadOnly(TestApp app, String why) async {
  final before = await _snapshot(app.db);
  for (final MapEntry(key: name, value: run) in _entryPoints.entries) {
    for (var i = 1; i <= 3; i++) {
      final at = '$why: $name, run $i';
      expect(await run(app), isFalse, reason: at);
      expect(await _snapshot(app.db), before, reason: at);
    }
  }
}

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7, 9)));
  });
  tearDown(() => app.db.close());

  group('A. the ended arc is the home arc', () {
    test('D, E, F: on closedOn, after it, after its planned end and after a '
        'clock rollback, nothing is added, revoked or re-dated', () async {
      final arc = await _endedArc(app);
      final stored = await _unlocks(app.db, arc.id);
      for (final (why, today) in [
        ('D. today is closedOn', _closed),
        ('E. the day after closedOn', _closed.addDays(1)),
        ('E. after its planned end', arc.endDate.addDays(30)),
        ('F. rolled back to Day 2', _d2),
        ('F. rolled back before the start', _d1.addDays(-3)),
      ]) {
        _at(app, today);
        await _expectEveryEntryPointReadOnly(app, why);
        expect(await _unlocks(app.db, arc.id), stored, reason: why);
      }
    });

    test('its stored unlocks stay readable on the board, as stored', () async {
      final arc = await _endedArc(app);
      _at(app, _closed);
      await app.achievements.sync();
      final stored = await _unlocks(app.db, arc.id);
      for (final board in [
        (await app.achievements.board())!,
        await app.achievements.boardFor(arc.id),
      ]) {
        expect({
          for (final e in board.entries)
            if (e.unlock case final u?) u.key.id: u.unlockedOn,
        }, stored);
      }
    });

    test('M. an arc ended on Day 92 never newly earns the Summit', () async {
      _at(app, _d1);
      await app.winterArc.beginSetup();
      final started = await app.winterArc.startWinterArc();
      await completeAll(app);
      await app.achievements.sync();
      _at(app, started.endDate);
      await completeAll(app);
      await app.achievements.sync();
      final arc = await _end(app, started.id, started.endDate);
      for (final today in [
        arc.endDate,
        arc.endDate.addDays(1),
        arc.endDate.addDays(400),
      ]) {
        _at(app, today);
        // The close-out leaves an ended arc as it is.
        expect((await app.lifecycle.reconcile())?.status, arc.status);
        await _expectEveryEntryPointReadOnly(app, 'Day 92 ended, on $today');
        expect(
          await _unlocks(app.db, arc.id),
          isNot(contains(AchievementKey.summit.id)),
        );
      }
    });
  });

  group('B. the ended arc is older history; a newer arc is active', () {
    test('I, J. the active arc gains and loses today\'s unlocks as before; '
        'the ended arc is never touched', () async {
      final ended = await _endedArc(app);
      final endedRows = await _arcRows(app.db, ended.id);
      _at(app, _closed.addDays(1));
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final active = await app.winterArc.startWinterArc();
      final today = app.clock.today();

      // J. A provisional unlock of today is revoked when its reason goes.
      await completeHabit(app, 'no_junk_food');
      expect((await app.achievements.reconcile()).map((u) => u.key), [
        AchievementKey.firstRep,
      ]);
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.undoCompletion,
        date: today,
      );
      final undone = await app.achievements.sync();
      expect(undone.revoked.map((u) => u.key), [AchievementKey.firstRep]);
      expect(await _unlocks(app.db, active.id), isEmpty);

      // I. A valid unlock is stored and celebrated once.
      await completeAll(app);
      final container = _launch(app);
      final stored = await container.read(achievementSyncProvider).run();
      expect(
        {for (final u in stored) u.key: u.unlockedOn},
        {AchievementKey.firstRep: today, AchievementKey.firstPerfect: today},
      );
      expect(container.read(celebrationQueueProvider), hasLength(1));
      for (final run in _entryPoints.values) {
        expect(await run(app), isFalse, reason: 'N. idempotent');
      }
      expect(await _arcRows(app.db, ended.id), endedRows);

      // The backfill reconciles every non-active arc: the ended one stays
      // as stored, even with the clock back on its closedOn.
      for (final date in [_closed, _d2, today.addDays(1)]) {
        _at(app, date);
        final backfill = await app.achievements.backfillCatalog();
        expect(backfill.historical, isEmpty, reason: '$date');
        expect(await _arcRows(app.db, ended.id), endedRows, reason: '$date');
      }
      _at(app, _closed);
      await _expectEveryEntryPointReadOnly(app, 'rolled back to closedOn');
      expect(await _arcRows(app.db, ended.id), endedRows);
    });
  });

  group('C. the ended arc is older history; a newer arc completed', () {
    test('K, L. the completed arc is backfilled silently and earns its '
        'Summit; the ended arc is never touched', () async {
      final ended = await _endedArc(app);
      final endedRows = await _arcRows(app.db, ended.id);
      _at(app, _closed.addDays(1));
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final second = await app.winterArc.startWinterArc();
      await completeAll(app);
      await app.achievements.sync();
      // As if the catalog had grown since that day.
      await _forget(app, second.id, AchievementKey.firstPerfect.id);
      _at(app, second.endDate.addDays(1));
      expect(
        (await app.lifecycle.reconcile())?.status,
        WinterArcStatus.completed,
      );

      final backfill = await app.achievements.backfillCatalog();
      // K. The completed arc gains what it earned, dated when earned,
      // silently: the forgotten Clean Sweep, and the day milestones that
      // no sync stored while it ran. The ended arc gains nothing.
      expect(backfill.historical.keys, [second.id]);
      expect(
        {for (final u in backfill.historical[second.id]!) u.key: u.unlockedOn},
        {
          AchievementKey.firstPerfect: second.startDate,
          AchievementKey.day14: second.dateOfDay(14),
          AchievementKey.halfway: second.dateOfDay(46),
          AchievementKey.day60: second.dateOfDay(60),
          AchievementKey.day75: second.dateOfDay(75),
        },
      );
      // L. Its natural completion earns the Summit, celebrated.
      expect(
        {for (final u in backfill.celebratable.unlocked) u.key: u.unlockedOn},
        {AchievementKey.summit: second.endDate},
      );
      expect(backfill.celebratable.revoked, isEmpty);
      expect(await _arcRows(app.db, ended.id), endedRows);

      // N. Then everything is idempotent, also after a rollback to the
      // ended arc's closedOn.
      for (final date in [second.endDate.addDays(2), _closed]) {
        _at(app, date);
        await _expectEveryEntryPointReadOnly(app, 'after completion, $date');
      }
      expect(await _arcRows(app.db, ended.id), endedRows);
    });
  });

  group('G. an ended arc restored from a format-4 backup', () {
    test('restores exactly, then stays read-only on every date', () async {
      final ended = await _endedArc(app);
      _at(app, _closed.addDays(1));
      final export = await app.backup.export();
      final sourceRows = await _arcRows(app.db, ended.id);

      final target = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 11, 1, 9)),
      );
      addTearDown(target.db.close);
      await target.winterArc.beginSetup();
      await target.winterArc.startWinterArc();
      await completeAll(target);
      await target.backup.restore(await target.backup.inspect(export.bytes));
      final restored = (await target.sessions.listSessions()).single;
      expect(restored.status, WinterArcStatus.ended);
      expect(restored.closedOn, _closed);
      // Session and XP row ids are local surrogate keys (never exported),
      // and rows return in a canonical order; everything else is as
      // exported.
      Map<String, List<String>> comparable(
        Map<String, List<Map<String, Object?>>> rows,
      ) => {
        for (final MapEntry(key: table, value: list) in rows.entries)
          table: [
            for (final row in list)
              jsonEncode(
                {...row}
                  ..remove('session_id')
                  ..removeWhere(
                    (column, _) =>
                        column == 'id' &&
                        (table == 'xp_transactions' ||
                            table == 'winter_arc_sessions'),
                  ),
              ),
          ]..sort(),
      };
      expect(
        comparable(await _arcRows(target.db, restored.id)),
        comparable(sourceRows),
      );

      final stored = await _unlocks(target.db, restored.id);
      for (final (why, today) in [
        ('D. today is closedOn', _closed),
        ('E. after closedOn', LocalDate(2026, 11, 1)),
        ('F. rolled back to Day 2', _d2),
      ]) {
        _at(target, today);
        await _expectEveryEntryPointReadOnly(target, 'restored: $why');
        expect(await _unlocks(target.db, restored.id), stored, reason: why);
      }
    });
  });
}
