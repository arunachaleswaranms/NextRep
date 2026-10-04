import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/xp/level_rules.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Default enabled starter habits: workout (30 min), water (8), learning
/// (20 min), no_junk_food (binary).
void main() {
  late TestApp app;
  final day1 = LocalDate(2026, 10, 1);

  Future<void> act(String habitId, HabitAction action, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await app.tracking.perform(
        habitId: habitId,
        action: action,
        date: app.clock.today(),
      );
    }
  }

  /// Completes every default habit except [except].
  Future<void> completeAll({String? except}) async {
    const steps = {'workout': 6, 'water': 8, 'learning': 4};
    for (final MapEntry(key: id, value: times) in steps.entries) {
      if (id != except) await act(id, HabitAction.increment, times: times);
    }
    if (except != 'no_junk_food') {
      await act('no_junk_food', HabitAction.complete);
    }
  }

  Future<List<String>> ledgerKeys() async => [
    for (final row in await app.db.select(app.db.xpTransactions).get())
      row.sourceKey,
  ];

  Future<int> totalXp() async => (await app.tracking.today()).totalXp;

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 7)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  group('Perfect Day XP', () {
    test('completing the final habit awards +30 exactly once', () async {
      await completeAll(except: 'no_junk_food');
      expect(await totalXp(), 3 * XpRules.habitCompletion);
      expect((await app.tracking.today()).isPerfect, isFalse);

      final commit = await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: day1,
      );
      expect(commit.settlement.ledger.perfectDayGranted, isTrue);
      expect(commit.xpAfter - commit.xpBefore, 15 + XpRules.perfectDayBonus);

      final today = await app.tracking.today();
      expect(today.isPerfect, isTrue);
      expect(today.totalXp, 4 * 15 + XpRules.perfectDayBonus);
      expect(today.perfectDays.total, 1);
      expect(
        (await ledgerKeys()).where((k) => k == XpRules.perfectDayKey(day1)),
        hasLength(1),
      );
    });

    test('repeated actions and refreshes never duplicate the bonus', () async {
      await completeAll();
      await act('no_junk_food', HabitAction.complete, times: 3);
      await act('water', HabitAction.increment, times: 3);
      for (var i = 0; i < 3; i++) {
        await app.tracking.today();
        await app.tracking.journey();
      }
      expect(await totalXp(), 4 * 15 + 30);
    });

    test('undo revokes the bonus and re-completing restores it once', () async {
      await completeAll();
      await act('no_junk_food', HabitAction.undoCompletion);
      var today = await app.tracking.today();
      expect(today.isPerfect, isFalse);
      expect(today.totalXp, 3 * 15);
      expect(today.perfectDays.total, 0);
      expect(await ledgerKeys(), isNot(contains(XpRules.perfectDayKey(day1))));

      await act('no_junk_food', HabitAction.complete);
      today = await app.tracking.today();
      expect(today.isPerfect, isTrue);
      expect(today.totalXp, 4 * 15 + 30);

      // Undo via a numeric habit dropping below its target.
      await act('water', HabitAction.decrement);
      expect(await totalXp(), 3 * 15);
      await act('water', HabitAction.increment);
      expect(await totalXp(), 4 * 15 + 30);
      expect(
        (await ledgerKeys()).where((k) => k.startsWith('perfect_day:')),
        hasLength(1),
      );
    });

    test('concurrent final-habit actions cannot duplicate the bonus', () async {
      await completeAll(except: 'no_junk_food');
      await Future.wait([
        for (var i = 0; i < 10; i++)
          app.tracking.perform(
            habitId: 'no_junk_food',
            action: HabitAction.complete,
            date: day1,
          ),
      ]);
      expect(await totalXp(), 4 * 15 + 30);
      expect(await ledgerKeys(), hasLength(5));
    });

    test('the bonus is per date', () async {
      await completeAll();
      app.clock.current = DateTime(2026, 10, 2, 7);
      await completeAll();
      final today = await app.tracking.today();
      expect(today.totalXp, 2 * (4 * 15 + 30));
      expect(today.perfectDays.streak.current, 2);
    });
  });

  group('levels', () {
    test('level is derived from persisted XP and crosses a boundary', () async {
      expect((await app.tracking.today()).level.level, 1);
      // Day 1-2 perfect = 180 XP; Day 3 perfect pushes past 250.
      await completeAll();
      app.clock.current = DateTime(2026, 10, 2, 7);
      await completeAll();
      app.clock.current = DateTime(2026, 10, 3, 7);
      await completeAll(except: 'no_junk_food');
      expect((await app.tracking.today()).totalXp, 225);

      final commit = await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: app.clock.today(),
      );
      expect(commit.xpBefore, 225);
      expect(commit.xpAfter, 270);
      expect(
        LevelRules.levelUp(beforeXp: commit.xpBefore, afterXp: commit.xpAfter),
        2,
      );
      final level = (await app.tracking.today()).level;
      expect(level.level, 2);
      expect(level.xpIntoLevel, 20);
    });
  });

  group('Minimum Day', () {
    test('switches targets to minimums and keeps progress', () async {
      await act('water', HabitAction.increment, times: 2);
      await act('workout', HabitAction.increment, times: 3); // 15 min

      final commit = await app.tracking.activateMinimumDay(date: day1);
      expect(commit.value, isTrue);

      final today = await app.tracking.today();
      expect(today.mode, DayMode.minimum);
      final byId = {for (final e in today.entries) e.habit.id: e};
      expect(byId['workout']!.target, 10);
      expect(byId['water']!.target, 3);
      expect(byId['learning']!.target, 5);
      expect(byId['no_junk_food']!.target, 1);
      // Progress is retained, never reduced.
      expect(byId['water']!.progress.currentValue, 2);
      expect(byId['workout']!.progress.currentValue, 15);
      // Workout already meets its 10 min minimum: complete with XP.
      expect(byId['workout']!.progress.completed, isTrue);
      expect(byId['water']!.progress.completed, isFalse);
      expect(today.totalXp, 15);
      expect(
        commit.settlement.ledger.habitAwardFor('workout')?.amount,
        XpRules.habitCompletion,
      );
    });

    test(
      'minimum completion earns habit XP but no Perfect Day bonus',
      () async {
        await app.tracking.activateMinimumDay(date: day1);
        await act('workout', HabitAction.increment, times: 2);
        await act('water', HabitAction.increment, times: 3);
        await act('learning', HabitAction.increment);
        await act('no_junk_food', HabitAction.complete);
        final today = await app.tracking.today();
        expect(today.record.isMinimumComplete, isTrue);
        expect(today.isPerfect, isFalse);
        expect(today.totalXp, 4 * 15);
        expect(today.perfectDays.total, 0);
        expect(today.streakFor('water').current, 1);
        final journey = await app.tracking.journey();
        expect(journey.days.first.state, JourneyDayState.minimumComplete);
      },
    );

    test('activation is idempotent and XP stays exact', () async {
      await act('workout', HabitAction.increment, times: 3);
      final first = await app.tracking.activateMinimumDay(date: day1);
      final again = await app.tracking.activateMinimumDay(date: day1);
      expect(first.value, isTrue);
      expect(again.value, isFalse);
      expect(again.settlement.hasWrites, isFalse);
      expect(await totalXp(), 15);
    });

    test('is one-way: no action reverts the day to normal', () async {
      await app.tracking.activateMinimumDay(date: day1);
      await completeAll();
      await act('no_junk_food', HabitAction.undoCompletion);
      expect((await app.tracking.today()).mode, DayMode.minimum);
      final modes = await app.db.select(app.db.dayModes).get();
      expect(modes.single.mode, DayMode.minimum);
    });

    test('only applies to the current challenge date', () async {
      app.clock.current = DateTime(2026, 10, 2, 7);
      expect(
        app.tracking.activateMinimumDay(date: day1),
        _failsWith(DomainRule.staleDay),
      );
      expect(
        app.tracking.activateMinimumDay(date: day1.addDays(2)),
        _failsWith(DomainRule.staleDay),
      );
      app.clock.current = DateTime(2027, 1, 1, 7);
      expect(
        app.tracking.activateMinimumDay(date: LocalDate(2027, 1, 1)),
        _failsWith(DomainRule.arcNotRunningToday),
      );
      expect(await app.db.select(app.db.dayModes).get(), isEmpty);
    });

    test('does not carry over to the next day', () async {
      await app.tracking.activateMinimumDay(date: day1);
      app.clock.current = DateTime(2026, 10, 2, 7);
      final today = await app.tracking.today();
      expect(today.mode, DayMode.normal);
      expect(today.entries.firstWhere((e) => e.habit.id == 'water').target, 8);
    });

    test('is rejected once today is already a Perfect Day', () async {
      await completeAll();
      expect(
        app.tracking.activateMinimumDay(date: day1),
        _failsWith(DomainRule.dayAlreadyPerfect),
      );
      expect(await totalXp(), 4 * 15 + 30);
    });

    test('Minimum Day keeps a habit streak alive across days', () async {
      await act('water', HabitAction.increment, times: 8);
      app.clock.current = DateTime(2026, 10, 2, 7);
      await app.tracking.activateMinimumDay(date: app.clock.today());
      await act('water', HabitAction.increment, times: 3);
      app.clock.current = DateTime(2026, 10, 3, 7);
      await act('water', HabitAction.increment, times: 8);
      final today = await app.tracking.today();
      expect(today.streakFor('water').current, 3);
      expect(today.perfectDays.streak.current, 0);
    });
  });

  // Phase 3: goal and on/off edits take effect from the next challenge day;
  // renames apply immediately. See habit_edit_timing_test.dart for the
  // effective-date rules themselves.
  group('habit editing', () {
    Future<void> edit(String habitId, HabitEdit edit) => app.tracking.editHabit(
      habitId: habitId,
      edit: edit,
      date: app.clock.today(),
    );

    test('a target edit does not alter a prior day\'s completion', () async {
      await act('water', HabitAction.increment, times: 8);
      app.clock.current = DateTime(2026, 10, 10, 7);
      await edit('water', const HabitEdit(target: 10));

      final journey = await app.tracking.journey();
      final water1 = journey.days.first.record!.entryFor('water')!;
      expect(water1.target, 8);
      expect(water1.progress.currentValue, 8);
      expect(water1.progress.completed, isTrue);
      expect(journey.days.first.xpEarned, 15);

      app.clock.current = DateTime(2026, 10, 11, 7);
      final today = await app.tracking.today();
      expect(today.entries.firstWhere((e) => e.habit.id == 'water').target, 10);
    });

    test('disabling a habit does not create past Perfect Days', () async {
      // Day 1: everything but no_junk_food.
      await completeAll(except: 'no_junk_food');
      app.clock.current = DateTime(2026, 10, 2, 7);
      await edit('no_junk_food', const HabitEdit(enabled: false));

      final journey = await app.tracking.journey();
      expect(journey.days.first.state, JourneyDayState.partial);
      expect(journey.perfectDays.total, 0);

      app.clock.current = DateTime(2026, 10, 3, 7);
      final today = await app.tracking.today();
      expect(
        today.entries.map((e) => e.habit.id),
        isNot(contains('no_junk_food')),
      );
    });

    test('a target edit cannot change today\'s completion or XP', () async {
      await completeAll();
      expect(await totalXp(), 90);

      // Raising water above today's progress no longer revokes anything.
      await edit('water', const HabitEdit(target: 10));
      var today = await app.tracking.today();
      final water = today.entries.firstWhere((e) => e.habit.id == 'water');
      expect(water.target, 8);
      expect(water.progress.completed, isTrue);
      expect(today.isPerfect, isTrue);
      expect(today.totalXp, 90);

      // A second edit the same day replaces the pending revision.
      await edit('water', const HabitEdit(target: 6));
      today = await app.tracking.today();
      expect(today.totalXp, 90);
      final revisions = await app.db.select(app.db.habitRevisions).get();
      expect(revisions, hasLength(1));
      expect(revisions.single.target, 6);
      expect(revisions.single.effectiveFrom, LocalDate(2026, 10, 2));
    });

    test('disabling an unfinished habit cannot make today Perfect', () async {
      await completeAll(except: 'learning');
      await edit('learning', const HabitEdit(enabled: false));
      final today = await app.tracking.today();
      expect(today.isPerfect, isFalse);
      expect(today.totalXp, 3 * 15);
    });

    test('rename applies everywhere, edits are validated', () async {
      await edit('water', const HabitEdit(title: '  Hydrate  '));
      final settings = await app.tracking.habitSettings();
      expect(
        settings.habits.firstWhere((s) => s.habit.id == 'water').habit.title,
        'Hydrate',
      );
      expect(
        edit('water', const HabitEdit(title: ' ')),
        _failsWith(DomainRule.invalidHabitEdit),
      );
      expect(
        edit('water', const HabitEdit(minimumTarget: 9)),
        _failsWith(DomainRule.invalidHabitEdit),
      );
      expect(
        edit('no_junk_food', const HabitEdit(target: 2)),
        _failsWith(DomainRule.invalidHabitEdit),
      );
      expect(
        edit('nope', const HabitEdit(target: 2)),
        _failsWith(DomainRule.habitNotFound),
      );
    });

    test('the last enabled habit cannot be disabled', () async {
      for (final id in ['workout', 'water', 'learning']) {
        await edit(id, const HabitEdit(enabled: false));
      }
      expect(
        edit('no_junk_food', const HabitEdit(enabled: false)),
        _failsWith(DomainRule.lastEnabledHabit),
      );
    });

    test('editing a past day is impossible', () async {
      app.clock.current = DateTime(2026, 10, 3, 7);
      expect(
        app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(target: 4),
          date: day1,
        ),
        _failsWith(DomainRule.staleDay),
      );
    });

    test('disabling and re-enabling on the same day changes nothing', () async {
      await act('water', HabitAction.increment, times: 8);
      await edit('water', const HabitEdit(enabled: false));
      expect(await totalXp(), 15);
      await edit('water', const HabitEdit(enabled: true));

      app.clock.current = DateTime(2026, 10, 2, 7);
      final today = await app.tracking.today();
      expect(today.entries.map((e) => e.habit.id), contains('water'));
      expect(today.totalXp, 15);
    });
  });

  group('persistence across restart', () {
    late Directory dir;
    late File file;
    TestApp launch() => TestApp(AppDatabase(NativeDatabase(file)), app.clock);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nextrep_p2_');
      file = File('${dir.path}/nextrep.sqlite');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('Minimum Day, edits and the bonus survive a relaunch', () async {
      var run = launch();
      await run.winterArc.beginSetup();
      await run.winterArc.startWinterArc();
      await run.tracking.editHabit(
        habitId: 'water',
        edit: const HabitEdit(target: 6, minimumTarget: 2, title: 'Hydrate'),
        date: day1,
      );
      await run.tracking.activateMinimumDay(date: day1);
      await run.tracking.perform(
        habitId: 'water',
        action: HabitAction.increment,
        date: day1,
      );
      await run.db.close();

      run = launch();
      addTearDown(run.db.close);
      final today = await run.tracking.today();
      expect(today.mode, DayMode.minimum);
      final water = today.entries.firstWhere((e) => e.habit.id == 'water');
      expect(water.habit.title, 'Hydrate'); // renames apply immediately
      expect(water.config.target, 8); // goal edits wait for tomorrow
      expect(water.target, 3);
      expect(water.progress.currentValue, 1);

      // Still one-way and idempotent after restart.
      final again = await run.tracking.activateMinimumDay(date: day1);
      expect(again.value, isFalse);
      await run.tracking.perform(
        habitId: 'water',
        action: HabitAction.increment,
        date: day1,
      );
      expect((await run.tracking.today()).totalXp, 0);

      // The edit made on Day 1 is in effect on Day 2, after the restart.
      run.clock.current = DateTime(2026, 10, 2, 7);
      final day2 = await run.tracking.today();
      final water2 = day2.entries.firstWhere((e) => e.habit.id == 'water');
      expect(day2.mode, DayMode.normal);
      expect(water2.config.target, 6);
      expect(water2.config.minimumTarget, 2);
    });
  });
}
