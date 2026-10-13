import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../generated_migrations/schema.dart';
import '../support/fakes.dart';

/// Unix seconds, the way drift stores DateTime columns.
int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Every table of schema v5, each of which must survive v5 → v6 as it was.
const _v5Tables = [
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

/// A realistic v1.1 (schema v5) database, all synthetic:
///
/// * arc 1: completed rolling arc (1 Jul – 30 Sep 2026) with a Water
///   revision, a Minimum Day, progress, XP, achievements and a reflection
/// * arc 2: this year's Seasonal Winter Arc, joined 3 Oct, active, with
///   Water renamed "Morning Hydration", a pending Water revision, today's
///   Minimum Day and progress
/// * saved reminder preferences: daily on at 07:30, reflection off at 21:00
void _seedV5(dynamic raw) {
  void session(
    int id,
    String kind,
    String start,
    String end,
    String status,
    String joined,
  ) => raw.execute(
    'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
    'created_at, started_at, arc_kind, participation_start_date) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      start,
      end,
      status,
      _ts(DateTime(2026, 7, 1, 8)),
      _ts(DateTime(2026, 7, 1, 9)),
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
  ) => raw.execute(
    'INSERT INTO habits (session_id, id, title, type, target, unit, '
    'icon_key, enabled, sort_order, created_at, minimum_target) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
    [
      s,
      id,
      title,
      type,
      target,
      type == 'binary' ? null : 'u',
      id,
      id.length,
      _ts(DateTime(2026, 7, 1, 8)),
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
        done ? _ts(DateTime(2026, 7, 1, 18)) : null,
        _ts(DateTime(2026, 7, 1, 18)),
      ],
    );
    if (done) {
      raw.execute(
        'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
        "habit_id, date, created_at) VALUES (?, ?, 'habitCompleted', 15, ?, "
        '?, ?)',
        [s, 'habit_completed:$habit:$date', habit, date, 5],
      );
    }
  }

  session(
    1,
    'rolling92',
    '2026-07-01',
    '2026-09-30',
    'completed',
    '2026-07-01',
  );
  session(
    2,
    'seasonalWinter',
    '2026-10-01',
    '2026-12-31',
    'active',
    '2026-10-03',
  );
  habit(1, 'water', 'Water Intake', 'count', 8, 3);
  habit(1, 'workout', 'Workout', 'duration', 30, 10);
  habit(2, 'water', 'Morning Hydration', 'count', 8, 3);
  habit(2, 'workout', 'Workout', 'duration', 30, 10);
  habit(2, 'sleep_before', 'Sleep Before Target', 'timeBefore', 1380, 1380);
  void revision(int s, String habit, String from, int target, int min) =>
      raw.execute(
        'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
        'target, minimum_target, enabled, created_at) '
        'VALUES (?, ?, ?, ?, ?, 1, ?)',
        [s, habit, from, target, min, _ts(DateTime(2026, 7, 2, 19))],
      );
  revision(1, 'water', '2026-07-03', 10, 4);
  revision(2, 'water', '2026-10-06', 6, 2);
  void mode(int s, String date) => raw.execute(
    'INSERT INTO day_modes (session_id, date, mode, changed_at) '
    "VALUES (?, ?, 'minimum', ?)",
    [s, date, _ts(DateTime(2026, 7, 3, 12))],
  );
  mode(1, '2026-07-03');
  mode(2, '2026-10-05');
  progress(1, 'water', '2026-07-01', 8, true);
  progress(1, 'workout', '2026-07-01', 30, true);
  progress(1, 'water', '2026-07-03', 4, true);
  progress(2, 'water', '2026-10-03', 8, true);
  progress(2, 'water', '2026-10-05', 2, false);
  raw.execute(
    'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
    "habit_id, date, created_at) VALUES (1, 'perfect_day:2026-07-01', "
    "'perfectDay', 30, NULL, '2026-07-01', ?)",
    [_ts(DateTime(2026, 7, 1, 18))],
  );
  for (final (s, key, on) in [
    (1, 'first_rep', '2026-07-01'),
    (1, 'first_perfect', '2026-07-01'),
    (2, 'first_rep', '2026-10-03'),
  ]) {
    raw.execute(
      'INSERT INTO achievement_unlocks (session_id, achievement_key, '
      'unlocked_on, unlocked_at) VALUES (?, ?, ?, ?)',
      [s, key, on, _ts(DateTime(2026, 7, 1, 18))],
    );
  }
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

List<Map<String, Object?>> _rowsBefore(dynamic raw, String table) => [
  for (final row in raw.select('SELECT * FROM $table ORDER BY rowid'))
    {for (final key in row.keys) key as String: row[key]},
];

/// The rows of [table] with only the columns v5 had.
Future<List<Map<String, Object?>>> _v5ColumnsAfter(
  AppDatabase db,
  String table,
) async => [
  for (final row
      in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
    {...row.data}..removeWhere((key, _) => key.startsWith('hydration_')),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('schema v6 is the current schema', () {
    final db = memoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 6);
  });

  test('an empty v5 database upgrades to exactly the v6 schema', () async {
    final db = AppDatabase(await verifier.startAt(5));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 6);
    expect(await db.select(db.reminderPrefs).get(), isEmpty);
    expect(await db.select(db.focusGuardPrefs).get(), isEmpty);
    expect(await db.select(db.focusGuardSelectedApps).get(), isEmpty);
  });

  test('an empty v1 database upgrades through v2, v3, v4 and v5 to exactly '
      'v6', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 6);
  });

  for (final version in [2, 3, 4]) {
    test('an empty v$version database upgrades to exactly v6', () async {
      final db = AppDatabase(await verifier.startAt(version));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 6);
    });
  }

  group('v5 → v6 with v1.1 data', () {
    late AppDatabase db;
    late TestApp app;
    late Map<String, List<Map<String, Object?>>> before;

    setUp(() async {
      final schema = await verifier.schemaAt(5);
      final raw = schema.rawDatabase;
      _seedV5(raw);
      before = {for (final t in _v5Tables) t: _rowsBefore(raw, t)};
      db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 6);
      app = TestApp(db, FakeClock(DateTime(2026, 10, 5, 9)));
    });
    tearDown(() => db.close());

    test('every v5 row survives with every v5 value unchanged', () async {
      for (final table in _v5Tables) {
        expect(await _v5ColumnsAfter(db, table), before[table], reason: table);
      }
      expect(before['winter_arc_sessions'], hasLength(2));
      expect(before['habit_revisions'], hasLength(2));
      expect(before['day_modes'], hasLength(2));
      expect(before['daily_habit_progress_entries'], hasLength(5));
      expect(before['xp_transactions'], hasLength(5));
      expect(before['achievement_unlocks'], hasLength(3));
      expect(before['daily_reflections'], hasLength(1));
      expect(before['reminder_preferences'], hasLength(1));
    });

    test('the saved reminder row gains the Hydration Coach defaults', () async {
      final prefs = await app.reminderStore.load();
      expect(prefs.dailyEnabled, isTrue);
      expect(prefs.dailyTime, const ReminderTime(7, 30));
      expect(prefs.reflectionEnabled, isFalse);
      expect(prefs.reflectionTime, const ReminderTime(21, 0));
      expect(prefs.hydrationEnabled, isFalse);
      expect(prefs.hydrationWindow, HydrationWindow.defaults);
      expect(prefs.hydrationMode, HydrationMode.balanced);
    });

    test('Focus Guard\'s tables exist and are empty; settings read as the '
        'defaults', () async {
      expect(await db.select(db.focusGuardPrefs).get(), isEmpty);
      expect(await db.select(db.focusGuardSelectedApps).get(), isEmpty);
      final settings = await DriftFocusGuardSettingsRepository(db).load();
      expect(settings.enabled, isFalse);
      expect(settings.selectedPackages, isEmpty);
      expect(
        settings.dailyBudgetMinutes,
        FocusGuardRules.defaultDailyBudgetMinutes,
      );
      expect(settings.lastNudgedOn, isNull);
    });

    test('both arcs, their history, XP, achievements and the Journal read '
        'as before', () async {
      final completed = await app.tracking.historyFor(1);
      expect(completed.session.status, WinterArcStatus.completed);
      expect(completed.records.totalXp, 15 * 3 + 30);
      expect(completed.records.modeOn(LocalDate(2026, 7, 3)), DayMode.minimum);
      expect(
        completed.records.habits
            .configOn(
              completed.records.habits.habit('water')!,
              LocalDate(2026, 7, 3),
            )
            .target,
        10,
      );
      final today = await app.tracking.today();
      expect(today.session.id, 2);
      expect(today.session.kind, ArcKind.seasonalWinter);
      expect(today.session.participationStartDate, LocalDate(2026, 10, 3));
      expect(today.date, LocalDate(2026, 10, 5));
      final water = today.entries.singleWhere((e) => e.habit.id == 'water');
      expect(water.habit.title, 'Morning Hydration');
      expect(water.target, 3, reason: "today's Minimum Day");
      expect(water.progress.currentValue, 2);
      expect(await app.achievementStore.unlocks(1), hasLength(2));
      expect((await app.reflections.journalFor(1)).count, 1);
    });

    test('the migrated active arc keeps tracking, and Hydration Coach works '
        'with its renamed built-in Water habit', () async {
      final scheduler = FakeReminderScheduler(granted: true);
      final live = TestApp(db, app.clock, scheduler: scheduler);
      await live.reminders.update((p) => p.copyWith(hydrationEnabled: true));
      final today = [
        for (final r in scheduler.pending)
          if (r.kind == ReminderKind.hydration &&
              LocalDate.fromDateTime(r.at) == LocalDate(2026, 10, 5))
            r,
      ];
      // A Minimum Day (target 3) with 2 logged: the last checkpoint only.
      expect(today.map((r) => r.id), [302]);
      // From 6 Oct the pending goal of 6 applies.
      final tomorrow = scheduler.pending.where(
        (r) =>
            r.kind == ReminderKind.hydration &&
            LocalDate.fromDateTime(r.at) == LocalDate(2026, 10, 6),
      );
      expect(tomorrow, hasLength(4));
      expect(
        scheduler.pending.where((r) => r.kind == ReminderKind.daily),
        isNotEmpty,
        reason: 'the daily reminder stays on',
      );
    });
  });

  group('schema v6 constraints', () {
    late AppDatabase db;

    setUp(() => db = memoryDatabase());
    tearDown(() => db.close());

    Future<void> insertPrefs(int sh, int sm, int eh, int em) =>
        db.customStatement(
          'INSERT OR REPLACE INTO reminder_preferences (id, daily_enabled, '
          'daily_hour, daily_minute, reflection_enabled, reflection_hour, '
          'reflection_minute, updated_at, hydration_start_hour, '
          'hydration_start_minute, hydration_end_hour, hydration_end_minute) '
          'VALUES (1, 0, 8, 0, 0, 21, 0, 0, $sh, $sm, $eh, $em)',
        );

    test('only a same-day window of 8 to 18 hours can be stored', () async {
      await insertPrefs(8, 0, 16, 0);
      await insertPrefs(5, 0, 23, 0);
      for (final (sh, sm, eh, em) in [
        (8, 0, 15, 59),
        (5, 0, 23, 1),
        (20, 0, 8, 0),
        (22, 0, 6, 0),
        (8, 0, 20, 60),
        (24, 0, 20, 0),
      ]) {
        await expectLater(
          insertPrefs(sh, sm, eh, em),
          throwsA(anything),
          reason: '$sh:$sm–$eh:$em',
        );
      }
    });

    test('an unknown mode, budget or package name is rejected', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO reminder_preferences (id, daily_enabled, daily_hour, '
          'daily_minute, reflection_enabled, reflection_hour, '
          'reflection_minute, updated_at, hydration_mode) '
          "VALUES (1, 0, 8, 0, 0, 21, 0, 0, 'Balanced')",
        ),
        throwsA(anything),
        reason: 'stored names are exact',
      );
      for (final budget in [0, 1441]) {
        await expectLater(
          db.customStatement(
            'INSERT INTO focus_guard_preferences '
            '(id, enabled, daily_budget_minutes, updated_at) '
            'VALUES (1, 0, $budget, 0)',
          ),
          throwsA(anything),
          reason: '$budget',
        );
      }
      await expectLater(
        db.customStatement(
          'INSERT INTO focus_guard_preferences '
          '(id, enabled, daily_budget_minutes, updated_at) VALUES (2, 0, 60, 0)',
        ),
        throwsA(anything),
        reason: 'a singleton',
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO focus_guard_selected_apps '
          "(package_name, sort_order, selected_at) VALUES ('', 0, 0)",
        ),
        throwsA(anything),
      );
    });

    test('the Focus Guard repository keeps configuration only, and rejects '
        'what the rules don\'t allow', () async {
      final repo = DriftFocusGuardSettingsRepository(db);
      await repo.save(
        FocusGuardSettings(
          enabled: true,
          dailyBudgetMinutes: 45,
          selectedPackages: const ['org.example.video', 'org.example.chat'],
          lastNudgedOn: LocalDate(2026, 10, 5),
        ),
        at: DateTime(2026, 10, 5, 9),
      );
      final loaded = await repo.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.dailyBudgetMinutes, 45);
      expect(loaded.selectedPackages, [
        'org.example.video',
        'org.example.chat',
      ]);
      expect(loaded.lastNudgedOn, LocalDate(2026, 10, 5));

      for (final invalid in [
        FocusGuardSettings.defaults.copyWithBudget(0),
        const FocusGuardSettings(
          enabled: false,
          dailyBudgetMinutes: 60,
          selectedPackages: ['not a package'],
        ),
        const FocusGuardSettings(
          enabled: false,
          dailyBudgetMinutes: 60,
          selectedPackages: ['org.example.a', 'org.example.a'],
        ),
      ]) {
        expect(
          () => repo.save(invalid, at: DateTime(2026, 10, 5)),
          throwsArgumentError,
        );
      }
      expect((await repo.load()).dailyBudgetMinutes, 45, reason: 'unchanged');
    });
  });
}

extension on FocusGuardSettings {
  FocusGuardSettings copyWithBudget(int minutes) => FocusGuardSettings(
    enabled: enabled,
    dailyBudgetMinutes: minutes,
    selectedPackages: selectedPackages,
  );
}
