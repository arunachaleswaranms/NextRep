import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:sqlite3/sqlite3.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v6.dart' as v6;
import '../support/arcs.dart';
import '../support/fakes.dart';

/// Unix seconds, the way drift stores DateTime columns.
int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Every table of schema v6, each of which must survive v6 → v7 as it was.
const _v6Tables = [
  'winter_arc_sessions',
  'habits',
  'habit_revisions',
  'daily_habit_progress_entries',
  'day_modes',
  'xp_transactions',
  'achievement_unlocks',
  'daily_reflections',
  'reminder_preferences',
  'focus_guard_preferences',
  'focus_guard_selected_apps',
];

/// A realistic v1.2 (schema v6) database, all synthetic:
///
/// * arc 1: a completed rolling arc (5 Jan – 6 Apr 2026) with a goal
///   revision, a Minimum Day, progress, XP, unlocks and a reflection
/// * arc 2: last season's Seasonal Winter Arc, joined late (10 Oct 2025),
///   completed
/// * arc 3: the current arc: an active rolling arc from 1 Nov 2026 with
///   built-in, custom, clock-time and disabled habits in a chosen order,
///   a pending revision, today's Minimum Day, progress and XP; or, with
///   [setup], a saved setup with custom habits and no history
/// * reminder preferences with Hydration Coach on, Focus Guard on with
///   two selected apps and a nudge on record
void _seedV6(dynamic raw, {bool setup = false}) {
  void session(
    int id,
    String kind,
    String start,
    String end,
    String status,
    String? joined,
  ) => raw.execute(
    'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
    'created_at, started_at, arc_kind, participation_start_date) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      start,
      end,
      status,
      _ts(DateTime(2026, 1, 4, 8)),
      joined == null ? null : _ts(DateTime(2026, 1, 5, 9)),
      kind,
      joined,
    ],
  );
  void habit(
    int s,
    String id,
    String title,
    String type,
    int target,
    int min,
    int order, {
    bool enabled = true,
  }) => raw.execute(
    'INSERT INTO habits (session_id, id, title, type, target, unit, '
    'icon_key, enabled, sort_order, created_at, minimum_target) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      s,
      id,
      title,
      type,
      target,
      type == 'binary' || type == 'timeBefore' ? null : 'u',
      id,
      enabled ? 1 : 0,
      order,
      _ts(DateTime(2026, 1, 4, 8)),
      min,
    ],
  );
  void progress(int s, String habit, String date, int value, bool done) {
    raw.execute(
      'INSERT INTO daily_habit_progress_entries (session_id, habit_id, date, '
      'current_value, completed, completed_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        s,
        habit,
        date,
        value,
        done ? 1 : 0,
        done ? _ts(DateTime(2026, 1, 5, 18)) : null,
        _ts(DateTime(2026, 1, 5, 18)),
      ],
    );
    if (done) {
      raw.execute(
        'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
        "habit_id, date, created_at) VALUES (?, ?, 'habitCompleted', 15, ?, "
        '?, ?)',
        [s, 'habit_completed:$habit:$date', habit, date, 7],
      );
    }
  }

  void revision(int s, String habit, String from, int target, int min) =>
      raw.execute(
        'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
        'target, minimum_target, enabled, created_at) '
        'VALUES (?, ?, ?, ?, ?, 1, ?)',
        [s, habit, from, target, min, _ts(DateTime(2026, 1, 6, 19))],
      );
  void mode(int s, String date) => raw.execute(
    'INSERT INTO day_modes (session_id, date, mode, changed_at) '
    "VALUES (?, ?, 'minimum', ?)",
    [s, date, _ts(DateTime(2026, 1, 7, 12))],
  );
  void unlock(int s, String key, String on) => raw.execute(
    'INSERT INTO achievement_unlocks (session_id, achievement_key, '
    'unlocked_on, unlocked_at) VALUES (?, ?, ?, ?)',
    [s, key, on, _ts(DateTime(2026, 1, 5, 18))],
  );

  // Arc 1: completed rolling.
  session(
    1,
    'rolling92',
    '2026-01-05',
    '2026-04-06',
    'completed',
    '2026-01-05',
  );
  habit(1, 'water', 'Water Intake', 'count', 8, 3, 0);
  habit(1, 'workout', 'Workout', 'duration', 30, 10, 1);
  revision(1, 'water', '2026-01-07', 10, 4);
  mode(1, '2026-01-07');
  progress(1, 'water', '2026-01-05', 8, true);
  progress(1, 'workout', '2026-01-05', 30, true);
  progress(1, 'water', '2026-01-07', 4, true);
  progress(1, 'workout', '2026-01-07', 5, false);
  raw.execute(
    'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
    "habit_id, date, created_at) VALUES (1, 'perfect_day:2026-01-05', "
    "'perfectDay', 30, NULL, '2026-01-05', ?)",
    [_ts(DateTime(2026, 1, 5, 18))],
  );
  unlock(1, 'first_rep', '2026-01-05');
  unlock(1, 'first_perfect', '2026-01-05');
  unlock(1, 'summit', '2026-04-06');
  raw.execute(
    'INSERT INTO daily_reflections (session_id, date, mood, win, '
    'improvement, created_at, updated_at) '
    "VALUES (1, '2026-01-05', 'good', 'Synthetic win', 'Synthetic next', ?, ?)",
    [_ts(DateTime(2026, 1, 5, 21)), _ts(DateTime(2026, 1, 5, 22))],
  );

  // Arc 2: last season, joined late, completed.
  session(
    2,
    'seasonalWinter',
    '2025-10-01',
    '2025-12-31',
    'completed',
    '2025-10-10',
  );
  habit(2, 'water', 'Morning Hydration', 'count', 6, 2, 0);
  progress(2, 'water', '2025-10-10', 6, true);
  unlock(2, 'first_rep', '2025-10-10');

  // Arc 3: the current arc, active or a saved setup.
  if (setup) {
    session(3, 'rolling92', '2026-11-05', '2027-02-04', 'setup', null);
  } else {
    session(3, 'rolling92', '2026-11-01', '2027-01-31', 'active', '2026-11-01');
  }
  habit(3, 'custom_violin', 'Violin practice', 'duration', 20, 5, 0);
  habit(3, 'water', 'Water Intake', 'count', 8, 3, 1);
  habit(3, 'sleep_before', 'Sleep Before Target', 'timeBefore', 1380, 1380, 2);
  habit(3, 'custom_journal', 'Paper journal', 'binary', 1, 1, 3);
  habit(3, 'workout', 'Workout', 'duration', 30, 10, 4, enabled: false);
  if (!setup) {
    revision(3, 'water', '2026-11-06', 10, 4); // pending tomorrow
    mode(3, '2026-11-05');
    progress(3, 'custom_violin', '2026-11-01', 20, true);
    progress(3, 'water', '2026-11-01', 8, true);
    progress(3, 'custom_journal', '2026-11-01', 1, true);
    progress(3, 'water', '2026-11-05', 2, false);
    unlock(3, 'first_rep', '2026-11-01');
    raw.execute(
      'INSERT INTO daily_reflections (session_id, date, mood, win, '
      'improvement, created_at, updated_at) '
      "VALUES (3, '2026-11-01', NULL, 'Synthetic day one', NULL, ?, ?)",
      [_ts(DateTime(2026, 11, 1, 21)), _ts(DateTime(2026, 11, 1, 21))],
    );
  }

  raw.execute(
    'INSERT INTO reminder_preferences (id, daily_enabled, daily_hour, '
    'daily_minute, reflection_enabled, reflection_hour, reflection_minute, '
    'updated_at, hydration_enabled, hydration_start_hour, '
    'hydration_start_minute, hydration_end_hour, hydration_end_minute, '
    "hydration_mode) VALUES (1, 1, 7, 30, 1, 21, 15, ?, 1, 7, 0, 21, 0, "
    "'supportive')",
    [_ts(DateTime(2026, 10, 1))],
  );
  raw.execute(
    'INSERT INTO focus_guard_preferences (id, enabled, daily_budget_minutes, '
    "last_nudged_on, updated_at) VALUES (1, 1, 45, '2026-11-04', ?)",
    [_ts(DateTime(2026, 10, 2))],
  );
  for (final (i, name) in ['org.example.video', 'org.example.chat'].indexed) {
    raw.execute(
      'INSERT INTO focus_guard_selected_apps (package_name, sort_order, '
      'selected_at) VALUES (?, ?, ?)',
      [name, i, _ts(DateTime(2026, 10, 2))],
    );
  }
}

List<Map<String, Object?>> _rows(dynamic raw, String table) => [
  for (final row in raw.select('SELECT * FROM $table ORDER BY rowid'))
    {for (final key in row.keys) key as String: row[key]},
];

/// The rows of [table] after the upgrade, with only the columns v6 had.
Future<List<Map<String, Object?>>> _v6ColumnsAfter(
  AppDatabase db,
  String table,
) async => [
  for (final row
      in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
    {...row.data}..remove('closed_on'),
];

/// The schema objects of a database, by name: their SQL as SQLite stores it.
Map<String, String?> _objects(dynamic raw) => {
  for (final row in raw.select(
    "SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  ))
    row['name'] as String: row['sql'] as String?,
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('schema v7 is the current schema', () {
    final db = memoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 7);
  });

  test('a fresh install creates exactly the v7 schema', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await db.validateDatabaseSchema();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 7);
    // The new objects, as the approved design (addendum § G) states them.
    final objects = {
      for (final row
          in await db
              .customSelect(
                "SELECT name, sql FROM sqlite_master WHERE name IN "
                "('arc_freezes', 'one_open_freeze', 'feedback_preferences')",
              )
              .get())
        row.read<String>('name'): row.read<String>('sql'),
    };
    expect(objects, {
      'arc_freezes':
          'CREATE TABLE "arc_freezes" ("session_id" INTEGER NOT NULL '
          'REFERENCES winter_arc_sessions (id) ON DELETE CASCADE, '
          '"frozen_from" TEXT NOT NULL, "resumed_on" TEXT NULL, '
          '"requested_at" INTEGER NOT NULL, "resumed_at" INTEGER NULL, '
          'PRIMARY KEY ("session_id", "frozen_from"), '
          'CHECK (resumed_on IS NULL OR resumed_on > frozen_from))',
      'one_open_freeze':
          'CREATE UNIQUE INDEX one_open_freeze ON arc_freezes (session_id) '
          'WHERE resumed_on IS NULL',
      'feedback_preferences':
          'CREATE TABLE "feedback_preferences" ("id" INTEGER NOT NULL '
          'CHECK("id" = 1), "sounds_enabled" INTEGER NOT NULL CHECK '
          '("sounds_enabled" IN (0, 1)), "sound_theme" TEXT NOT NULL '
          "CHECK(\"sound_theme\" IN ('iceCrystal', 'summitSpark', "
          "'warmEmber')), \"updated_at\" INTEGER NOT NULL, "
          'PRIMARY KEY ("id"))',
    });
  });

  test('an empty v6 database upgrades to exactly the v7 schema', () async {
    final db = AppDatabase(await verifier.startAt(6));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 7);
    expect(await db.select(db.arcFreezes).get(), isEmpty);
    expect(await db.select(db.feedbackPrefs).get(), isEmpty);
  });

  for (final version in [1, 2, 3, 4, 5]) {
    test('an empty v$version database upgrades through every step to '
        'exactly v7', () async {
      final db = AppDatabase(await verifier.startAt(version));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 7);
    });
  }

  for (final setup in [false, true]) {
    group(
      'v6 → v7 with v1.2 data (${setup ? 'a saved setup' : 'an active '
                'arc'})',
      () {
        late AppDatabase db;
        late TestApp app;
        late Map<String, List<Map<String, Object?>>> before;
        late Map<String, String?> objectsBefore;

        setUp(() async {
          final schema = await verifier.schemaAt(6);
          final raw = schema.rawDatabase;
          _seedV6(raw, setup: setup);
          before = {for (final t in _v6Tables) t: _rows(raw, t)};
          objectsBefore = _objects(raw);
          db = AppDatabase(schema.newConnection());
          await verifier.migrateAndValidate(db, 7);
          app = TestApp(db, FakeClock(DateTime(2026, 11, 5, 9)));
        });
        tearDown(() => db.close());

        test('every v6 row survives with every v6 value unchanged', () async {
          for (final table in _v6Tables) {
            expect(
              await _v6ColumnsAfter(db, table),
              before[table],
              reason: table,
            );
            expect(before[table], isNotEmpty, reason: '$table was seeded');
          }
        });

        test(
          'old arcs read closed_on NULL; the new tables are empty',
          () async {
            final closed = await db
                .customSelect('SELECT closed_on FROM winter_arc_sessions')
                .get();
            expect(closed, hasLength(3));
            expect(closed.every((r) => r.data['closed_on'] == null), isTrue);
            expect(await db.select(db.arcFreezes).get(), isEmpty);
            expect(await db.select(db.feedbackPrefs).get(), isEmpty);
            final version = await db.customSelect('PRAGMA user_version').get();
            expect(version.single.data.values.single, 7);
          },
        );

        test('existing tables and indexes are not recreated or changed', () {
          // Only winter_arc_sessions' stored SQL changes: ADD COLUMN appends.
          // Every other v6 object, single_open_session included, is as it was.
          return db.customSelect('SELECT 1').get().then((_) async {
            final after = {
              for (final row
                  in await db
                      .customSelect(
                        "SELECT name, sql FROM sqlite_master "
                        "WHERE name NOT LIKE 'sqlite_%'",
                      )
                      .get())
                row.read<String>('name'): row.readNullable<String>('sql'),
            };
            for (final MapEntry(key: name, value: sql)
                in objectsBefore.entries) {
              if (name == 'winter_arc_sessions') {
                expect(
                  after[name],
                  '${sql!.substring(0, sql.length - 1)}, '
                  '"closed_on" TEXT NULL)',
                );
              } else {
                expect(after[name], sql, reason: name);
              }
            }
            expect(after.keys.toSet().difference(objectsBefore.keys.toSet()), {
              'arc_freezes',
              'one_open_freeze',
              'feedback_preferences',
            });
          });
        });

        test('foreign keys hold and SQLite reports a healthy file', () async {
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          final integrity = await db
              .customSelect('PRAGMA integrity_check')
              .get();
          expect(integrity.single.data.values.single, 'ok');
        });

        test('at most one unfinished arc is still enforced', () async {
          await expectLater(
            db.customStatement(
              "INSERT INTO winter_arc_sessions (start_date, end_date, status, "
              "created_at) VALUES ('2026-11-05', '2027-02-04', 'setup', 0)",
            ),
            throwsA(anything),
          );
        });

        test('the migration awards nothing; reading awards nothing', () async {
          expect(
            await _v6ColumnsAfter(db, 'xp_transactions'),
            before['xp_transactions'],
          );
          expect(
            await _v6ColumnsAfter(db, 'achievement_unlocks'),
            before['achievement_unlocks'],
          );
          await app.history.sessions();
          await app.insights.snapshot();
          for (final id in [1, 2]) {
            await app.tracking.historyFor(id);
          }
          expect(
            await _v6ColumnsAfter(db, 'xp_transactions'),
            before['xp_transactions'],
          );
          expect(
            await _v6ColumnsAfter(db, 'achievement_unlocks'),
            before['achievement_unlocks'],
          );
        });

        test('history reads exactly as in v1.2', () async {
          final completed = await app.tracking.historyFor(1);
          expect(completed.session.status, WinterArcStatus.completed);
          expect(completed.session.freezes, isEmpty);
          expect(completed.session.closedOn, isNull);
          expect(completed.records.totalXp, 15 * 3 + 30);
          expect(
            completed.records.modeOn(LocalDate(2026, 1, 7)),
            DayMode.minimum,
          );
          expect(completed.elapsedDates, hasLength(92));
          final season = await app.tracking.historyFor(2);
          expect(season.session.joinDayNumber, 10);
          expect(season.elapsedDates, hasLength(83));
          expect((await app.reflections.journalFor(1)).count, 1);
        });

        test(
          'app-level settings read as before; feedback reads its defaults',
          () async {
            final prefs = await app.reminderStore.load();
            expect(prefs.dailyEnabled, isTrue);
            expect(prefs.dailyTime, const ReminderTime(7, 30));
            expect(prefs.reflectionTime, const ReminderTime(21, 15));
            expect(prefs.hydrationEnabled, isTrue);
            expect(prefs.hydrationMode, HydrationMode.supportive);
            final focusGuard = await DriftFocusGuardSettingsRepository(db)
                .load();
            expect(focusGuard.enabled, isTrue);
            expect(focusGuard.dailyBudgetMinutes, 45);
            expect(focusGuard.selectedPackages, [
              'org.example.video',
              'org.example.chat',
            ]);
            expect(focusGuard.lastNudgedOn, LocalDate(2026, 11, 4));
            expect(
              await DriftFeedbackPreferencesRepository(db).load(),
              FeedbackPreferences.defaults,
            );
            expect(
              await db.select(db.feedbackPrefs).get(),
              isEmpty,
              reason: 'reading writes nothing',
            );
          },
        );

        if (!setup) {
          test(
            'the active arc keeps tracking, with its order and custom habits',
            () async {
              final today = await app.tracking.today();
              expect(today.session.id, 3);
              expect(today.isTrackable, isTrue);
              expect(today.entries.map((e) => e.habit.id), [
                'custom_violin',
                'water',
                'sleep_before',
                'custom_journal',
              ]);
              expect(
                today.entries.firstWhere((e) => e.habit.id == 'water').target,
                3,
                reason: "today's Minimum Day",
              );
              await completeHabit(app, 'custom_violin');
              final after = await app.tracking.history();
              expect(after.records.totalXp, 15 * 3 + 15);
            },
          );
        } else {
          test(
            'the saved setup reopens with its order and can start',
            () async {
              final setupView = await app.winterArc.setup();
              expect(setupView.session.status, WinterArcStatus.setup);
              expect(setupView.habits.map((h) => h.id), [
                'custom_violin',
                'water',
                'sleep_before',
                'custom_journal',
                'workout',
              ]);
              final started = await app.winterArc.startWinterArc();
              expect(started.status, WinterArcStatus.active);
              expect(started.participationStartDate, LocalDate(2026, 11, 5));
              expect(started.closedOn, isNull);
            },
          );
        }
      },
    );
  }

  group('a v6 file on disk', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nextrep_v7_');
      file = File('${dir.path}/nextrep.sqlite');
      // A schema-v6 database exactly as v1.2.0 would leave it.
      final old = v6.DatabaseAtV6(NativeDatabase(file));
      await old.customSelect('SELECT 1').get(); // creates the v6 schema
      await old.close();
      final raw = await _openRaw(file);
      _seedV6(raw);
      raw.close();
    });
    tearDown(() => dir.delete(recursive: true));

    test('upgrades once and reopens without migrating again', () async {
      final first = AppDatabase(NativeDatabase(file));
      expect((await first.select(first.winterArcSessions).get()), hasLength(3));
      await first.close();
      // A second open: user_version is 7, so no step runs (re-running
      // ALTER TABLE ADD COLUMN would fail on the existing column).
      final second = AppDatabase(NativeDatabase(file));
      final version = await second.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.single, 7);
      expect(await second.select(second.arcFreezes).get(), isEmpty);
      expect(
        (await second.select(second.winterArcSessions).get()),
        hasLength(3),
      );
      await second.close();
    });

    test('a failed upgrade leaves the v6 database exactly as it was, and a '
        'retry succeeds', () async {
      // Sabotage: an object that makes the step's CREATE TABLE fail after
      // its ALTER TABLE has run.
      var raw = await _openRaw(file);
      raw.execute('CREATE TABLE arc_freezes (unexpected INTEGER)');
      final rowsBefore = {for (final t in _v6Tables) t: _rows(raw, t)};
      final objectsBefore = _objects(raw);
      raw.close();

      final failing = AppDatabase(NativeDatabase(file));
      await expectLater(
        failing.customSelect('SELECT 1').get(),
        throwsA(anything),
      );
      await failing.close();

      raw = await _openRaw(file);
      expect(raw.select('PRAGMA user_version').single.values.single, 6);
      expect(_objects(raw), objectsBefore, reason: 'no partial schema');
      for (final t in _v6Tables) {
        expect(_rows(raw, t), rowsBefore[t], reason: t);
      }
      raw.execute('DROP TABLE arc_freezes');
      raw.close();

      final retry = AppDatabase(NativeDatabase(file));
      addTearDown(retry.close);
      final version = await retry.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.single, 7);
      await retry.validateDatabaseSchema();
      for (final t in _v6Tables) {
        expect(await _v6ColumnsAfter(retry, t), rowsBefore[t], reason: t);
      }
    });
  });
}

/// A plain sqlite3 connection to [file], for raw checks outside drift.
Future<Database> _openRaw(File file) async => sqlite3.open(file.path);
