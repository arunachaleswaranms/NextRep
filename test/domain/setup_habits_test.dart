import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/data/drift_habit_repository.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/habit/starter_habits.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Predictable ids for tests: custom_000…01, custom_000…02, ...
final class _CountingIds implements HabitIdGenerator {
  var _n = 0;

  @override
  String next() => 'custom_${(++_n).toRadixString(16).padLeft(32, '0')}';
}

void main() {
  late TestApp app;
  late WinterArcService service;

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 4, 9)));
    service = WinterArcService(
      sessions: app.sessions,
      habits: app.habits,
      clock: app.clock,
      ids: _CountingIds(),
    );
    await service.beginSetup();
  });
  tearDown(() => app.db.close());

  Future<Habit> byId(String id) async =>
      (await service.setupHabits()).singleWhere((h) => h.id == id);

  group('templates', () {
    test('the catalogue is bundled, with stable ids and valid configs', () {
      final ids = HabitTemplateCatalog.all.map((t) => t.id).toList();
      expect(ids, [
        'workout',
        'water',
        'learning',
        'english',
        'no_junk_food',
        'sleep_before',
        'meditation',
        'journal',
      ]);
      expect(ids.toSet(), hasLength(ids.length));
      for (final t in HabitTemplateCatalog.all) {
        expect(
          HabitEditRules.isValidConfig(
            t.type,
            t.toHabit(sortOrder: 0, createdAt: DateTime(2026)).baseline,
          ),
          isTrue,
          reason: t.id,
        );
      }
      expect(ids, isNot(contains('sleep_on_time')), reason: 'legacy id');
      expect(
        HabitTemplateCatalog.byId('sleep_before')!.type,
        HabitType.timeBefore,
      );
    });

    test('a fresh setup seeds the starter templates', () async {
      final habits = await service.setupHabits();
      expect(habits.map((h) => h.id), StarterHabits.all.map((t) => t.id));
      expect(habits.where((h) => h.enabled).map((h) => h.id), [
        'workout',
        'water',
        'learning',
        'no_junk_food',
      ]);
    });

    test('Sleep Before Target creates a timeBefore habit', () async {
      await service.deleteSetupHabit('sleep_before');
      final habit = await service.addTemplateHabit('sleep_before');
      expect(habit.type, HabitType.timeBefore);
      expect(habit.target, NightTime(23, 30).value);
      expect(habit.minimumTarget, habit.target);
      expect(habit.enabled, isTrue);
      expect((await byId('sleep_before')).type, HabitType.timeBefore);
    });

    test('a template already in the arc cannot be added twice', () async {
      await expectLater(
        service.addTemplateHabit('water'),
        _failsWith(DomainRule.duplicateHabit),
      );
      final journal = await service.addTemplateHabit('journal');
      expect(journal.id, 'journal');
      await expectLater(
        service.addTemplateHabit('journal'),
        _failsWith(DomainRule.duplicateHabit),
      );
    });
  });

  group('custom habits', () {
    test('binary: no numbers, target 1', () async {
      final habit = await service.addCustomHabit(
        const HabitDraft(
          title: 'Cold shower',
          type: HabitType.binary,
          iconKey: 'heart',
          target: 7, // ignored for this type
          minimumTarget: 3,
          unit: 'x',
        ),
      );
      expect(habit.type, HabitType.binary);
      expect(habit.target, 1);
      expect(habit.minimumTarget, 1);
      expect(habit.unit, isNull);
      expect(habit.enabled, isTrue);
    });

    test('count: target, Minimum Day target and unit', () async {
      final habit = await service.addCustomHabit(
        const HabitDraft(
          title: 'Pages',
          type: HabitType.count,
          iconKey: 'learning',
          target: 20,
          minimumTarget: 5,
          unit: ' pages ',
        ),
      );
      expect(habit.type, HabitType.count);
      expect((habit.target, habit.minimumTarget, habit.unit), (20, 5, 'pages'));
    });

    test('duration: minutes and Minimum Day minutes', () async {
      final habit = await service.addCustomHabit(
        const HabitDraft(
          title: 'Stretch',
          type: HabitType.duration,
          iconKey: 'walk',
          target: 15,
          minimumTarget: 5,
        ),
      );
      expect((habit.target, habit.minimumTarget, habit.unit), (15, 5, 'min'));
    });

    test('timeBefore: a goal time, the same on Minimum Days', () async {
      final habit = await service.addCustomHabit(
        HabitDraft(
          title: 'Phone off',
          type: HabitType.timeBefore,
          iconKey: 'star',
          target: NightTime(22, 30).value,
          minimumTarget: 1, // ignored: always the target
        ),
      );
      expect(habit.type, HabitType.timeBefore);
      expect(habit.target, NightTime(22, 30).value);
      expect(habit.minimumTarget, habit.target);
      await expectLater(
        service.addCustomHabit(
          const HabitDraft(
            title: 'Lunch',
            type: HabitType.timeBefore,
            iconKey: 'star',
            target: 12 * 60,
          ),
        ),
        _failsWith(DomainRule.invalidHabitEdit),
      );
    });

    test('ids are random, unique, stable, and never the title', () async {
      final first = await service.addCustomHabit(
        const HabitDraft(
          title: 'Reading',
          type: HabitType.binary,
          iconKey: 'star',
        ),
      );
      final second = await service.addCustomHabit(
        const HabitDraft(
          title: 'Writing',
          type: HabitType.binary,
          iconKey: 'star',
        ),
      );
      expect(first.id, isNot(second.id));
      expect(SetupHabitRules.isCustomId(first.id), isTrue);
      expect(first.id.contains('reading'), isFalse);

      // Renaming keeps the id.
      await service.editSetupHabit(
        first.id,
        const HabitDraft(
          title: 'Novels',
          type: HabitType.binary,
          iconKey: 'star',
        ),
      );
      expect((await byId(first.id)).title, 'Novels');

      // The real generator: 128 random bits as 32 hex digits.
      final secure = SecureHabitIdGenerator();
      final ids = {for (var i = 0; i < 200; i++) secure.next()};
      expect(ids, hasLength(200));
      expect(ids.every(SetupHabitRules.isCustomId), isTrue);
      expect(
        SecureHabitIdGenerator(Random(1)).next(),
        SecureHabitIdGenerator(Random(1)).next(),
        reason: 'injectable for deterministic tests',
      );
    });

    test(
      'titles are trimmed; empty and duplicate names are rejected',
      () async {
        final habit = await service.addCustomHabit(
          const HabitDraft(
            title: '  Reading  ',
            type: HabitType.binary,
            iconKey: 'star',
          ),
        );
        expect(habit.title, 'Reading');
        for (final title in ['', '   ']) {
          await expectLater(
            service.addCustomHabit(
              HabitDraft(title: title, type: HabitType.binary, iconKey: 'star'),
            ),
            _failsWith(DomainRule.invalidHabitEdit),
          );
        }
        for (final title in [' reading ', 'READING', 'Water Intake']) {
          await expectLater(
            service.addCustomHabit(
              HabitDraft(title: title, type: HabitType.binary, iconKey: 'star'),
            ),
            _failsWith(DomainRule.duplicateHabit),
            reason: title,
          );
        }
        await expectLater(
          service.addCustomHabit(
            const HabitDraft(
              title: 'Odd',
              type: HabitType.binary,
              iconKey: 'nope',
            ),
          ),
          _failsWith(DomainRule.invalidHabitEdit),
        );
      },
    );

    test('an arc has at most 12 habits, enforced by the domain', () async {
      // 7 starters + 5 = 12.
      for (var i = 0; i < 5; i++) {
        await service.addCustomHabit(
          HabitDraft(
            title: 'Habit $i',
            type: HabitType.binary,
            iconKey: 'star',
          ),
        );
      }
      final setup = await service.setup();
      expect(setup.habits, hasLength(SetupHabitRules.maxHabits));
      expect(setup.atHabitLimit, isTrue);
      await expectLater(
        service.addCustomHabit(
          const HabitDraft(
            title: 'One more',
            type: HabitType.binary,
            iconKey: 'star',
          ),
        ),
        _failsWith(DomainRule.habitLimitReached),
      );
      await service.deleteSetupHabit('english');
      await service.addTemplateHabit('journal');
      await expectLater(
        service.addTemplateHabit('english'),
        _failsWith(DomainRule.habitLimitReached),
      );
    });
  });

  group('setup editing', () {
    test('edits change the baseline directly, without revisions', () async {
      await service.editSetupHabit(
        'water',
        const HabitDraft(
          title: 'Water',
          type: HabitType.count,
          iconKey: 'water',
          target: 10,
          minimumTarget: 4,
          unit: 'glasses',
        ),
      );
      final water = await byId('water');
      expect(
        (water.title, water.target, water.minimumTarget),
        ('Water', 10, 4),
      );
      expect(await app.db.select(app.db.habitRevisions).get(), isEmpty);
      await expectLater(
        service.editSetupHabit(
          'water',
          const HabitDraft(
            title: 'Water',
            type: HabitType.binary,
            iconKey: 'water',
          ),
        ),
        _failsWith(DomainRule.invalidHabitEdit),
        reason: 'the type is fixed',
      );
    });

    test('deleting works in setup; Start needs an enabled habit', () async {
      for (final habit in await service.setupHabits()) {
        await service.deleteSetupHabit(habit.id);
      }
      final empty = await service.setup();
      expect(empty.habits, isEmpty);
      expect(empty.canStart, isFalse);
      await expectLater(
        service.startWinterArc(),
        _failsWith(DomainRule.noHabitsSelected),
      );
      await service.addTemplateHabit('journal');
      final arc = await service.startWinterArc();
      expect(arc.status, WinterArcStatus.active);
    });

    test('a running arc can neither add nor delete habits', () async {
      await service.startWinterArc();
      await expectLater(
        service.addCustomHabit(
          const HabitDraft(
            title: 'Late',
            type: HabitType.binary,
            iconKey: 'star',
          ),
        ),
        _failsWith(DomainRule.sessionNotInSetup),
      );
      await expectLater(
        service.addTemplateHabit('journal'),
        _failsWith(DomainRule.sessionNotInSetup),
      );
      await expectLater(
        service.deleteSetupHabit('water'),
        _failsWith(DomainRule.sessionNotInSetup),
      );
      // The store re-checks the status inside its transaction.
      final arc = (await app.sessions.currentSession())!;
      await expectLater(
        DriftHabitRepository(app.db).deleteSetupHabit(arc.id, 'water'),
        _failsWith(DomainRule.sessionNotInSetup),
      );
      expect(await app.habits.habitsForSession(arc.id), hasLength(7));
    });
  });

  group('Reuse Last Setup', () {
    test(
      'keeps custom and timeBefore habits; the kind is chosen anew',
      () async {
        final custom = await service.addCustomHabit(
          const HabitDraft(
            title: 'Pages',
            type: HabitType.count,
            iconKey: 'learning',
            target: 20,
            minimumTarget: 5,
            unit: 'pages',
          ),
        );
        await service.setHabitEnabled('sleep_before', enabled: true);
        await service.startWinterArc();
        app.clock.current = DateTime(2027, 1, 5, 9);
        await app.lifecycle.reconcile();

        // A seasonal arc's habits... can't start in January; a rolling one can.
        await expectLater(
          service.startNewArc(
            NewArcBaseline.reuseLast,
            kind: ArcKind.seasonalWinter,
          ),
          _failsWith(DomainRule.seasonNotOpen),
        );
        final next = await service.startNewArc(NewArcBaseline.reuseLast);
        expect(next.kind, ArcKind.rolling92);
        final habits = await service.setupHabits();
        final pages = habits.singleWhere((h) => h.id == custom.id);
        expect((pages.title, pages.target, pages.unit), ('Pages', 20, 'pages'));
        final sleep = habits.singleWhere((h) => h.id == 'sleep_before');
        expect(sleep.type, HabitType.timeBefore);
        expect(sleep.enabled, isTrue);
      },
    );

    test('a legacy binary sleep habit is reused exactly as it was', () async {
      final legacy = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 7, 1, 8)),
      );
      addTearDown(legacy.db.close);
      await runFirstArc(legacy);
      // Pretend the finished arc came from Phase 1–5: its sleep habit was
      // the old done / not-done one.
      final done = (await legacy.sessions.latestCompletedSession())!;
      await legacy.db.customStatement(
        "UPDATE habits SET id = 'sleep_on_time', type = 'binary', "
        "target = 1, minimum_target = 1 WHERE session_id = ${done.id} "
        "AND id = 'sleep_before'",
      );
      await legacy.winterArc.startNewArc(
        NewArcBaseline.reuseLast,
        kind: ArcKind.seasonalWinter,
      );
      final habits = await legacy.winterArc.setupHabits();
      final sleep = habits.singleWhere((h) => h.id == 'sleep_on_time');
      expect(sleep.type, HabitType.binary);
      expect(habits.any((h) => h.id == 'sleep_before'), isFalse);
      // The user may remove it and add the new template instead.
      await legacy.winterArc.deleteSetupHabit('sleep_on_time');
      final added = await legacy.winterArc.addTemplateHabit('sleep_before');
      expect(added.type, HabitType.timeBefore);
      // The finished arc is untouched.
      final old = await legacy.habits.habitsForSession(done.id);
      expect(
        old.singleWhere((h) => h.id == 'sleep_on_time').type,
        HabitType.binary,
      );
    });
  });
}
