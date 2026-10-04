import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../generated_migrations/schema.dart';
import '../support/fakes.dart';

/// Unix seconds, the way drift stores DateTime columns.
int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
DateTime _at(int day, int hour) => DateTime(2026, 10, day, hour);
String _date(int day) => '2026-10-0$day';

/// A realistic Phase 2 (schema v2) database: an active arc from Oct 1 with
/// the four default habits (workout, water, learning, no_junk_food).
///
/// * Day 1, Day 2: Perfect Days (4 × 15 + 30 each).
/// * Day 3: a completed Minimum Day (4 × 15).
/// * Day 4: water raised to 10 (minimum 2) by a same-day Phase 2 revision;
///   water stays at 8, the rest is done (3 × 15).
/// * Day 5: only no_junk_food (15).
const _habits = [
  // id, title, type, target, minimum, unit, icon, enabled
  ('workout', 'Workout', 'duration', 30, 10, 'min', 'workout', true),
  ('water', 'Water Intake', 'count', 8, 3, 'glasses', 'water', true),
  ('learning', 'Learning / Skills', 'duration', 20, 5, 'min', 'learning', true),
  ('english', 'English Practice', 'duration', 10, 5, 'min', 'english', false),
  ('no_junk_food', 'No Junk Food', 'binary', 1, 1, null, 'no_junk_food', true),
  (
    'sleep_on_time',
    'Sleep Before Target',
    'binary',
    1,
    1,
    null,
    'sleep',
    false,
  ),
  ('meditation', 'Meditation', 'duration', 10, 5, 'min', 'meditation', false),
];
const _progress = [
  // day, habit, value, completed
  (1, 'workout', 30, true), (1, 'water', 8, true),
  (1, 'learning', 20, true), (1, 'no_junk_food', 1, true),
  (2, 'workout', 30, true), (2, 'water', 8, true),
  (2, 'learning', 20, true), (2, 'no_junk_food', 1, true),
  (3, 'workout', 10, true), (3, 'water', 3, true),
  (3, 'learning', 5, true), (3, 'no_junk_food', 1, true),
  (4, 'workout', 30, true), (4, 'water', 8, false),
  (4, 'learning', 20, true), (4, 'no_junk_food', 1, true),
  (5, 'no_junk_food', 1, true),
];
const _perfectDays = [1, 2];
const _expectedXp = 2 * (4 * 15 + 30) + 4 * 15 + 3 * 15 + 15; // 300

void _seedV2(dynamic raw) {
  raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    "VALUES (1, '2026-10-01', '2026-12-31', 'active', ?, ?)",
    [_ts(_at(1, 8)), _ts(_at(1, 9))],
  );
  for (final (i, (id, title, type, target, min, unit, icon, enabled))
      in _habits.indexed) {
    raw.execute(
      'INSERT INTO habits (session_id, id, title, type, target, unit, '
      'icon_key, enabled, sort_order, created_at, minimum_target) '
      'VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        title,
        type,
        target,
        unit,
        icon,
        enabled ? 1 : 0,
        i,
        _ts(_at(1, 8)),
        min,
      ],
    );
  }
  raw.execute(
    'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
    "target, minimum_target, enabled, created_at) VALUES (1, 'water', ?, "
    '10, 2, 1, ?)',
    [_date(4), _ts(_at(4, 7))],
  );
  raw.execute(
    'INSERT INTO day_modes (session_id, date, mode, changed_at) '
    "VALUES (1, ?, 'minimum', ?)",
    [_date(3), _ts(_at(3, 12))],
  );
  for (final (day, habit, value, completed) in _progress) {
    raw.execute(
      'INSERT INTO daily_habit_progress_entries (session_id, habit_id, date, '
      'current_value, completed, completed_at, updated_at) '
      'VALUES (1, ?, ?, ?, ?, ?, ?)',
      [
        habit,
        _date(day),
        value,
        completed ? 1 : 0,
        completed ? _ts(_at(day, 18)) : null,
        _ts(_at(day, 18)),
      ],
    );
    if (completed) {
      raw.execute(
        'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
        "habit_id, date, created_at) VALUES (1, ?, 'habitCompleted', 15, ?, ?, ?)",
        [
          'habit_completed:$habit:${_date(day)}',
          habit,
          _date(day),
          _ts(_at(day, 18)),
        ],
      );
    }
  }
  for (final day in _perfectDays) {
    raw.execute(
      'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
      "habit_id, date, created_at) VALUES (1, ?, 'perfectDay', 30, NULL, ?, ?)",
      ['perfect_day:${_date(day)}', _date(day), _ts(_at(day, 18))],
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('an empty v2 database upgrades to exactly the v3 schema', () async {
    final db = AppDatabase(await verifier.startAt(2));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
    expect(await db.select(db.achievementUnlocks).get(), isEmpty);
  });

  group('v2 → v3 with Phase 2 data', () {
    late AppDatabase db;
    late TestApp app;
    LocalDate day(int n) => LocalDate(2026, 10, n);

    setUp(() async {
      final schema = await verifier.schemaAt(2);
      _seedV2(schema.rawDatabase);
      db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 3);
      app = TestApp(db, FakeClock(DateTime(2026, 10, 6, 20)));
    });
    tearDown(() => db.close());

    test('retains the session and boots into the active arc', () async {
      final session = (await app.winterArc.currentSession())!;
      expect(session.status, WinterArcStatus.active);
      expect(session.startDate, day(1));
      expect(session.endDate, LocalDate(2026, 12, 31));
      expect(session.startedAt, _at(1, 9));
      expect(AppRoutes.forSession(session), AppRoutes.today);
    });

    test('retains the habit baseline, minimum targets and revisions', () async {
      final habits = await app.habits.habitsForSession(1);
      expect(habits.map((h) => h.id), _habits.map((h) => h.$1));
      for (final h in habits) {
        final (_, title, _, target, min, unit, icon, enabled) = _habits
            .firstWhere((v) => v.$1 == h.id);
        expect(h.title, title);
        expect(h.target, target);
        expect(h.minimumTarget, min);
        expect(h.unit, unit);
        expect(h.iconKey, icon);
        expect(h.enabled, enabled);
      }
      final revision = (await db.select(db.habitRevisions).get()).single;
      expect(revision.habitId, 'water');
      expect(revision.effectiveFrom, day(4));
      expect(revision.target, 10);
      expect(revision.minimumTarget, 2);
      expect(revision.createdAt, _at(4, 7));
    });

    test('retains day modes, progress and the XP ledger unchanged', () async {
      final mode = (await db.select(db.dayModes).get()).single;
      expect(mode.date, day(3));
      expect(mode.mode, DayMode.minimum);

      final rows = await db.select(db.dailyHabitProgressEntries).get();
      expect(rows, hasLength(_progress.length));
      for (final (d, habit, value, completed) in _progress) {
        final row = rows.singleWhere(
          (r) => r.habitId == habit && r.date == day(d),
        );
        expect(row.currentValue, value);
        expect(row.completed, completed);
      }

      final ledger = await db.select(db.xpTransactions).get();
      expect(
        ledger.where((r) => r.reason == XpReason.habitCompleted),
        hasLength(16),
      );
      final bonuses = ledger.where((r) => r.reason == XpReason.perfectDay);
      expect(bonuses.map((r) => r.date), [day(1), day(2)]);
      expect(await app.progress.totalXp(1), _expectedXp);
    });

    test('Today and Journey read the migrated history unchanged', () async {
      final today = await app.tracking.today();
      expect(today.date, day(6));
      expect(today.totalXp, _expectedXp);
      expect(today.level.level, 2);
      expect(today.perfectDays.total, 2);
      expect(today.perfectDays.streak.best, 2);
      expect(today.streakFor('no_junk_food').current, 5);
      expect(today.streakFor('workout').current, 0);
      expect(today.streakFor('workout').best, 4);
      // The Phase 2 same-day revision still applies from Day 4.
      expect(today.entries.firstWhere((e) => e.habit.id == 'water').target, 10);

      final journey = await app.tracking.journey();
      expect(journey.days.take(6).map((d) => d.state), [
        JourneyDayState.perfect,
        JourneyDayState.perfect,
        JourneyDayState.minimumComplete,
        JourneyDayState.partial,
        JourneyDayState.partial,
        JourneyDayState.today,
      ]);
      expect(journey.days.take(5).map((d) => d.xpEarned), [90, 90, 60, 45, 15]);
      expect(journey.days[2].record!.entryFor('water')!.target, 3);
      expect(journey.days[3].record!.entryFor('water')!.target, 10);
    });

    test(
      'achievements reconcile from the history, without duplicates',
      () async {
        expect(await db.select(db.achievementUnlocks).get(), isEmpty);
        final unlocked = await app.achievements.reconcile();
        expect(
          {for (final u in unlocked) u.key: u.unlockedOn},
          {
            AchievementKey.firstRep: day(1),
            AchievementKey.firstPerfect: day(1),
            AchievementKey.streak3: day(3),
            AchievementKey.minimumComplete: day(3),
            AchievementKey.level2: day(4),
          },
        );
        expect(await app.achievements.reconcile(), isEmpty);
        expect(await db.select(db.achievementUnlocks).get(), hasLength(5));
        // Achievements never grant XP.
        expect(await app.progress.totalXp(1), _expectedXp);
      },
    );

    test('Phase 3 writes work after the migration', () async {
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: day(6),
      );
      final today = await app.tracking.today();
      expect(today.totalXp, _expectedXp + 15);
      expect(today.streakFor('no_junk_food').current, 6);
      final unlocked = await app.achievements.reconcile();
      expect(unlocked.map((u) => u.key), contains(AchievementKey.firstRep));
    });
  });
}
