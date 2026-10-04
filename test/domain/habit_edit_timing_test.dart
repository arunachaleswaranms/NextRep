import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/progress/day_record.dart';
import 'package:nextrep/domain/progress/day_summary.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/progress/habit_tracking_service.dart';
import 'package:nextrep/domain/progress/progress_repository.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Phase 3 edit timing: a rename applies now; target, minimum target and
/// enabled apply from the next challenge day. Default habits: workout
/// (30 min), water (8, minimum 3), learning (20 min), no_junk_food.
void main() {
  late TestApp app;

  LocalDate day(int n) => LocalDate(2026, 10, 1).addDays(n - 1);
  void goTo(int n) =>
      app.clock.current = day(n)
          .toLocalDateTime()
          .add(const Duration(hours: 8));

  Future<DayCommit<HabitEditOutcome>> edit(String habitId, HabitEdit edit) =>
      app.tracking.editHabit(
        habitId: habitId,
        edit: edit,
        date: app.clock.today(),
      );

  HabitDayEntry water(DaySummary s) =>
      s.entries.firstWhere((e) => e.habit.id == 'water');

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 8)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  test('a title rename applies immediately, including to past days', () async {
    goTo(3);
    final commit = await edit('water', const HabitEdit(title: 'Hydrate'));
    expect(commit.value.renamed, isTrue);
    expect(commit.value.configFrom, isNull);
    expect(water(await app.tracking.today()).habit.title, 'Hydrate');
    final journey = await app.tracking.journey();
    expect(
      journey.days.first.record!.entryFor('water')!.habit.title,
      'Hydrate',
    );
    expect(await app.db.select(app.db.habitRevisions).get(), isEmpty);
  });

  test('a target edit leaves today unchanged and applies tomorrow', () async {
    goTo(12);
    await app.tracking.perform(
      habitId: 'water',
      action: HabitAction.increment,
      date: day(12),
    );
    final commit = await edit('water', const HabitEdit(target: 10));
    expect(commit.value.configFrom, day(13));
    expect(commit.settlement.progress, isEmpty);
    expect(commit.settlement.ledger.isEmpty, isTrue);

    final today = water(await app.tracking.today());
    expect(today.target, 8);
    expect(today.config.target, 8);
    expect(today.progress.currentValue, 1);

    final settings = await app.tracking.habitSettings();
    final setting = settings.habits.firstWhere((s) => s.habit.id == 'water');
    expect(setting.config.target, 8);
    expect(setting.upcoming!.target, 10);
    expect(setting.hasPendingChange, isTrue);

    goTo(13);
    expect(water(await app.tracking.today()).target, 10);
    goTo(40);
    expect(water(await app.tracking.today()).target, 10);
  });

  test('a minimum target edit applies from tomorrow too', () async {
    goTo(5);
    await edit('water', const HabitEdit(minimumTarget: 2));
    await app.tracking.activateMinimumDay(date: day(5));
    expect(water(await app.tracking.today()).target, 3);
    goTo(6);
    await app.tracking.activateMinimumDay(date: day(6));
    expect(water(await app.tracking.today()).target, 2);
  });

  test('enable and disable apply from tomorrow', () async {
    goTo(4);
    await edit('learning', const HabitEdit(enabled: false));
    await edit('english', const HabitEdit(enabled: true));
    var ids = (await app.tracking.today()).entries.map((e) => e.habit.id);
    expect(ids, contains('learning'));
    expect(ids, isNot(contains('english')));

    goTo(5);
    ids = (await app.tracking.today()).entries.map((e) => e.habit.id);
    expect(ids, isNot(contains('learning')));
    expect(ids, contains('english'));
  });

  test('a same-day edit cannot create a Perfect Day', () async {
    for (var i = 0; i < 6; i++) {
      await app.tracking.perform(
        habitId: 'workout',
        action: HabitAction.increment,
        date: day(1),
      );
    }
    await app.tracking.perform(
      habitId: 'no_junk_food',
      action: HabitAction.complete,
      date: day(1),
    );
    for (var i = 0; i < 8; i++) {
      await app.tracking.perform(
        habitId: 'water',
        action: HabitAction.increment,
        date: day(1),
      );
    }
    // Learning is unfinished: neither lowering nor disabling it helps today.
    await edit('learning', const HabitEdit(target: 5));
    expect((await app.tracking.today()).isPerfect, isFalse);
    await edit('learning', const HabitEdit(enabled: false));
    final today = await app.tracking.today();
    expect(today.isPerfect, isFalse);
    expect(today.totalXp, 3 * 15);
  });

  test('past days keep their configuration after later edits', () async {
    goTo(2);
    await edit('water', const HabitEdit(target: 12, minimumTarget: 4));
    goTo(6);
    await edit('water', const HabitEdit(enabled: false));
    goTo(9);
    final journey = await app.tracking.journey();
    expect(journey.days[0].record!.entryFor('water')!.target, 8); // day 1
    expect(journey.days[1].record!.entryFor('water')!.target, 8); // day 2
    expect(journey.days[2].record!.entryFor('water')!.target, 12); // day 3
    expect(journey.days[5].record!.entryFor('water')!.target, 12); // day 6
    expect(journey.days[6].record!.entryFor('water'), isNull); // day 7
    final revisions = await app.db.select(app.db.habitRevisions).get();
    expect(revisions.map((r) => r.effectiveFrom), [day(3), day(7)]);
  });

  test('a Phase 2 revision stored for its own day stays in effect', () async {
    goTo(3);
    await app.db
        .into(app.db.habitRevisions)
        .insert(
          HabitRevisionsCompanion.insert(
            sessionId: 1,
            habitId: 'water',
            effectiveFrom: day(3),
            target: 6,
            minimumTarget: 2,
            enabled: true,
            createdAt: DateTime(2026, 10, 3, 8),
          ),
        );
    expect(water(await app.tracking.today()).target, 6);
    final journey = await app.tracking.journey();
    expect(journey.days[1].record!.entryFor('water')!.target, 8);
  });

  test('on Day 92 goal edits are rejected but renaming works', () async {
    goTo(92);
    final settings = await app.tracking.habitSettings();
    expect(settings.editable, isTrue);
    expect(settings.configEditable, isFalse);
    expect(settings.habits.every((s) => s.upcoming == null), isTrue);

    expect(
      edit('water', const HabitEdit(target: 10)),
      _failsWith(DomainRule.noNextChallengeDay),
    );
    expect(
      edit('learning', const HabitEdit(enabled: false)),
      _failsWith(DomainRule.noNextChallengeDay),
    );
    // Unchanged goals alongside a rename are fine.
    final commit = await edit(
      'water',
      const HabitEdit(title: 'Last water', target: 8, minimumTarget: 3),
    );
    expect(commit.value.renamed, isTrue);
    expect(water(await app.tracking.today()).habit.title, 'Last water');
    expect(await app.db.select(app.db.habitRevisions).get(), isEmpty);

    goTo(91);
    expect((await app.tracking.habitSettings()).configEditable, isTrue);
  });
}
