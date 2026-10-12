import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/app/theme/winter_tokens.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/habit/starter_habits.dart';
import 'package:nextrep/features/achievements/widgets/achievement_badge.dart';
import 'package:nextrep/shared/widgets/habit_icon.dart';

import '../support/builders.dart' show day1;
import '../support/fakes.dart';

/// Phase 10C: six optional templates and a 32-achievement catalog in six
/// categories.

/// (id, title, type, target, minimum, unit, description)
const _newTemplates = [
  (
    'hair_care',
    'Hair Care',
    HabitType.binary,
    1,
    1,
    null,
    'Complete your daily hair-care routine.',
  ),
  (
    'skin_care',
    'Skin Care',
    HabitType.binary,
    1,
    1,
    null,
    'Complete your daily skin-care routine.',
  ),
  (
    'fruit',
    'Eat Fruit',
    HabitType.binary,
    1,
    1,
    null,
    'Include fruit in your day.',
  ),
  (
    'nuts_seeds',
    'Nuts / Seeds',
    HabitType.binary,
    1,
    1,
    null,
    'Include nuts or seeds in your day.',
  ),
  (
    'mobility',
    'Stretch / Mobility',
    HabitType.duration,
    10,
    5,
    'min',
    'Make time for stretching or mobility work.',
  ),
  (
    'reading',
    'Reading',
    HabitType.duration,
    15,
    5,
    'min',
    'Spend a few focused minutes reading.',
  ),
];

const _oldAchievementIds = [
  'first_rep',
  'first_perfect',
  'streak_3',
  'streak_7',
  'perfect_3',
  'minimum_complete',
  'level_2',
  'level_3',
  'halfway',
  'summit',
  'first_reflection',
  'reflections_7',
  'minimum_3',
  'perfect_10',
  'level_5',
];

const _newAchievementIds = [
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

void main() {
  group('templates', () {
    for (final (id, title, type, target, minimum, unit, description)
        in _newTemplates) {
      test('$id: exact, optional, with its own icon', () {
        final t = HabitTemplateCatalog.byId(id)!;
        expect(t.id, id);
        expect(t.title, title);
        expect(t.type, type);
        expect(t.target, target);
        expect(t.minimumTarget, minimum);
        expect(t.unit, unit);
        expect(t.starter, isFalse);
        expect(t.enabledByDefault, isFalse);
        expect(t.description, description);
        expect(t.iconKey, id);
        expect(HabitIconKeys.all, contains(id));
        expect(HabitIcon.hasIcon(id), isTrue);
        expect(WinterHabitAccents.hasAccent(id), isTrue);
      });
    }

    test('no medical or universal claims in the new descriptions', () {
      final text = [
        for (final (id, _, _, _, _, _, _) in _newTemplates)
          '${HabitTemplateCatalog.byId(id)!.title} '
              '${HabitTemplateCatalog.byId(id)!.description}',
      ].join(' ').toLowerCase();
      for (final word in const [
        'minoxidil',
        'medication',
        'hair loss',
        'treatment',
        'cure',
        'should',
        'must',
        'servings',
      ]) {
        expect(text, isNot(contains(word)));
      }
    });

    test(
      'every icon key has a glyph and an accent; unknown keys fall back',
      () {
        for (final key in HabitIconKeys.all) {
          expect(HabitIcon.hasIcon(key), isTrue, reason: key);
          expect(WinterHabitAccents.hasAccent(key), isTrue, reason: key);
        }
        expect(HabitIcon.hasIcon('from_the_future'), isFalse);
        expect(
          WinterHabitAccents.of('from_the_future'),
          WinterColors.night.accent,
        );
      },
    );

    test('the starter set is unchanged', () {
      expect(StarterHabits.all.map((t) => t.id), [
        'workout',
        'water',
        'learning',
        'english',
        'no_junk_food',
        'sleep_before',
        'meditation',
      ]);
    });

    test('templates are added through the setup rules like any other', () {
      final starters = StarterHabits.seed(DateTime(2026, 10, 1));
      final hair = SetupHabitRules.fromTemplate(
        HabitTemplateCatalog.byId('hair_care')!,
        starters,
        createdAt: DateTime(2026, 10, 1, 9),
      );
      expect(hair.id, 'hair_care');
      expect(hair.type, HabitType.binary);
      expect(hair.enabled, isTrue);
      expect(hair.iconKey, 'hair_care');
      expect(hair.sortOrder, starters.length);

      final reading = SetupHabitRules.fromTemplate(
        HabitTemplateCatalog.byId('reading')!,
        starters,
        createdAt: DateTime(2026, 10, 1, 9),
      );
      expect(
        (reading.target, reading.minimumTarget, reading.unit),
        (15, 5, 'min'),
      );
    });

    group('in setup (real services)', () {
      late TestApp app;

      setUp(() async {
        app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 9)));
        await app.winterArc.beginSetup();
      });
      tearDown(() => app.db.close());

      Future<List<Habit>> setupHabits() async =>
          (await app.winterArc.setup()).habits;

      Matcher failsWith(DomainRule rule) =>
          throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

      test('a fresh setup is not seeded with them', () async {
        final ids = (await setupHabits()).map((h) => h.id);
        expect(ids, StarterHabits.all.map((t) => t.id));
        for (final (id, _, _, _, _, _, _) in _newTemplates) {
          expect(ids, isNot(contains(id)));
        }
      });

      test('Hair Care is added enabled, once', () async {
        final added = await app.winterArc.addTemplateHabit('hair_care');
        expect(added.enabled, isTrue);
        final stored = (await setupHabits()).singleWhere(
          (h) => h.id == 'hair_care',
        );
        expect(stored.title, 'Hair Care');
        expect(stored.enabled, isTrue);
        expect(stored.iconKey, 'hair_care');
        await expectLater(
          app.winterArc.addTemplateHabit('hair_care'),
          failsWith(DomainRule.duplicateHabit),
        );
        expect(
          (await setupHabits()).where((h) => h.id == 'hair_care'),
          hasLength(1),
        );
      });

      test('the 12-habit limit holds for the new templates too', () async {
        // 7 starters + 5 new templates = 12.
        for (final id in const [
          'hair_care',
          'skin_care',
          'fruit',
          'nuts_seeds',
          'mobility',
        ]) {
          await app.winterArc.addTemplateHabit(id);
        }
        expect(await setupHabits(), hasLength(SetupHabitRules.maxHabits));
        await expectLater(
          app.winterArc.addTemplateHabit('reading'),
          failsWith(DomainRule.habitLimitReached),
        );
        expect(await setupHabits(), hasLength(12));
      });

      test('a running arc never gains one', () async {
        final arc = await app.winterArc.startWinterArc();
        final before = await app.habits.habitsForSession(arc.id);
        await expectLater(
          app.winterArc.addTemplateHabit('hair_care'),
          throwsA(isA<DomainFailure>()),
        );
        expect(
          await app.habits.habitsForSession(arc.id),
          hasLength(before.length),
        );
        expect(
          (await app.habits.habitsForSession(arc.id)).map((h) => h.id),
          isNot(contains('hair_care')),
        );
        final today = await app.tracking.today();
        expect(
          today.entries.map((e) => e.habit.id),
          isNot(contains('hair_care')),
        );
      });
    });
  });

  group('achievement catalog', () {
    final keys = AchievementCatalog.all.map((d) => d.key).toList();

    test('32 achievements, each key exactly once', () {
      expect(AchievementCatalog.all, hasLength(32));
      expect(AchievementKey.values, hasLength(32));
      expect(keys.toSet(), AchievementKey.values.toSet());
      expect(keys, hasLength(keys.toSet().length));
    });

    test('the 15 existing ids are unchanged and the 17 new ids are unique '
        'snake_case', () {
      final ids = AchievementKey.values.map((k) => k.id).toList();
      expect(ids.take(15), _oldAchievementIds);
      expect(ids.skip(15), _newAchievementIds);
      expect(ids.toSet(), hasLength(32));
      for (final id in _newAchievementIds) {
        expect(id, matches(RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$')));
        expect(AchievementKey.fromId(id)?.id, id);
      }
    });

    test('display order is deterministic and grouped by category', () {
      expect(keys, [
        // Progress.
        AchievementKey.firstRep,
        AchievementKey.level2,
        AchievementKey.level3,
        AchievementKey.level5,
        // Consistency.
        AchievementKey.firstPerfect,
        AchievementKey.streak3,
        AchievementKey.streak7,
        AchievementKey.streak14,
        AchievementKey.streak30,
        AchievementKey.streak50,
        AchievementKey.perfect3,
        AchievementKey.perfect10,
        AchievementKey.perfect25,
        // Resilience.
        AchievementKey.minimumComplete,
        AchievementKey.minimum3,
        AchievementKey.minimum7,
        // Habit mastery.
        AchievementKey.noJunk7,
        AchievementKey.noJunk30,
        AchievementKey.noJunk50,
        AchievementKey.workout30,
        AchievementKey.water30,
        AchievementKey.learning30,
        AchievementKey.sleep14,
        // Reflection.
        AchievementKey.firstReflection,
        AchievementKey.reflections7,
        AchievementKey.reflections14,
        AchievementKey.reflections30,
        // Journey.
        AchievementKey.day14,
        AchievementKey.halfway,
        AchievementKey.day60,
        AchievementKey.day75,
        AchievementKey.summit,
      ]);
    });

    test('category sizes add up to 32, labels are human-facing', () {
      final sizes = {
        for (final c in AchievementCategory.values)
          c: AchievementCatalog.all.where((d) => d.category == c).length,
      };
      expect(sizes, {
        AchievementCategory.progress: 4,
        AchievementCategory.consistency: 9,
        AchievementCategory.resilience: 3,
        AchievementCategory.habitMastery: 7,
        AchievementCategory.reflection: 4,
        AchievementCategory.journey: 5,
      });
      expect(sizes.values.fold(0, (a, b) => a + b), 32);
      expect(AchievementCategory.values.map((c) => c.label), [
        'Progress',
        'Consistency',
        'Resilience',
        'Habit Mastery',
        'Reflection',
        'Journey',
      ]);
      // Board groups follow the categories.
      final board = AchievementBoard(
        startDate: day1,
        entries: [
          for (final d in AchievementCatalog.all)
            AchievementStatus(definition: d),
        ],
      );
      expect(board.groups.map((g) => g.$1), AchievementCategory.values);
      expect(board.groups.map((g) => g.$2.length), [4, 9, 3, 7, 4, 5]);
    });

    test('titles and descriptions of the new achievements', () {
      final byId = {for (final d in AchievementCatalog.all) d.key.id: d};
      expect(
        {for (final id in _newAchievementIds) id: byId[id]!.title},
        {
          'streak_14': 'Two Weeks Strong',
          'streak_30': 'Cold Discipline',
          'streak_50': 'Iron Winter',
          'perfect_25': 'Quarter Century',
          'minimum_7': "Bend, Don't Break",
          'reflections_14': 'Two Weeks Inward',
          'reflections_30': 'Know Yourself',
          'day_14': 'First Chapter',
          'day_60': 'Aurora',
          'day_75': 'Final Approach',
          'no_junk_7': 'Clean Week',
          'no_junk_30': 'Intentional Month',
          'no_junk_50': 'Deep Discipline',
          'workout_30': 'Built by Reps',
          'water_30': 'Hydration Rhythm',
          'learning_30': 'Always Learning',
          'sleep_before_14': 'Rest Rhythm',
        },
      );
      for (final d in AchievementCatalog.all) {
        expect(d.description, isNotEmpty);
      }
      // No universal intake rule in the Water achievement.
      expect(byId['water_30']!.description, isNot(contains('8')));
      expect(byId['water_30']!.description, contains('your own'));
    });

    test('every key has its own icon and a palette accent', () {
      final colors = buildWinterTheme().extension<WinterColors>()!;
      final palette = {
        colors.accent,
        colors.accentSecondary,
        colors.celebration,
        colors.auroraViolet,
        colors.auroraGreen,
        colors.recovery,
        colors.warmLight,
      };
      final icons = <IconData>{};
      for (final key in AchievementKey.values) {
        icons.add(key.icon);
        expect(palette, contains(key.accent(colors)), reason: key.id);
      }
      expect(icons, hasLength(32), reason: 'no badge shares a glyph');
    });
  });
}
