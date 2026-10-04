import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

int _t(int hour, int minute) => NightTime(hour, minute).value;

void main() {
  group('NightTime', () {
    test('normalizes the night window so after midnight sorts last', () {
      expect(NightTime(18, 0).value, 1080);
      expect(NightTime(23, 59).value, 1439);
      expect(NightTime(0, 0).value, 1440, reason: 'midnight is never 0');
      expect(NightTime(1, 0).value, 1500);
      expect(NightTime(5, 59).value, 1799);
      expect(NightTime.fromValue(1500), NightTime(1, 0));
      expect(NightTime(0, 45).hhmm, '00:45');
      expect(NightTime(23, 5).hhmm, '23:05');
      expect(NightTime(0, 30).isAtOrBefore(NightTime(1, 0)), isTrue);
    });

    test('rejects daytime and invalid times', () {
      for (final (h, m) in [(6, 0), (12, 0), (17, 59), (24, 0), (1, 60)]) {
        expect(NightTime.tryClock(h, m), isNull, reason: '$h:$m');
        expect(() => NightTime(h, m), throwsArgumentError);
      }
      for (final v in [0, 1079, 1800, -1]) {
        expect(NightTime.isValidValue(v), isFalse, reason: '$v');
        expect(() => NightTime.fromValue(v), throwsArgumentError);
      }
      expect(
        HabitEditRules.isValidConfig(
          HabitType.timeBefore,
          const HabitConfig(target: 720, minimumTarget: 720, enabled: true),
        ),
        isFalse,
        reason: '12:00 is not a supported target',
      );
    });
  });

  group('completion rule', () {
    const type = HabitType.timeBefore;
    for (final (target, actual, done) in [
      ((1, 0), (0, 30), true),
      ((1, 0), (1, 0), true),
      ((1, 0), (1, 1), false),
      ((23, 30), (23, 10), true),
      ((23, 30), (0, 10), false),
    ]) {
      test('target ${target.$1}:${target.$2} + actual ${actual.$1}:'
          '${actual.$2} → ${done ? 'complete' : 'incomplete'}', () {
        expect(
          type.isCompletedBy(
            _t(actual.$1, actual.$2),
            _t(target.$1, target.$2),
          ),
          done,
        );
      });
    }

    test('not logged (0) is incomplete', () {
      expect(type.isCompletedBy(0, _t(1, 0)), isFalse);
    });
  });

  group('tracking', () {
    late TestApp app;
    late LocalDate day1;

    /// A rolling arc with Sleep Before Target (goal 01:00) and Water on, so
    /// a Perfect Day needs both. Starts on 1 Oct 2026 08:00.
    setUp(() async {
      app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 8)));
      await app.winterArc.beginSetup();
      for (final habit in await app.winterArc.setupHabits()) {
        await app.winterArc.setHabitEnabled(
          habit.id,
          enabled: habit.id == 'sleep_before' || habit.id == 'water',
        );
      }
      await app.winterArc.editSetupHabit(
        'sleep_before',
        HabitDraft(
          title: 'Sleep Before Target',
          type: HabitType.timeBefore,
          iconKey: 'sleep',
          target: _t(1, 0),
        ),
      );
      await app.winterArc.startWinterArc();
      day1 = app.clock.today();
    });
    tearDown(() => app.db.close());

    Future<DailyHabitProgress> sleep() async =>
        (await app.tracking.today()).record.entryFor('sleep_before')!.progress;

    Future<void> setTime(int h, int m) => app.tracking.perform(
      habitId: 'sleep_before',
      action: HabitAction.setTime,
      time: NightTime(h, m),
      date: app.clock.today(),
    );

    Future<void> clear() => app.tracking.perform(
      habitId: 'sleep_before',
      action: HabitAction.clearTime,
      date: app.clock.today(),
    );

    Future<int> xp() async => (await app.tracking.today()).totalXp;

    Future<void> completeWater() async {
      for (var i = 0; i < 8; i++) {
        await app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: app.clock.today(),
        );
      }
    }

    test(
      'unset is incomplete; setTime persists; clearTime returns to unset',
      () async {
        expect((await sleep()).completed, isFalse);
        expect((await sleep()).currentValue, 0);

        await setTime(0, 45);
        final stored = (await app.progress.progressOn(1, day1)).single;
        expect(stored.currentValue, _t(0, 45));
        expect(stored.completed, isTrue);

        await clear();
        expect((await sleep()).currentValue, 0);
        expect((await sleep()).completed, isFalse);
      },
    );

    test('a late time stays recorded, just not completed', () async {
      await setTime(1, 25);
      final progress = await sleep();
      expect(progress.currentValue, _t(1, 25));
      expect(progress.completed, isFalse);
      expect(await xp(), 0);
    });

    test('incompatible actions are rejected', () async {
      for (final action in [
        HabitAction.increment,
        HabitAction.decrement,
        HabitAction.complete,
        HabitAction.undoCompletion,
      ]) {
        await expectLater(
          app.tracking.perform(
            habitId: 'sleep_before',
            action: action,
            date: day1,
          ),
          _failsWith(DomainRule.actionNotSupportedForHabitType),
          reason: action.name,
        );
      }
      // setTime / clearTime belong to clock-time habits only.
      await expectLater(
        app.tracking.perform(
          habitId: 'water',
          action: HabitAction.setTime,
          time: NightTime(23, 0),
          date: day1,
        ),
        _failsWith(DomainRule.actionNotSupportedForHabitType),
      );
      await expectLater(
        app.tracking.perform(
          habitId: 'sleep_before',
          action: HabitAction.setTime,
          date: day1,
        ),
        _failsWith(DomainRule.actionNotSupportedForHabitType),
        reason: 'setTime needs a time',
      );
    });

    test('XP: pass grants once, repeats add nothing, pass → fail revokes, '
        'fail → pass restores once', () async {
      await setTime(0, 45);
      expect(await xp(), XpRules.habitCompletion);
      await setTime(0, 45);
      await setTime(0, 50);
      expect(await xp(), XpRules.habitCompletion, reason: 'idempotent');

      await setTime(1, 15);
      expect(await xp(), 0);
      expect((await sleep()).completed, isFalse);

      await setTime(0, 45);
      expect(await xp(), XpRules.habitCompletion);
      final ledger = await app.db.select(app.db.xpTransactions).get();
      expect(ledger, hasLength(1));
    });

    test(
      'the last habit passing makes a Perfect Day; failing revokes it',
      () async {
        await completeWater();
        expect((await app.tracking.today()).isPerfect, isFalse);

        await setTime(0, 30);
        final perfect = await app.tracking.today();
        expect(perfect.isPerfect, isTrue);
        expect(
          perfect.totalXp,
          2 * XpRules.habitCompletion + XpRules.perfectDayBonus,
        );

        await setTime(1, 30);
        final late = await app.tracking.today();
        expect(late.isPerfect, isFalse);
        expect(late.totalXp, XpRules.habitCompletion);

        await setTime(0, 30);
        expect(
          (await app.tracking.today()).totalXp,
          2 * XpRules.habitCompletion + XpRules.perfectDayBonus,
        );
        await clear();
        expect((await app.tracking.today()).totalXp, XpRules.habitCompletion);
      },
    );

    test(
      'Minimum Day keeps the same clock target and still pays habit XP',
      () async {
        await app.tracking.activateMinimumDay(date: day1);
        final entry = (await app.tracking.today()).record.entryFor(
          'sleep_before',
        )!;
        expect(entry.target, _t(1, 0));

        await setTime(1, 15);
        expect((await sleep()).completed, isFalse);
        await setTime(0, 45);
        expect((await sleep()).completed, isTrue);
        await completeWater();
        final today = await app.tracking.today();
        expect(today.mode, DayMode.minimum);
        expect(today.record.isMinimumComplete, isTrue);
        expect(today.isPerfect, isFalse);
        expect(today.totalXp, 2 * XpRules.habitCompletion);
        expect(today.streakFor('sleep_before').current, 1);
      },
    );

    test(
      'a target edit applies from tomorrow; past days keep their target',
      () async {
        await setTime(0, 45);
        final outcome = await app.tracking.editHabit(
          habitId: 'sleep_before',
          edit: HabitEdit(target: _t(0, 30)),
          date: day1,
        );
        expect(outcome.value.configFrom, day1.addDays(1));
        // Today unchanged: 00:45 still meets 01:00.
        final today = (await app.tracking.today()).record.entryFor(
          'sleep_before',
        )!;
        expect(today.target, _t(1, 0));
        expect(today.progress.completed, isTrue);

        app.clock.current = DateTime(2026, 10, 2, 8);
        final tomorrow = (await app.tracking.today()).record.entryFor(
          'sleep_before',
        )!;
        expect(tomorrow.target, _t(0, 30));
        expect(tomorrow.config.minimumTarget, _t(0, 30));
        await setTime(0, 45);
        expect((await sleep()).completed, isFalse);

        final history = await app.tracking.history();
        final past = history.recordOn(day1).entryFor('sleep_before')!;
        expect(past.target, _t(1, 0));
        expect(past.progress.completed, isTrue);
      },
    );

    test('on Day 92 the clock target can no longer change', () async {
      app.clock.current = DateTime(2026, 12, 31, 8);
      await expectLater(
        app.tracking.editHabit(
          habitId: 'sleep_before',
          edit: HabitEdit(target: _t(23, 0)),
          date: app.clock.today(),
        ),
        _failsWith(DomainRule.noNextChallengeDay),
      );
    });

    test('a clock target outside the night window is rejected', () async {
      await expectLater(
        app.tracking.editHabit(
          habitId: 'sleep_before',
          edit: const HabitEdit(target: 600),
          date: day1,
        ),
        _failsWith(DomainRule.invalidHabitEdit),
      );
    });
  });
}
