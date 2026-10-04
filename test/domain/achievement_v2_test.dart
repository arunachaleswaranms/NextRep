import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/achievement/achievement_repository.dart';
import 'package:nextrep/domain/achievement/achievement_rules.dart';
import 'package:nextrep/domain/achievement/achievement_service.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';

import '../support/builders.dart';
import '../support/fakes.dart';

Map<AchievementKey, LocalDate> _earned(
  ArcHistory history, {
  Iterable<int> reflectionDays = const [],
}) => {
  for (final e in AchievementRules.evaluate(
    AchievementContext(
      history: history,
      reflectionDates: [for (final d in reflectionDays) dayN(d)],
    ),
  ))
    e.key: e.earnedOn,
};

Map<int, List<String>> _allDone(Iterable<int> days) => {
  for (final d in days) d: const ['water', 'junk'],
};

const _phase3 = {
  AchievementKey.firstRep,
  AchievementKey.firstPerfect,
  AchievementKey.streak3,
  AchievementKey.streak7,
  AchievementKey.perfect3,
  AchievementKey.minimumComplete,
  AchievementKey.level2,
  AchievementKey.level3,
  AchievementKey.halfway,
  AchievementKey.summit,
};

void main() {
  group('catalog v2 rules', () {
    test('Looking Inward: the first reflection, on its date', () {
      final arc = arcOf(today: 9);
      expect(_earned(arc)[AchievementKey.firstReflection], isNull);
      expect(
        _earned(arc, reflectionDays: [6, 4])[AchievementKey.firstReflection],
        dayN(4),
      );
    });

    test('Seven Check-ins: 7 reflected days, not necessarily in a row', () {
      final arc = arcOf(today: 30);
      final six = [1, 3, 5, 8, 13, 21];
      expect(
        _earned(arc, reflectionDays: six)[AchievementKey.reflections7],
        isNull,
      );
      expect(
        _earned(arc, reflectionDays: [...six, 29])[AchievementKey.reflections7],
        dayN(29),
      );
    });

    test('reflection dates outside the elapsed arc never count', () {
      final arc = arcOf(today: 5);
      final earned = _earned(arc, reflectionDays: [-3, 0, 6, 7, 8, 9, 10]);
      expect(earned[AchievementKey.firstReflection], isNull);
      // A date counted twice is still one check-in.
      expect(
        AchievementContext(
          history: arc,
          reflectionDates: [dayN(2), dayN(2), dayN(1)],
        ).reflectionDates,
        [dayN(1), dayN(2)],
      );
    });

    test('Adaptable: 3 fully completed Minimum Days', () {
      final modes = {
        2: DayMode.minimum,
        4: DayMode.minimum,
        6: DayMode.minimum,
        7: DayMode.minimum,
      };
      // Day 6 is a Minimum Day left unfinished.
      final arc = arcOf(
        today: 9,
        done: _allDone([2, 4, 7]),
        partial: {
          6: {'water': 1},
        },
        modes: modes,
      );
      final earned = _earned(arc);
      expect(earned[AchievementKey.minimumComplete], dayN(2));
      expect(earned[AchievementKey.minimum3], dayN(7));
      expect(
        _earned(
          arcOf(today: 9, done: _allDone([2, 4]), modes: modes),
        )[AchievementKey.minimum3],
        isNull,
      );
    });

    test('Ten Clean Sweeps: the 10th Perfect Day', () {
      final days = [1, 2, 3, 5, 6, 8, 9, 10, 12, 15, 16];
      final earned = _earned(arcOf(today: 20, done: _allDone(days)));
      expect(earned[AchievementKey.perfect3], dayN(3));
      expect(earned[AchievementKey.perfect10], dayN(15));
      expect(
        _earned(
          arcOf(today: 20, done: _allDone(days.take(9))),
        )[AchievementKey.perfect10],
        isNull,
      );
    });

    test('Stronger Every Day: Level 5 (1,000 XP)', () {
      final earned = _earned(
        arcOf(today: 9, xp: {1: 400, 3: 350, 5: 249, 8: 1}),
      );
      expect(earned[AchievementKey.level3], dayN(3));
      expect(earned[AchievementKey.level5], dayN(8));
      expect(
        _earned(arcOf(today: 9, xp: {1: 999}))[AchievementKey.level5],
        isNull,
      );
    });

    test('Phase 3 achievements keep their exact semantics', () {
      final arc = arcOf(
        today: 50,
        done: _allDone([1, 2, 3, 4, 5, 6, 7]),
        modes: {9: DayMode.minimum},
        xp: {1: 300, 2: 300},
      );
      final without = _earned(arc);
      final withReflections = _earned(arc, reflectionDays: [1, 2, 3, 4]);
      Map<AchievementKey, LocalDate> phase3(Map<AchievementKey, LocalDate> m) =>
          {
            for (final e in m.entries)
              if (_phase3.contains(e.key)) e.key: e.value,
          };
      expect(phase3(withReflections), phase3(without));
      expect(phase3(without), {
        AchievementKey.firstRep: dayN(1),
        AchievementKey.firstPerfect: dayN(1),
        AchievementKey.streak3: dayN(3),
        AchievementKey.streak7: dayN(7),
        AchievementKey.perfect3: dayN(3),
        AchievementKey.level2: dayN(1),
        AchievementKey.level3: dayN(2),
        AchievementKey.halfway: dayN(46),
      });
    });

    test('there are 15 achievements, none granting XP', () {
      expect(AchievementCatalog.all, hasLength(15));
      expect(
        AchievementCatalog.of(AchievementKey.firstReflection).title,
        'Looking Inward',
      );
      expect(
        AchievementCatalog.of(AchievementKey.reflections7).title,
        'Seven Check-ins',
      );
      expect(AchievementCatalog.of(AchievementKey.minimum3).title, 'Adaptable');
      expect(
        AchievementCatalog.of(AchievementKey.perfect10).title,
        'Ten Clean Sweeps',
      );
      expect(
        AchievementCatalog.of(AchievementKey.level5).title,
        'Stronger Every Day',
      );
    });
  });

  group('reflection achievements, persisted', () {
    late TestApp app;

    setUp(() async {
      app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 21)));
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
    });
    tearDown(() => app.db.close());

    Future<void> reflect(int day, Mood mood) async {
      app.clock.current = DateTime(2026, 10, day, 21);
      final arc = (await app.winterArc.currentSession())!;
      await app.reflections.save(
        sessionId: arc.id,
        date: app.clock.today(),
        draft: ReflectionDraft(mood: mood),
      );
    }

    test('unlocked once, retried without duplicates, never with XP', () async {
      await reflect(1, Mood.good);
      final first = await app.achievements.reconcile();
      expect(first.map((u) => u.key), [AchievementKey.firstReflection]);
      expect(first.single.unlockedOn, LocalDate(2026, 10, 1));
      // Editing today's reflection and retrying adds nothing.
      await reflect(1, Mood.excellent);
      expect(await app.achievements.reconcile(), isEmpty);
      expect(await app.achievements.reconcile(), isEmpty);

      for (final day in [2, 4, 5, 7, 8]) {
        await reflect(day, Mood.okay);
      }
      expect(await app.achievements.reconcile(), isEmpty); // 6 days so far
      await reflect(10, Mood.rough);
      final seventh = await app.achievements.reconcile();
      expect(seventh.map((u) => u.key), [AchievementKey.reflections7]);
      expect(seventh.single.unlockedOn, LocalDate(2026, 10, 10));
      expect(
        await app.db.select(app.db.achievementUnlocks).get(),
        hasLength(2),
      );
      expect((await app.tracking.today()).totalXp, 0);
    });

    test('a failed reconciliation never undoes the reflection', () async {
      final broken = AchievementService(
        sessions: app.sessions,
        progress: app.progress,
        achievements: _FailingAchievements(),
        reflections: app.reflectionStore,
        clock: app.clock,
      );
      await reflect(1, Mood.good);
      await expectLater(broken.reconcile(), throwsA(isA<PersistenceFailure>()));
      expect((await app.reflections.journal()).todayEntry!.mood, Mood.good);
      // The next good run heals it.
      expect(
        (await app.achievements.reconcile()).single.key,
        AchievementKey.firstReflection,
      );
    });
  });
}

final class _FailingAchievements implements AchievementRepository {
  @override
  Future<List<AchievementUnlock>> unlocks(int sessionId) async => const [];

  @override
  Future<List<AchievementUnlock>> unlockNew(
    int sessionId,
    List<EarnedAchievement> earned, {
    required DateTime at,
  }) async => throw const PersistenceFailure('disk full');
}
