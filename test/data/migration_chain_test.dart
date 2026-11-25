import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../generated_migrations/schema.dart';
import '../support/fakes.dart';
import '../support/reconciliation.dart';
import '../support/review_db.dart';

/// Phase 12H migration hardening (brief § 6): the **whole** chain
/// v1 → v2 → v3 → v4 → v5 → v6 → v7 (and v3 → … → v7) on populated
/// historical databases, with every row of every table that existed before
/// compared value by value afterwards.
///
/// Earlier phases compared every row only from v4, v5 and v6 onwards
/// (`migration_v5_test`, `migration_v6_test`, `migration_v7_test`); the
/// v1 and v3 chains were checked through app reads. Here, for each start:
///
/// * every pre-existing table keeps every row, each column it had before
///   holding exactly its old value (added columns are checked apart);
/// * the only added rows are the documented v1 → v2 Perfect Day bonuses,
///   one per qualifying date; nothing is deleted or duplicated;
/// * added columns hold their documented values (`minimum_target`
///   catalogue backfill, `arc_kind = rolling92`, `participation_start_date
///   = start_date` for started Arcs, null in setup, `closed_on` null);
/// * every table added on the way is empty (no `arc_freezes`, no
///   `feedback_preferences` row, which reads as the approved defaults);
/// * `PRAGMA user_version` is exactly 7 (Focus Guard's native gate reads
///   it), the schema equals the committed v7 snapshot, and SQLite reports
///   no integrity or foreign-key problem;
/// * the migrated Arc reconciles on every screen, and reading writes
///   nothing.
///
/// The direct v6 → v7 fixture upgrade with every v6 row compared is
/// `migration_v7_test` ("every v6 row survives…", PRAGMA checks). All data
/// is synthetic.

int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

typedef _Rows = Map<String, List<Map<String, Object?>>>;

/// Every row of every table (sqlite_master's list), in rowid order.
_Rows _rawSnapshot(dynamic raw) {
  final tables = [
    for (final row in raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String,
  ];
  return {
    for (final t in tables)
      t: [
        for (final row in raw.select('SELECT * FROM "$t" ORDER BY rowid'))
          Map<String, Object?>.of(row),
      ],
  };
}

/// [after] holds every row of [before], each with its old columns'
/// values unchanged, in the same order; [added] says which rows a table
/// may gain (none unless given).
void _expectPreserved(
  _Rows before,
  _Rows after, {
  bool Function(String table, Map<String, Object?> row)? added,
}) {
  for (final table in before.keys) {
    expect(after.containsKey(table), isTrue, reason: '$table dropped');
    final old = before[table]!;
    final now = [
      for (final row in after[table]!)
        if (added == null || !added(table, row)) row,
    ];
    expect(now, hasLength(old.length), reason: '$table: rows added or lost');
    for (final (i, row) in old.indexed) {
      final restricted = {for (final c in row.keys) c: now[i][c]};
      expect(restricted, row, reason: '$table row $i changed');
    }
  }
}

Future<void> _expectHealthyV7(AppDatabase db, {required String why}) async {
  final version = await db.customSelect('PRAGMA user_version').getSingle();
  expect(version.data.values.single, 7, reason: '$why: user_version');
  final integrity = await db.customSelect('PRAGMA integrity_check').get();
  expect(integrity.single.data.values.single, 'ok', reason: why);
  expect(
    await db.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
    reason: '$why: foreign keys',
  );
}

// ---------------------------------------------------------------------------
// v1: a Phase 1 database (one Arc: active, or still in setup).

const _v1Habits = [
  // id, title, type, target, unit, icon, enabled
  ('workout', 'Workout', 'duration', 30, 'min', 'workout', true),
  ('water', 'Water Intake', 'count', 8, 'glasses', 'water', true),
  ('learning', 'Learning / Skills', 'duration', 20, 'min', 'learning', false),
  ('english', 'English Practice', 'duration', 10, 'min', 'english', true),
  ('no_junk_food', 'No Junk Food', 'binary', 1, null, 'no_junk_food', true),
  ('sleep_on_time', 'Sleep Before Target', 'binary', 1, null, 'sleep', false),
  ('meditation', 'Meditation', 'duration', 10, 'min', 'meditation', false),
  ('custom_a1', 'Cold Shower', 'count', 2, 'times', 'star', true),
];
const _v1Minimums = {
  'workout': 10,
  'water': 3,
  'learning': 5,
  'english': 5,
  'no_junk_food': 1,
  'sleep_on_time': 1,
  'meditation': 5,
  'custom_a1': 2, // unknown habits keep their full target
};

/// Days 1, 2 and 4 have every enabled habit done (Perfect in v2 terms);
/// Day 3 is partial; Day 5 has a row that isn't completed.
final _v1Progress = [
  for (final day in [1, 2, 4])
    for (final h in [
      'workout',
      'water',
      'english',
      'no_junk_food',
      'custom_a1',
    ])
      (day, h, h == 'water' ? 8 : (h == 'custom_a1' ? 2 : 1), true),
  (3, 'workout', 30, true),
  (3, 'water', 5, false),
  (5, 'water', 2, false),
];

DateTime _oct(int day, int hour) => DateTime(2026, 10, day, hour);

void _seedV1(dynamic raw, {required String status}) {
  raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    "VALUES (1, '2026-10-01', '2026-12-31', ?, ?, ?)",
    [status, _ts(_oct(1, 8)), status == 'setup' ? null : _ts(_oct(1, 9))],
  );
  for (final (i, (id, title, type, target, unit, icon, enabled))
      in _v1Habits.indexed) {
    raw.execute(
      'INSERT INTO habits (session_id, id, title, type, target, unit, '
      'icon_key, enabled, sort_order, created_at) '
      'VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        title,
        type,
        target,
        unit,
        icon,
        enabled ? 1 : 0,
        i,
        _ts(_oct(1, 8)),
      ],
    );
  }
  if (status == 'setup') return;
  for (final (day, habit, value, completed) in _v1Progress) {
    final date = '2026-10-0$day';
    raw.execute(
      'INSERT INTO daily_habit_progress_entries (session_id, habit_id, date, '
      'current_value, completed, completed_at, updated_at) '
      'VALUES (1, ?, ?, ?, ?, ?, ?)',
      [
        habit,
        date,
        value,
        completed ? 1 : 0,
        completed ? _ts(_oct(day, 18)) : null,
        _ts(_oct(day, 18)),
      ],
    );
    if (completed) {
      raw.execute(
        'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
        "habit_id, date, created_at) VALUES (1, ?, 'habitCompleted', 15, ?, ?, ?)",
        ['habit_completed:$habit:$date', habit, date, _ts(_oct(day, 18))],
      );
    }
  }
}

// ---------------------------------------------------------------------------
// v3: a Phase 3 database (one completed Arc with revisions, a Minimum Day
// and unlocks).

DateTime _jul(int day, int hour) => DateTime(2026, 7, day, hour);
String _julDate(int day) => '2026-07-0$day';

void _seedV3(dynamic raw) {
  raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    "VALUES (1, '2026-07-01', '2026-09-30', 'completed', ?, ?)",
    [_ts(_jul(1, 8)), _ts(_jul(1, 9))],
  );
  for (final (i, (id, target, min, enabled)) in const [
    ('workout', 30, 10, true),
    ('water', 8, 3, true),
    ('learning', 20, 5, true),
    ('no_junk_food', 1, 1, true),
  ].indexed) {
    raw.execute(
      'INSERT INTO habits (session_id, id, title, type, target, unit, '
      'icon_key, enabled, sort_order, created_at, minimum_target) '
      "VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        id,
        id.toUpperCase(),
        id == 'water'
            ? 'count'
            : (id == 'no_junk_food' ? 'binary' : 'duration'),
        target,
        id == 'water' ? 'glasses' : null,
        id,
        enabled ? 1 : 0,
        i,
        _ts(_jul(1, 8)),
        min,
      ],
    );
  }
  raw.execute(
    'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
    'target, minimum_target, enabled, created_at) VALUES '
    "(1, 'water', ?, 10, 4, 1, ?), (1, 'learning', ?, 20, 5, 0, ?)",
    [_julDate(3), _ts(_jul(2, 19)), _julDate(3), _ts(_jul(2, 19))],
  );
  raw.execute(
    'INSERT INTO day_modes (session_id, date, mode, changed_at) '
    "VALUES (1, ?, 'minimum', ?)",
    [_julDate(3), _ts(_jul(3, 12))],
  );
  for (final (day, habit, value) in const [
    (1, 'workout', 30),
    (1, 'water', 8),
    (1, 'learning', 20),
    (1, 'no_junk_food', 1),
    (3, 'workout', 10),
    (3, 'water', 4),
    (3, 'no_junk_food', 1),
  ]) {
    raw.execute(
      'INSERT INTO daily_habit_progress_entries (session_id, habit_id, date, '
      'current_value, completed, completed_at, updated_at) '
      'VALUES (1, ?, ?, ?, 1, ?, ?)',
      [habit, _julDate(day), value, _ts(_jul(day, 18)), _ts(_jul(day, 18))],
    );
    raw.execute(
      'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
      "habit_id, date, created_at) VALUES (1, ?, 'habitCompleted', 15, ?, ?, ?)",
      [
        'habit_completed:$habit:${_julDate(day)}',
        habit,
        _julDate(day),
        _ts(_jul(day, 18)),
      ],
    );
  }
  raw.execute(
    'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
    "habit_id, date, created_at) VALUES (1, ?, 'perfectDay', 30, NULL, ?, ?)",
    ['perfect_day:${_julDate(1)}', _julDate(1), _ts(_jul(1, 18))],
  );
  for (final (key, on) in const [
    ('first_rep', '2026-07-01'),
    ('first_perfect', '2026-07-01'),
    ('minimum_complete', '2026-07-03'),
    ('summit', '2026-09-30'),
  ]) {
    raw.execute(
      'INSERT INTO achievement_unlocks (session_id, achievement_key, '
      'unlocked_on, unlocked_at) VALUES (1, ?, ?, ?)',
      [key, on, _ts(DateTime(2026, 10, 1, 9))],
    );
  }
}

const _addedSinceV1 = [
  'habit_revisions',
  'day_modes',
  'achievement_unlocks',
  'daily_reflections',
  'reminder_preferences',
  'focus_guard_preferences',
  'focus_guard_selected_apps',
  'arc_freezes',
  'feedback_preferences',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final status in ['active', 'setup']) {
    test('v1 → v7 with a Phase 1 $status Arc: every v1 row and value kept, '
        'only the documented additions', () async {
      final schema = await verifier.schemaAt(1);
      _seedV1(schema.rawDatabase, status: status);
      final before = _rawSnapshot(schema.rawDatabase);
      expect(before.keys.toSet(), {
        'winter_arc_sessions',
        'habits',
        'daily_habit_progress_entries',
        'xp_transactions',
      });
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 7);
      final after = await snapshotAll(db);

      // Every v1 row, every v1 column; xp may gain only Perfect Day bonuses.
      _expectPreserved(
        before,
        after,
        added: (table, row) =>
            table == 'xp_transactions' && row['reason'] == 'perfectDay',
      );
      final bonuses = [
        for (final r in after['xp_transactions']!)
          if (r['reason'] == 'perfectDay') r,
      ];
      expect(
        [for (final b in bonuses) b['date']],
        status == 'active' ? ['2026-10-01', '2026-10-02', '2026-10-04'] : [],
        reason: 'one bonus per v1 Perfect date, none twice',
      );
      for (final b in bonuses) {
        expect(b['amount'], 30);
        expect(b['source_key'], 'perfect_day:${b['date']}');
        expect(b['habit_id'], isNull);
      }

      // Added columns hold their documented values.
      for (final h in after['habits']!) {
        expect(h['minimum_target'], _v1Minimums[h['id']], reason: '${h['id']}');
      }
      final session = after['winter_arc_sessions']!.single;
      expect(session['arc_kind'], 'rolling92');
      expect(
        session['participation_start_date'],
        status == 'setup' ? isNull : '2026-10-01',
      );
      expect(session['closed_on'], isNull, reason: 'closed_on null for v1');

      // Tables added on the way are empty.
      for (final table in _addedSinceV1) {
        expect(after[table], isEmpty, reason: '$table is empty');
      }
      await _expectHealthyV7(db, why: 'v1 $status');
      expect(
        await DriftFeedbackPreferencesRepository(db).load(),
        FeedbackPreferences.defaults,
        reason: 'no row reads as the approved defaults (on, Ice Crystal)',
      );

      // The migrated data reads consistently everywhere, and reading
      // writes nothing.
      final app = TestApp(db, FakeClock(DateTime(2026, 10, 5, 20)));
      expect(await snapshotAll(db), after, reason: 'opening wrote nothing');
      if (status == 'active') {
        final f = await expectArcReconciles(app, 1, context: 'v1 active');
        expect(f.status, WinterArcStatus.active);
        expect(f.elapsed, 5);
        expect(f.perfectDays, 3, reason: 'Days 1, 2, 4');
        expect(
          f.ledgerXp,
          (5 * 3 + 1) * 15 + 3 * 30,
          reason: 'v1 ledger plus the three bonuses',
        );
      } else {
        final setup = await app.winterArc.setup();
        expect(setup.session.status, WinterArcStatus.setup);
        expect(
          [for (final h in setup.habits) h.id],
          [for (final h in _v1Habits) h.$1],
          reason: 'setup order kept',
        );
      }
    });
  }

  test('v3 → v7 with a completed Phase 3 Arc (revisions, a Minimum Day, '
      'unlocks): every v3 row and value kept, nothing added', () async {
    final schema = await verifier.schemaAt(3);
    _seedV3(schema.rawDatabase);
    final before = _rawSnapshot(schema.rawDatabase);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 7);
    final after = await snapshotAll(db);
    _expectPreserved(before, after);
    final session = after['winter_arc_sessions']!.single;
    expect(session['status'], 'completed');
    expect(session['participation_start_date'], '2026-07-01');
    expect(session['closed_on'], isNull);
    for (final table in [
      'daily_reflections',
      'reminder_preferences',
      'focus_guard_preferences',
      'focus_guard_selected_apps',
      'arc_freezes',
      'feedback_preferences',
    ]) {
      expect(after[table], isEmpty, reason: '$table is empty');
    }
    await _expectHealthyV7(db, why: 'v3 completed');
    final app = TestApp(db, FakeClock(DateTime(2026, 11, 1, 9)));
    final f = await expectArcReconciles(app, 1, context: 'v3 completed');
    expect(f.status, WinterArcStatus.completed);
    expect((f.elapsed, f.open, f.ledgerXp), (92, 0, 4 * 15 + 30 + 3 * 15));
    expect(f.perfectDays, 1);
    expect(f.minimumDaysCompleted, 1);
    // A completed Arc is never re-opened, re-scored or re-awarded by the
    // app's own launch work.
    await app.lifecycle.reconcile();
    final ledger = await xpRows(db);
    expect(ledger, hasLength(8), reason: 'nothing re-derived');
    expect(
      (await app.sessions.sessionById(1))!.participationStartDate,
      LocalDate(2026, 7, 1),
    );
  });
}
