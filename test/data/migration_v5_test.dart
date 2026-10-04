import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../generated_migrations/schema.dart';
import '../support/fakes.dart';

/// Unix seconds, the way drift stores DateTime columns.
int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

const _tables = [
  'winter_arc_sessions',
  'habits',
  'habit_revisions',
  'daily_habit_progress_entries',
  'day_modes',
  'xp_transactions',
  'achievement_unlocks',
  'daily_reflections',
  'reminder_preferences',
];

/// A realistic Phase 5 (schema v4) database: arc 1 completed (1 Jul – 30
/// Sep 2026) with a revision, a Minimum Day, progress, XP, unlocks and a
/// reflection; arc 2 active since 1 Oct 2026 with a day of progress; and
/// saved reminder preferences.
void _seedV4(dynamic raw) {
  void session(int id, String start, String end, String status) => raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      id,
      start,
      end,
      status,
      _ts(DateTime(2026, 7, 1, 8)),
      status == 'setup' ? null : _ts(DateTime(2026, 7, 1, 9)),
    ],
  );
  void habit(int session, String id, String type, int target, int min) =>
      raw.execute(
        'INSERT INTO habits (session_id, id, title, type, target, unit, '
        'icon_key, enabled, sort_order, created_at, minimum_target) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
        [
          session,
          id,
          'Habit $id',
          type,
          target,
          type == 'binary' ? null : 'u',
          id,
          id.length,
          _ts(DateTime(2026, 7, 1, 8)),
          min,
        ],
      );
  void progress(int session, String habit, String date, int value) {
    raw.execute(
      'INSERT INTO daily_habit_progress_entries (session_id, habit_id, date, '
      'current_value, completed, completed_at, updated_at) '
      'VALUES (?, ?, ?, ?, 1, ?, ?)',
      [session, habit, date, value, _ts(DateTime(2026, 7, 1, 18)), 1],
    );
    raw.execute(
      'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
      "habit_id, date, created_at) VALUES (?, ?, 'habitCompleted', 15, ?, ?, ?)",
      [session, 'habit_completed:$habit:$date', habit, date, 5],
    );
  }

  session(1, '2026-07-01', '2026-09-30', 'completed');
  session(2, '2026-10-01', '2026-12-31', 'active');
  for (final s in [1, 2]) {
    habit(s, 'workout', 'duration', 30, 10);
    habit(s, 'no_junk_food', 'binary', 1, 1);
    habit(s, 'sleep_on_time', 'binary', 1, 1);
  }
  raw.execute(
    'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
    'target, minimum_target, enabled, created_at) '
    "VALUES (1, 'workout', '2026-07-03', 40, 15, 1, ?)",
    [_ts(DateTime(2026, 7, 2, 19))],
  );
  raw.execute(
    'INSERT INTO day_modes (session_id, date, mode, changed_at) '
    "VALUES (1, '2026-07-03', 'minimum', ?)",
    [_ts(DateTime(2026, 7, 3, 12))],
  );
  progress(1, 'workout', '2026-07-01', 30);
  progress(1, 'no_junk_food', '2026-07-01', 1);
  progress(2, 'workout', '2026-10-01', 30);
  raw.execute(
    'INSERT INTO achievement_unlocks (session_id, achievement_key, '
    "unlocked_on, unlocked_at) VALUES (1, 'first_rep', '2026-07-01', ?)",
    [_ts(DateTime(2026, 7, 1, 18))],
  );
  raw.execute(
    'INSERT INTO daily_reflections (session_id, date, mood, win, '
    'improvement, created_at, updated_at) '
    "VALUES (1, '2026-07-01', 'good', 'Synthetic win', NULL, ?, ?)",
    [_ts(DateTime(2026, 7, 1, 21)), _ts(DateTime(2026, 7, 1, 21))],
  );
  raw.execute(
    'INSERT INTO reminder_preferences (id, daily_enabled, daily_hour, '
    'daily_minute, reflection_enabled, reflection_hour, reflection_minute, '
    'updated_at) VALUES (1, 1, 7, 30, 0, 21, 0, ?)',
    [_ts(DateTime(2026, 9, 1))],
  );
}

/// Every row of [table], as maps, in a stable order.
List<Map<String, Object?>> _rowsBefore(dynamic raw, String table) => [
  for (final row in raw.select('SELECT * FROM $table ORDER BY rowid'))
    {for (final key in row.keys) key as String: row[key]},
];

Future<List<Map<String, Object?>>> _rowsAfter(
  AppDatabase db,
  String table,
) async => [
  for (final row
      in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
    {...row.data}
      ..remove('arc_kind')
      ..remove('participation_start_date'),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('an empty v4 database upgrades to exactly the v5 schema', () async {
    final db = AppDatabase(await verifier.startAt(4));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);
    expect(await db.select(db.winterArcSessions).get(), isEmpty);
  });

  test(
    'an empty v1 database upgrades through every step to exactly v5',
    () async {
      final db = AppDatabase(await verifier.startAt(1));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 5);
    },
  );

  test('schema v5 is the current schema', () {
    final db = memoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 5);
  });

  group('v4 → v5 with Phase 5 data', () {
    late AppDatabase db;
    late TestApp app;
    late Map<String, List<Map<String, Object?>>> before;

    setUp(() async {
      final schema = await verifier.schemaAt(4);
      final raw = schema.rawDatabase;
      _seedV4(raw);
      before = {for (final t in _tables) t: _rowsBefore(raw, t)};
      db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);
      app = TestApp(db, FakeClock(DateTime(2026, 10, 4, 9)));
    });
    tearDown(() => db.close());

    test('every existing row survives unchanged', () async {
      for (final table in _tables) {
        expect(await _rowsAfter(db, table), before[table], reason: table);
      }
      expect(before['xp_transactions'], hasLength(3));
      expect(before['daily_reflections'], hasLength(1));
      expect(before['reminder_preferences'], hasLength(1));
    });

    test('a completed arc becomes rolling92, joined on its start', () async {
      final arc = (await app.sessions.sessionById(1))!;
      expect(arc.kind, ArcKind.rolling92);
      expect(arc.status, WinterArcStatus.completed);
      expect(arc.participationStartDate, LocalDate(2026, 7, 1));
      expect(arc.participationStartDate, arc.startDate);
      expect(WinterArcRules.problemWith(arc), isNull);
    });

    test('an active arc becomes rolling92, joined on its start', () async {
      final arc = (await app.sessions.currentSession())!;
      expect(arc.id, 2);
      expect(arc.kind, ArcKind.rolling92);
      expect(arc.status, WinterArcStatus.active);
      expect(arc.participationStartDate, LocalDate(2026, 10, 1));
      expect(WinterArcRules.problemWith(arc), isNull);
    });

    test('history, XP, achievements and reflections still read', () async {
      final history = await app.tracking.historyFor(1);
      expect(history.elapsedDates, hasLength(92));
      expect(history.records.totalXp, 30);
      final today = await app.tracking.today();
      expect(today.position, isA<ArcInProgress>());
      expect(today.session.id, 2);
      expect(today.totalXp, 15);
      expect(await app.achievementStore.unlocks(1), hasLength(1));
      expect((await app.reflections.journalFor(1)).count, 1);
      final reminders = await app.reminderStore.load();
      expect(reminders.dailyEnabled, isTrue);
      expect(reminders.dailyTime, const ReminderTime(7, 30));
    });

    test('the migrated arcs keep working', () async {
      final journey = await app.tracking.journey();
      expect(journey.days, hasLength(92));
      expect(
        journey.days.where((d) => d.isNotJoined),
        isEmpty,
        reason: 'a rolling arc has no days before joining',
      );
    });
  });

  test('a v4 session still in setup becomes rolling92 without a '
      'participation date, and can start', () async {
    final schema = await verifier.schemaAt(4);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
      "created_at) VALUES (1, '2026-10-03', '2027-01-02', 'setup', ?)",
      [_ts(DateTime(2026, 10, 3, 8))],
    );
    raw.execute(
      'INSERT INTO habits (session_id, id, title, type, target, unit, '
      'icon_key, enabled, sort_order, created_at, minimum_target) '
      "VALUES (1, 'water', 'Water', 'count', 8, 'glasses', 'water', 1, 0, ?, 3)",
      [_ts(DateTime(2026, 10, 3, 8))],
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);

    final app = TestApp(db, FakeClock(DateTime(2026, 10, 4, 9)));
    final setup = (await app.sessions.currentSession())!;
    expect(setup.kind, ArcKind.rolling92);
    expect(setup.status, WinterArcStatus.setup);
    expect(setup.participationStartDate, isNull);

    final started = await app.winterArc.startWinterArc();
    expect(started.startDate, LocalDate(2026, 10, 4));
    expect(started.endDate, LocalDate(2027, 1, 3));
    expect(started.participationStartDate, LocalDate(2026, 10, 4));
  });

  test('v1 → v5: a Phase 1 active arc is rolling92 joined on Day 1', () async {
    final schema = await verifier.schemaAt(1);
    schema.rawDatabase.execute(
      'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
      "created_at, started_at) VALUES (1, '2026-10-01', '2026-12-31', "
      "'active', ?, ?)",
      [_ts(DateTime(2026, 10, 1, 8)), _ts(DateTime(2026, 10, 1, 9))],
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);
    final arc = (await TestApp(
      db,
      FakeClock(DateTime(2026, 10, 2, 9)),
    ).sessions.sessionById(1))!;
    expect(arc.kind, ArcKind.rolling92);
    expect(arc.participationStartDate, LocalDate(2026, 10, 1));
  });

  test('participation comes from start_date, never from started_at', () async {
    // started_at is an instant that falls on 30 Sep in UTC; the calendar
    // start stays 1 Oct.
    final schema = await verifier.schemaAt(4);
    schema.rawDatabase.execute(
      'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
      "created_at, started_at) VALUES (1, '2026-10-01', '2026-12-31', "
      "'active', ?, ?)",
      [_ts(DateTime.utc(2026, 9, 30, 20)), _ts(DateTime.utc(2026, 9, 30, 20))],
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 5);
    final row = await db
        .customSelect(
          'SELECT participation_start_date AS p FROM winter_arc_sessions',
        )
        .getSingle();
    expect(row.read<String>('p'), '2026-10-01');
  });
}
