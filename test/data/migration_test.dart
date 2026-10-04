import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
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

/// A realistic Phase 1 (schema v1) database: an active arc started on
/// Oct 1 with Learning turned off and English turned on during setup.
///
/// * Day 1 (Oct 1): all four enabled habits done (a perfect day in v1).
/// * Day 2 (Oct 2): workout, english, no junk food done; water 5 / 8.
/// * Day 3 (Oct 3): no junk food done.
const _enabled = {
  'workout': true,
  'water': true,
  'learning': false,
  'english': true,
  'no_junk_food': true,
  'sleep_on_time': false,
  'meditation': false,
};
const _v1Habits = [
  // id, title, type, target, unit, icon
  ('workout', 'Workout', 'duration', 30, 'min', 'workout'),
  ('water', 'Water Intake', 'count', 8, 'glasses', 'water'),
  ('learning', 'Learning / Skills', 'duration', 20, 'min', 'learning'),
  ('english', 'English Practice', 'duration', 10, 'min', 'english'),
  ('no_junk_food', 'No Junk Food', 'binary', 1, null, 'no_junk_food'),
  ('sleep_on_time', 'Sleep Before Target', 'binary', 1, null, 'sleep'),
  ('meditation', 'Meditation / Journal', 'duration', 10, 'min', 'meditation'),
];
const _v1Progress = [
  // day, habit, value, completed
  (1, 'workout', 30, true),
  (1, 'water', 8, true),
  (1, 'english', 10, true),
  (1, 'no_junk_food', 1, true),
  (2, 'workout', 30, true),
  (2, 'water', 5, false),
  (2, 'english', 10, true),
  (2, 'no_junk_food', 1, true),
  (3, 'no_junk_food', 1, true),
];

void _seedV1(dynamic raw) {
  raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    "VALUES (1, '2026-10-01', '2026-12-31', 'active', ?, ?)",
    [_ts(_at(1, 8)), _ts(_at(1, 9))],
  );
  for (final (i, (id, title, type, target, unit, icon)) in _v1Habits.indexed) {
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
        _enabled[id]! ? 1 : 0,
        i,
        _ts(_at(1, 8)),
      ],
    );
  }
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
        completed ? _ts(_at(day, 18)) : null,
        _ts(_at(day, 18)),
      ],
    );
    if (completed) {
      raw.execute(
        'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
        "habit_id, date, created_at) VALUES (1, ?, 'habitCompleted', 15, ?, ?, ?)",
        ['habit_completed:$habit:$date', habit, date, _ts(_at(day, 18))],
      );
    }
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('an empty v1 database upgrades through v2 to exactly v3', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  // The app always migrates to the current schema, so Phase 1 databases run
  // the v1 → v2 step and then v2 → v3 (see migration_v3_test.dart for v2).
  test(
    'an empty v1 database upgrades through v2 and v3 to exactly v4',
    () async {
      final db = AppDatabase(await verifier.startAt(1));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);
      expect(await db.select(db.dailyReflections).get(), isEmpty);
      expect(await db.select(db.reminderPrefs).get(), isEmpty);
    },
  );

  group('v1 → v2 → v3 → v4 with Phase 1 data', () {
    late AppDatabase db;
    late TestApp app;
    final day1 = LocalDate(2026, 10, 1);
    final day3 = LocalDate(2026, 10, 3);

    setUp(() async {
      final schema = await verifier.schemaAt(1);
      _seedV1(schema.rawDatabase);
      db = AppDatabase(schema.newConnection());
      // Runs the real migration chain, then checks the result against the
      // committed v3 snapshot.
      await verifier.migrateAndValidate(db, 4);
      app = TestApp(db, FakeClock(DateTime(2026, 10, 3, 20)));
    });
    tearDown(() => db.close());

    test('retains the session and boots into the active arc', () async {
      final session = (await app.winterArc.currentSession())!;
      expect(session.id, 1);
      expect(session.status, WinterArcStatus.active);
      expect(session.startDate, day1);
      expect(session.endDate, LocalDate(2026, 12, 31));
      expect(session.createdAt, _at(1, 8));
      expect(session.startedAt, _at(1, 9));
      expect(AppRoutes.forSession(session), AppRoutes.today);
    });

    test('retains habits and their enabled state', () async {
      final habits = await app.habits.habitsForSession(1);
      expect(habits.map((h) => h.id), _v1Habits.map((h) => h.$1));
      for (final h in habits) {
        final (_, title, type, target, unit, icon) = _v1Habits.firstWhere(
          (v) => v.$1 == h.id,
        );
        expect(h.title, title);
        expect(h.type.name, type);
        expect(h.target, target);
        expect(h.unit, unit);
        expect(h.iconKey, icon);
        expect(h.enabled, _enabled[h.id]);
        expect(h.createdAt, _at(1, 8));
      }
    });

    test('backfills starter Minimum Day targets', () async {
      final minimums = {
        for (final h in await app.habits.habitsForSession(1))
          h.id: h.minimumTarget,
      };
      expect(minimums, {
        'workout': 10,
        'water': 3,
        'learning': 5,
        'english': 5,
        'no_junk_food': 1,
        'sleep_on_time': 1,
        'meditation': 5,
      });
    });

    test('retains every progress row unchanged', () async {
      final rows = await db.select(db.dailyHabitProgressEntries).get();
      expect(rows, hasLength(_v1Progress.length));
      for (final (day, habit, value, completed) in _v1Progress) {
        final row = rows.singleWhere(
          (r) => r.habitId == habit && r.date == LocalDate(2026, 10, day),
        );
        expect(row.currentValue, value);
        expect(row.completed, completed);
        expect(row.completedAt, completed ? _at(day, 18) : null);
        expect(row.updatedAt, _at(day, 18));
      }
    });

    test('retains the XP ledger and adds the Perfect Day bonus', () async {
      final rows = await db.select(db.xpTransactions).get();
      final habitRows = rows.where((r) => r.reason == XpReason.habitCompleted);
      expect(habitRows, hasLength(8));
      for (final r in habitRows) {
        expect(r.amount, 15);
        expect(r.sourceKey, 'habit_completed:${r.habitId}:${r.date}');
      }
      // Only Day 1 had every enabled habit complete.
      final bonus = rows.singleWhere((r) => r.reason == XpReason.perfectDay);
      expect(bonus.sourceKey, XpRules.perfectDayKey(day1));
      expect(bonus.amount, XpRules.perfectDayBonus);
      expect(bonus.date, day1);
      expect(bonus.habitId, isNull);
      expect(bonus.createdAt, _at(1, 18));
      expect(await app.progress.totalXp(1), 8 * 15 + 30);
    });

    test('new tables start empty: every day normal, no revisions', () async {
      expect(await db.select(db.dayModes).get(), isEmpty);
      expect(await db.select(db.habitRevisions).get(), isEmpty);
      expect(await db.select(db.achievementUnlocks).get(), isEmpty);
    });

    test('achievements are derived from the migrated history once', () async {
      final unlocked = await app.achievements.reconcile();
      expect(unlocked.map((u) => u.key.id), [
        'first_rep',
        'first_perfect',
        'streak_3',
      ]);
      expect(await app.achievements.reconcile(), isEmpty);
      expect(await db.select(db.achievementUnlocks).get(), hasLength(3));
    });

    test('Today and Journey read the migrated history', () async {
      final today = await app.tracking.today();
      expect(today.date, day3);
      expect(today.mode, DayMode.normal);
      expect(today.entries.map((e) => e.habit.id), [
        'workout',
        'water',
        'english',
        'no_junk_food',
      ]);
      expect(today.completion.completed, 1);
      expect(today.totalXp, 150);
      expect(today.level.level, 1);
      expect(today.perfectDays.total, 1);
      expect(today.streakFor('no_junk_food').current, 3);
      expect(today.streakFor('workout').current, 2);
      expect(today.streakFor('water').current, 0);

      final journey = await app.tracking.journey();
      expect(journey.days[0].state, JourneyDayState.perfect);
      expect(journey.days[0].xpEarned, 4 * 15 + 30);
      expect(journey.days[1].state, JourneyDayState.partial);
      expect(journey.days[2].state, JourneyDayState.today);
      expect(journey.days[3].state, JourneyDayState.future);
    });

    test('Phase 2 and 3 writes work after migration', () async {
      // Applies from Day 4 (Phase 3 edit timing); today keeps water at 8.
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 10),
        date: day3,
      );
      await app.tracking.activateMinimumDay(date: day3);
      for (final (id, action, times) in [
        ('workout', HabitAction.increment, 2),
        ('water', HabitAction.increment, 3),
        ('english', HabitAction.increment, 1),
      ]) {
        for (var i = 0; i < times; i++) {
          await app.tracking.perform(habitId: id, action: action, date: day3);
        }
      }
      final today = await app.tracking.today();
      expect(today.record.isMinimumComplete, isTrue);
      expect(today.isPerfect, isFalse);
      expect(today.totalXp, 150 + 3 * 15);

      // History is untouched by today's edit and Minimum Day.
      final journey = await app.tracking.journey();
      expect(journey.days[0].record!.entryFor('water')!.target, 8);
      expect(journey.days[0].state, JourneyDayState.perfect);
      expect(journey.days[2].state, JourneyDayState.minimumComplete);
      expect(
        (await db.select(db.habits).get())
            .singleWhere((h) => h.id == 'water')
            .target,
        8, // baseline unchanged; the edit is a revision
      );
    });
  });

  test('a v1 session still in setup migrates and can start', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO winter_arc_sessions (id, start_date, end_date, status, '
      "created_at) VALUES (1, '2026-10-01', '2026-12-31', 'setup', ?)",
      [_ts(_at(1, 8))],
    );
    for (final (i, (id, title, type, target, unit, icon))
        in _v1Habits.indexed) {
      raw.execute(
        'INSERT INTO habits (session_id, id, title, type, target, unit, '
        'icon_key, enabled, sort_order, created_at) '
        'VALUES (1, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
        [id, title, type, target, unit, icon, i, _ts(_at(1, 8))],
      );
    }
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);

    final app = TestApp(db, FakeClock(DateTime(2026, 10, 2, 9)));
    expect(
      AppRoutes.forSession(await app.winterArc.currentSession()),
      AppRoutes.habitSetup,
    );
    final started = await app.winterArc.startWinterArc();
    expect(started.startDate, LocalDate(2026, 10, 2));
    final today = await app.tracking.today();
    expect(today.entries, hasLength(7));
    expect(
      today.entries.every((e) => e.config.minimumTarget <= e.config.target),
      isTrue,
    );
    expect(
      today.entries.firstWhere((e) => e.habit.type == HabitType.binary).target,
      1,
    );
  });
}
