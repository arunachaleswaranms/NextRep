import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../generated_migrations/schema.dart';
import '../support/fakes.dart';

/// Unix seconds, the way drift stores DateTime columns.
int _ts(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
DateTime _at(int day, int hour) => DateTime(2026, 7, day, hour);
String _date(int day) => '2026-07-0$day';

/// A realistic Phase 3 (schema v3) database: one arc from 1 Jul 2026,
/// completed (Day 92 was 30 Sep), with the four default habits.
///
/// * Day 1: a Perfect Day (4 × 15 + 30).
/// * Workout was renamed "Strength"; water raised to 10 (minimum 4) and
///   learning turned off from Day 3, as Phase 3 next-day revisions.
/// * Day 3: a completed Minimum Day (3 × 15).
/// * Five stored achievement unlocks, Summit included.
const _habits = [
  // id, title, type, target, minimum, unit, icon, enabled
  ('workout', 'Strength', 'duration', 30, 10, 'min', 'workout', true),
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
const _revisions = [
  // habit, from day, target, minimum, enabled
  ('water', 3, 10, 4, true),
  ('learning', 3, 20, 5, false),
];
const _progress = [
  // day, habit, value, completed
  (1, 'workout', 30, true), (1, 'water', 8, true),
  (1, 'learning', 20, true), (1, 'no_junk_food', 1, true),
  (3, 'workout', 10, true), (3, 'water', 4, true),
  (3, 'no_junk_food', 1, true),
];
const _unlocks = [
  ('first_rep', 1),
  ('first_perfect', 1),
  ('minimum_complete', 3),
  ('halfway', 46),
  ('summit', 92),
];
const _expectedXp = 4 * 15 + 30 + 3 * 15; // 135

LocalDate _day(int n) => LocalDate(2026, 7, 1).addDays(n - 1);

void _seedV3(dynamic raw) {
  raw.execute(
    'INSERT INTO winter_arc_sessions '
    '(id, start_date, end_date, status, created_at, started_at) '
    "VALUES (1, '2026-07-01', '2026-09-30', 'completed', ?, ?)",
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
  for (final (habit, from, target, min, enabled) in _revisions) {
    raw.execute(
      'INSERT INTO habit_revisions (session_id, habit_id, effective_from, '
      'target, minimum_target, enabled, created_at) '
      'VALUES (1, ?, ?, ?, ?, ?, ?)',
      [habit, _date(from), target, min, enabled ? 1 : 0, _ts(_at(2, 19))],
    );
  }
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
        _ts(_at(day, 18)),
        _ts(_at(day, 18)),
      ],
    );
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
  raw.execute(
    'INSERT INTO xp_transactions (session_id, source_key, reason, amount, '
    "habit_id, date, created_at) VALUES (1, ?, 'perfectDay', 30, NULL, ?, ?)",
    ['perfect_day:${_date(1)}', _date(1), _ts(_at(1, 18))],
  );
  for (final (key, day) in _unlocks) {
    raw.execute(
      'INSERT INTO achievement_unlocks (session_id, achievement_key, '
      'unlocked_on, unlocked_at) VALUES (1, ?, ?, ?)',
      [key, _day(day).toIsoString(), _ts(DateTime(2026, 10, 1, 9))],
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('an empty v3 database upgrades to exactly the v4 schema', () async {
    final db = AppDatabase(await verifier.startAt(3));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
    expect(await db.select(db.dailyReflections).get(), isEmpty);
    expect(await db.select(db.reminderPrefs).get(), isEmpty);
  });

  test('an empty v2 database upgrades through v3 to exactly v4', () async {
    final db = AppDatabase(await verifier.startAt(2));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 4);
  });

  group('v3 → v4 with a completed Phase 3 arc', () {
    late AppDatabase db;
    late TestApp app;

    setUp(() async {
      final schema = await verifier.schemaAt(3);
      _seedV3(schema.rawDatabase);
      db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 4);
      app = TestApp(db, FakeClock(DateTime(2026, 10, 4, 9)));
    });
    tearDown(() => db.close());

    test('keeps the session, completed, and makes it the home arc', () async {
      final sessions = await app.sessions.listSessions();
      expect(sessions, hasLength(1));
      final arc = sessions.single;
      expect(arc.status, WinterArcStatus.completed);
      expect(arc.startDate, _day(1));
      expect(arc.endDate, _day(92));
      expect(arc.startedAt, _at(1, 9));
      expect(await app.sessions.currentSession(), isNull);
      // Boots into its summary: it is the home arc, nothing is current.
      final resolution = await app.lifecycle.resolve();
      expect(resolution.home!.id, 1);
      expect(resolution.current, isNull);
    });

    test('keeps habits, minimum targets and revisions', () async {
      final history = await app.habits.historyForSession(1);
      expect(history.habits.map((h) => h.id), _habits.map((h) => h.$1));
      for (final h in history.habits) {
        final (_, title, _, target, min, unit, icon, enabled) = _habits
            .firstWhere((v) => v.$1 == h.id);
        expect(
          (h.title, h.target, h.minimumTarget, h.unit, h.iconKey, h.enabled),
          (title, target, min, unit, icon, enabled),
        );
      }
      expect(history.revisions, hasLength(2));
      final water = history.habit('water')!;
      expect(history.configOn(water, _day(2)).target, 8);
      expect(history.configOn(water, _day(3)).target, 10);
      expect(history.configOn(water, _day(3)).minimumTarget, 4);
      expect(
        history.configOn(history.habit('learning')!, _day(3)).enabled,
        isFalse,
      );
    });

    test('keeps day modes, progress, XP and Perfect Day bonuses', () async {
      final mode = (await db.select(db.dayModes).get()).single;
      expect((mode.date, mode.mode), (_day(3), DayMode.minimum));
      expect(
        await db.select(db.dailyHabitProgressEntries).get(),
        hasLength(_progress.length),
      );
      final ledger = await db.select(db.xpTransactions).get();
      expect(
        ledger.where((x) => x.reason == XpReason.habitCompleted),
        hasLength(7),
      );
      expect(
        ledger.where((x) => x.reason == XpReason.perfectDay).map((x) => x.date),
        [_day(1)],
      );
      expect(await app.progress.totalXp(1), _expectedXp);

      final journey = await app.tracking.journeyFor(1);
      expect(journey.days.take(3).map((d) => d.state), [
        JourneyDayState.perfect,
        JourneyDayState.missed,
        JourneyDayState.minimumComplete,
      ]);
      expect(journey.days.take(3).map((d) => d.xpEarned), [90, 0, 45]);
    });

    test('keeps achievement unlocks and adds no duplicates', () async {
      final unlocks = await app.achievementStore.unlocks(1);
      expect(
        {for (final u in unlocks) u.key: u.unlockedOn},
        {
          AchievementKey.firstRep: _day(1),
          AchievementKey.firstPerfect: _day(1),
          AchievementKey.minimumComplete: _day(3),
          AchievementKey.halfway: _day(46),
          AchievementKey.summit: _day(92),
        },
      );
      // Nothing new is earned by this history, so nothing is added.
      expect(await app.achievements.reconcile(), isEmpty);
      expect(await db.select(db.achievementUnlocks).get(), hasLength(5));
      expect((await app.achievements.boardFor(1)).total, 15);
    });

    test('starts with no reflections and reminders off', () async {
      expect(await db.select(db.dailyReflections).get(), isEmpty);
      expect((await app.reflections.journalFor(1)).count, 0);
      expect(await app.reminders.preferences(), ReminderPreferences.defaults);
      expect(await app.reminders.reconcile(), isEmpty);
    });

    test(
      'a new arc can start, reuse the final setup and take reflections',
      () async {
        final next = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
        final habits = {
          for (final h in await app.habits.habitsForSession(next.id)) h.id: h,
        };
        expect(habits['workout']!.title, 'Strength');
        expect(habits['water']!.target, 10);
        expect(habits['water']!.minimumTarget, 4);
        expect(habits['learning']!.enabled, isFalse);

        final started = await app.winterArc.startWinterArc();
        expect(started.startDate, LocalDate(2026, 10, 4));
        final saved = await app.reflections.save(
          sessionId: started.id,
          date: LocalDate(2026, 10, 4),
          draft: const ReflectionDraft(mood: Mood.good, win: 'Day 1 again'),
        );
        expect(saved.created, isTrue);
        expect((await app.achievements.reconcile()).map((u) => u.key), [
          AchievementKey.firstReflection,
        ]);
        // Arc 1 is untouched.
        expect(await app.progress.totalXp(1), _expectedXp);
        expect(await db.select(db.achievementUnlocks).get(), hasLength(6));
        expect((await app.reflections.journalFor(1)).count, 0);
      },
    );
  });
}
