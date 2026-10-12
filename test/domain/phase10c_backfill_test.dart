import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/achievements/achievements_controller.dart';
import 'package:nextrep/features/celebration/celebration_queue.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

/// Phase 10C upgrade behaviour: history lived under v1.0 (whose catalog
/// had 15 achievements) earns the new achievements when v1.1 first runs,
/// dated when they were actually earned. Real services over a real SQLite
/// database. Default habits: workout (30 min), water (8), learning
/// (20 min), no_junk_food (binary).

const _newIds = [
  'streak_14',
  'streak_30',
  'streak_50',
  'perfect_25',
  'minimum_7',
  'reflections_14',
  'reflections_30',
  'day_14',
  'day_60',
  'day_75',
  'no_junk_7',
  'no_junk_30',
  'no_junk_50',
  'workout_30',
  'water_30',
  'learning_30',
  'sleep_before_14',
];

const _defaults = ['workout', 'water', 'learning', 'no_junk_food'];

/// Moves the clock to challenge day [day] of [arc], at [hour].
void _goTo(TestApp app, WinterArcSession arc, int day, {int hour = 9}) {
  final date = arc.startDate.addDays(day - 1);
  app.clock.current = DateTime(date.year, date.month, date.day, hour);
}

LocalDate _on(WinterArcSession arc, int day) => arc.startDate.addDays(day - 1);

/// Lives days [from]..[to] of [arc] as v1.0 would: completes [habits]
/// each day, saves a reflection on [reflectOn] days, and reconciles
/// achievements after each day's actions.
Future<void> _live(
  TestApp app,
  WinterArcSession arc,
  int from,
  int to, {
  List<String> habits = _defaults,
  Set<int> reflectOn = const {},
}) async {
  for (var day = from; day <= to; day++) {
    _goTo(app, arc, day);
    for (final id in habits) {
      await completeHabit(app, id);
    }
    if (reflectOn.contains(day)) {
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(mood: Mood.good, win: 'Private words'),
      );
    }
    await app.achievements.reconcile();
  }
}

/// Removes every unlock of the Phase 10C keys: the state a v1.0 install
/// left behind, since v1.0 didn't know those achievements.
Future<void> _forgetNewUnlocks(AppDatabase db) => (db.delete(
  db.achievementUnlocks,
)..where((a) => a.achievementKey.isIn(_newIds))).go();

Future<List<AchievementUnlockRow>> _rows(AppDatabase db, int sessionId) =>
    (db.select(db.achievementUnlocks)
          ..where((a) => a.sessionId.equals(sessionId))
          ..orderBy([(a) => OrderingTerm.asc(a.achievementKey)]))
        .get();

Future<Map<String, LocalDate>> _stored(AppDatabase db, int sessionId) async => {
  for (final r in await _rows(db, sessionId)) r.achievementKey: r.unlockedOn,
};

Map<AchievementKey, LocalDate> _byKey(Iterable<AchievementUnlock> unlocks) => {
  for (final u in unlocks) u.key: u.unlockedOn,
};

/// The UI's achievement sync over [app]'s database and clock.
ProviderContainer _container(TestApp app) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(app.db),
      clockProvider.overrideWithValue(app.clock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

List<AchievementCelebration> _celebrations(ProviderContainer container) => [
  for (final e in container.read(celebrationQueueProvider))
    if (e is AchievementCelebration) e,
];

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 9)));
  });
  tearDown(() => app.db.close());

  /// The issue's example: 34 Perfect Days with every default habit (so 34
  /// Workout days and a 34-day No Junk Food run), 18 reflections, and the
  /// arc now on Day 64. Unlocks as v1.0 left them, plus an unknown key
  /// written by some newer version.
  Future<WinterArcSession> upgradedActiveArc() async {
    await app.winterArc.beginSetup();
    final arc = await app.winterArc.startWinterArc();
    await _live(app, arc, 1, 34, reflectOn: {for (var d = 1; d <= 18; d++) d});
    _goTo(app, arc, 64);
    await app.achievements.reconcile();
    await _forgetNewUnlocks(app.db);
    await app.db
        .into(app.db.achievementUnlocks)
        .insert(
          AchievementUnlocksCompanion.insert(
            sessionId: arc.id,
            achievementKey: 'from_the_future',
            unlockedOn: _on(arc, 40),
            unlockedAt: DateTime(2026, 11, 9, 7),
          ),
        );
    return arc;
  }

  Map<AchievementKey, LocalDate> expectedFor(WinterArcSession arc) => {
    AchievementKey.streak14: _on(arc, 14),
    AchievementKey.streak30: _on(arc, 30),
    AchievementKey.perfect25: _on(arc, 25),
    AchievementKey.noJunk7: _on(arc, 7),
    AchievementKey.noJunk30: _on(arc, 30),
    AchievementKey.workout30: _on(arc, 30),
    AchievementKey.water30: _on(arc, 30),
    AchievementKey.learning30: _on(arc, 30),
    AchievementKey.reflections14: _on(arc, 14),
    AchievementKey.day14: _on(arc, 14),
    AchievementKey.day60: _on(arc, 60),
  };

  group('A / B. the active arc', () {
    test('backfill stores what history already earned, dated when earned; '
        'old and unknown rows are untouched', () async {
      final arc = await upgradedActiveArc();
      final before = await _rows(app.db, arc.id);
      expect(before.map((r) => r.achievementKey), isNot(contains('day_14')));
      app.clock.current = DateTime(2026, 12, 3, 10, 30); // still Day 64

      final backfill = await app.achievements.backfillCatalog();
      expect(backfill.historical, isEmpty);
      expect(backfill.home.revoked, isEmpty);
      expect(_byKey(backfill.home.unlocked), expectedFor(arc));
      // Persisted now, dated in the past.
      expect(backfill.home.unlocked.map((u) => u.unlockedAt).toSet(), {
        DateTime(2026, 12, 3, 10, 30),
      });

      final after = await _rows(app.db, arc.id);
      for (final old in before) {
        expect(after, contains(old), reason: old.achievementKey);
      }
      expect(after, hasLength(before.length + 11));
      expect((await _stored(app.db, arc.id))['from_the_future'], _on(arc, 40));
      // Nothing beyond the history is awarded.
      for (final id in const [
        'streak_50',
        'minimum_7',
        'reflections_30',
        'day_75',
        'no_junk_50',
        'sleep_before_14',
      ]) {
        expect(await _stored(app.db, arc.id), isNot(contains(id)));
      }
      // Achievements never touch XP.
      final ledger = await app.db.select(app.db.xpTransactions).get();
      expect(ledger.map((x) => x.reason.name).toSet(), {
        'habitCompleted',
        'perfectDay',
      });
    });

    test('running the backfill again changes nothing', () async {
      final arc = await upgradedActiveArc();
      await app.achievements.backfillCatalog();
      final once = await _rows(app.db, arc.id);
      for (var i = 0; i < 2; i++) {
        app.clock.advance(const Duration(minutes: 5));
        expect((await app.achievements.backfillCatalog()).isEmpty, isTrue);
        expect((await app.achievements.sync()).isEmpty, isTrue);
      }
      expect(await _rows(app.db, arc.id), once);
    });
  });

  test('C. the home arc celebrates its backfill once, as one card', () async {
    final arc = await upgradedActiveArc();
    final container = _container(app);
    final sync = container.read(achievementSyncProvider);

    final stored = await sync.run();
    expect(_byKey(stored), expectedFor(arc));
    final celebrations = _celebrations(container);
    expect(celebrations, hasLength(1));
    expect(_byKey(celebrations.single.unlocks), expectedFor(arc));

    // Later runs (Today refreshes) add nothing and celebrate nothing.
    expect(await sync.run(), isEmpty);
    expect(await sync.run(), isEmpty);
    expect(container.read(celebrationQueueProvider), hasLength(1));
  });

  group('D / E. completed arcs', () {
    /// Arc 1: 1 Jul – 30 Sep 2026, lived like [upgradedActiveArc] and
    /// closed out on Day 93.
    Future<WinterArcSession> firstArc() async {
      app.clock.current = DateTime(2026, 7, 1, 9);
      await app.winterArc.beginSetup();
      final arc = await app.winterArc.startWinterArc();
      await _live(
        app,
        arc,
        1,
        34,
        reflectOn: {for (var d = 1; d <= 18; d++) d},
      );
      _goTo(app, arc, 93);
      await app.lifecycle.reconcile();
      await app.achievements.reconcile();
      return (await app.sessions.sessionById(arc.id))!;
    }

    test('D. a completed arc is backfilled silently', () async {
      final first = await firstArc();
      expect(first.status, WinterArcStatus.completed);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final second = await app.winterArc.startWinterArc();
      await _forgetNewUnlocks(app.db);
      final firstBefore = await _rows(app.db, first.id);
      expect(
        firstBefore.map((r) => r.achievementKey),
        unorderedEquals([
          'first_rep',
          'first_perfect',
          'streak_3',
          'streak_7',
          'perfect_3',
          'perfect_10',
          'level_2',
          'level_3',
          'level_5',
          'first_reflection',
          'reflections_7',
          'halfway',
          'summit',
        ]),
      );
      final secondBefore = await _rows(app.db, second.id);

      final container = _container(app);
      await container.read(achievementSyncProvider).run();

      final firstAfter = await _rows(app.db, first.id);
      for (final old in firstBefore) {
        expect(firstAfter, contains(old), reason: old.achievementKey);
      }
      expect(await _stored(app.db, first.id), {
        for (final r in firstBefore) r.achievementKey: r.unlockedOn,
        for (final MapEntry(:key, :value) in expectedFor(first).entries)
          key.id: value,
        'day_75': _on(first, 75),
      });
      // Nothing celebrated, the active arc untouched.
      expect(container.read(celebrationQueueProvider), isEmpty);
      expect(await _rows(app.db, second.id), secondBefore);
    });

    test(
      'E. several completed arcs each earn from their own history only',
      () async {
        final first = await firstArc();
        // Arc 2: only seven days of No Junk Food.
        await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
        final second = await app.winterArc.startWinterArc();
        await _live(app, second, 1, 7, habits: const ['no_junk_food']);
        _goTo(app, second, 93);
        await app.lifecycle.reconcile();
        await app.achievements.reconcile();
        // A third arc in setup: no home arc, nothing to celebrate.
        await app.winterArc.startNewArc(NewArcBaseline.fresh);
        await _forgetNewUnlocks(app.db);

        final backfill = await app.achievements.backfillCatalog();
        expect(backfill.home.isEmpty, isTrue);
        expect(
          backfill.historical.keys,
          unorderedEquals([first.id, second.id]),
        );
        expect(_byKey(backfill.historical[first.id]!), {
          ...expectedFor(first),
          AchievementKey.day75: _on(first, 75),
        });
        expect(_byKey(backfill.historical[second.id]!), {
          AchievementKey.noJunk7: _on(second, 7),
          AchievementKey.day14: _on(second, 14),
          AchievementKey.day60: _on(second, 60),
          AchievementKey.day75: _on(second, 75),
        });
        final sessions = await app.sessions.listSessions();
        final setup = sessions.singleWhere(
          (s) => s.status == WinterArcStatus.setup,
        );
        expect(await _rows(app.db, setup.id), isEmpty);
        expect((await app.achievements.backfillCatalog()).isEmpty, isTrue);
      },
    );
  });

  group('F. a new achievement earned today stays provisional', () {
    setUp(() async {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
    });

    Future<WinterArcSession> arc() async =>
        (await app.sessions.currentSession())!;

    Future<void> undo(String habitId) => app.tracking.perform(
      habitId: habitId,
      action: habitId == 'no_junk_food'
          ? HabitAction.undoCompletion
          : HabitAction.decrement,
      date: app.clock.today(),
    );

    test('a 14-day streak, Perfect Day 25, and 30-day totals and runs '
        'follow today', () async {
      final a = await arc();
      await _live(app, a, 1, 13);

      // Day 14: Day 14 itself is earned by taking part; the streaks by
      // today's completions.
      _goTo(app, a, 14);
      expect(_byKey(await app.achievements.reconcile()), {
        AchievementKey.day14: _on(a, 14),
      });
      for (final id in _defaults) {
        await completeHabit(app, id);
      }
      expect(
        (await app.achievements.reconcile()).map((u) => u.key),
        contains(AchievementKey.streak14),
      );
      // One habit undone: the others still have 14 days.
      await undo('no_junk_food');
      expect((await app.achievements.sync()).revoked, isEmpty);
      for (final id in _defaults.take(3)) {
        await undo(id);
      }
      expect((await app.achievements.sync()).revoked.map((u) => u.key), [
        AchievementKey.streak14,
      ]);
      expect(await _stored(app.db, a.id), contains('day_14'));
      expect(await _stored(app.db, a.id), isNot(contains('streak_14')));
      await completeHabit(app, 'water');
      expect((await app.achievements.reconcile()).map((u) => u.key), [
        AchievementKey.streak14,
      ]);
      for (final id in _defaults) {
        await completeHabit(app, id);
      }
      await app.achievements.reconcile();

      await _live(app, a, 15, 24);
      // Day 25: the 25th Perfect Day.
      _goTo(app, a, 25);
      for (final id in _defaults) {
        await completeHabit(app, id);
      }
      expect((await app.achievements.reconcile()).map((u) => u.key), [
        AchievementKey.perfect25,
      ]);
      await undo('no_junk_food');
      expect((await app.achievements.sync()).revoked.map((u) => u.key), [
        AchievementKey.perfect25,
      ]);
      await completeHabit(app, 'no_junk_food');
      expect((await app.achievements.reconcile()).map((u) => u.key), [
        AchievementKey.perfect25,
      ]);

      await _live(app, a, 26, 29);
      // Day 30: Workout, Water and Learning totals, the No Junk Food run
      // and the 30-day streak, all reached today.
      _goTo(app, a, 30);
      for (final id in _defaults) {
        await completeHabit(app, id);
      }
      expect(
        (await app.achievements.reconcile()).map((u) => u.key),
        unorderedEquals([
          AchievementKey.streak30,
          AchievementKey.noJunk30,
          AchievementKey.workout30,
          AchievementKey.water30,
          AchievementKey.learning30,
        ]),
      );
      await undo('workout');
      expect((await app.achievements.sync()).revoked.map((u) => u.key), [
        AchievementKey.workout30,
      ]);
      await undo('no_junk_food');
      expect((await app.achievements.sync()).revoked.map((u) => u.key), [
        AchievementKey.noJunk30,
      ]);
      // Past unlocks stay whatever today does.
      final stored = await _stored(app.db, a.id);
      expect(stored['no_junk_7'], _on(a, 7));
      expect(stored['perfect_25'], _on(a, 25));
      expect(stored['streak_14'], _on(a, 14));

      await completeHabit(app, 'workout');
      await completeHabit(app, 'no_junk_food');
      expect(
        (await app.achievements.reconcile()).map((u) => u.key),
        unorderedEquals([AchievementKey.workout30, AchievementKey.noJunk30]),
      );
      final rows = await _rows(app.db, a.id);
      expect(
        rows.map((r) => r.achievementKey).toList(),
        rows.map((r) => r.achievementKey).toSet().toList(),
        reason: 'no key stored twice',
      );
      expect((await app.achievements.sync()).isEmpty, isTrue);
    });

    test('Water counts completion against the goal of each day: a raised '
        'goal and Minimum Days are respected', () async {
      final a = await arc();
      Future<void> logWater(int glasses) async {
        for (var i = 0; i < glasses; i++) {
          await app.tracking.perform(
            habitId: 'water',
            action: HabitAction.increment,
            date: app.clock.today(),
          );
        }
      }

      // Day 1: 8 of 8. The goal then goes up to 10 (minimum 4).
      _goTo(app, a, 1);
      await logWater(8);
      await app.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 10, minimumTarget: 4),
        date: app.clock.today(),
      );
      // Days 2-20: 8 glasses no longer meet the goal.
      for (var day = 2; day <= 20; day++) {
        _goTo(app, a, day);
        await logWater(8);
      }
      // Days 21-49: Minimum Days, 4 glasses meet the minimum.
      for (var day = 21; day <= 49; day++) {
        _goTo(app, a, day);
        await app.tracking.activateMinimumDay(date: app.clock.today());
        await logWater(4);
        if (day == 48) {
          expect(
            (await app.achievements.reconcile()).map((u) => u.key),
            isNot(contains(AchievementKey.water30)),
          );
        }
      }
      final unlocked = await app.achievements.reconcile();
      expect(_byKey(unlocked)[AchievementKey.water30], _on(a, 49));
    });
  });
}
