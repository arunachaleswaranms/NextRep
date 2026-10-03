import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/progress/progress_repository.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

void main() {
  late TestApp app;
  final day1 = LocalDate(2026, 10, 1);

  Future<DayCommit<ProgressTransition>> act(
    String habitId,
    HabitAction action, {
    LocalDate? date,
  }) => app.tracking.perform(
    habitId: habitId,
    action: action,
    date: date ?? app.clock.today(),
  );

  Future<int> xpRows() async =>
      (await app.db.select(app.db.xpTransactions).get()).length;

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 7)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  test('today lists enabled habits in order with no progress', () async {
    final today = await app.tracking.today();
    expect(today.date, day1);
    expect((today.position as ArcInProgress).dayNumber, 1);
    expect(today.entries.map((e) => e.habit.id), [
      'workout',
      'water',
      'learning',
      'no_junk_food',
    ]);
    expect(today.completion.percent, 0);
    expect(today.totalXp, 0);
  });

  test('completing a habit persists progress, XP and percentage', () async {
    final t = await act('no_junk_food', HabitAction.complete);
    expect(t.value.becameCompleted, isTrue);

    final today = await app.tracking.today();
    final entry = today.entries.firstWhere((e) => e.habit.id == 'no_junk_food');
    expect(entry.progress.completed, isTrue);
    expect(entry.progress.completedAt, DateTime(2026, 10, 1, 7));
    expect(today.completion.completed, 1);
    expect(today.completion.percent, 25);
    expect(today.totalXp, XpRules.habitCompletion);
  });

  test('rapid concurrent completes grant XP exactly once', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++) act('no_junk_food', HabitAction.complete),
    ]);
    expect(await xpRows(), 1);
    expect((await app.tracking.today()).totalXp, XpRules.habitCompletion);
  });

  test('complete → undo → complete never exceeds one award', () async {
    for (var i = 0; i < 5; i++) {
      await act('no_junk_food', HabitAction.complete);
      await act('no_junk_food', HabitAction.undoCompletion);
    }
    expect((await app.tracking.today()).totalXp, 0);
    await act('no_junk_food', HabitAction.complete);
    expect((await app.tracking.today()).totalXp, XpRules.habitCompletion);
    expect(await xpRows(), 1);
  });

  test('undo removes the completion and its XP', () async {
    await act('no_junk_food', HabitAction.complete);
    await act('no_junk_food', HabitAction.undoCompletion);
    final today = await app.tracking.today();
    expect(today.completion.completed, 0);
    expect(today.totalXp, 0);
  });

  test('concurrent increments are all applied, in sequence', () async {
    await Future.wait([
      for (var i = 0; i < 8; i++) act('water', HabitAction.increment),
    ]);
    final water = (await app.tracking.today()).entries.firstWhere(
      (e) => e.habit.id == 'water',
    );
    expect(water.progress.currentValue, 8);
    expect(water.progress.completed, isTrue);
    expect(await xpRows(), 1);
  });

  test('the same habit on a new day is a separate award', () async {
    await act('no_junk_food', HabitAction.complete);
    app.clock.current = DateTime(2026, 10, 2, 7);
    final today = await app.tracking.today();
    expect((today.position as ArcInProgress).dayNumber, 2);
    expect(today.completion.completed, 0); // fresh day
    await act('no_junk_food', HabitAction.complete);
    expect((await app.tracking.today()).totalXp, 2 * XpRules.habitCompletion);
  });

  test('an action for a day that has rolled over is rejected', () async {
    app.clock.current = DateTime(2026, 10, 2, 0, 0, 1);
    expect(
      act('no_junk_food', HabitAction.complete, date: day1),
      _failsWith(DomainRule.staleDay),
    );
    expect(await xpRows(), 0);
  });

  test('actions are rejected after the arc has finished', () async {
    app.clock.current = DateTime(2027, 1, 1, 9);
    expect(
      act('no_junk_food', HabitAction.complete),
      _failsWith(DomainRule.arcNotRunningToday),
    );
  });

  test('disabled and unknown habits are rejected', () async {
    expect(
      act('english', HabitAction.increment),
      _failsWith(DomainRule.habitDisabled),
    );
    expect(
      act('nope', HabitAction.complete),
      _failsWith(DomainRule.habitNotFound),
    );
  });

  test('type-incompatible actions persist nothing', () async {
    await expectLater(
      act('water', HabitAction.complete),
      _failsWith(DomainRule.actionNotSupportedForHabitType),
    );
    expect(
      await app.db.select(app.db.dailyHabitProgressEntries).get(),
      isEmpty,
    );
  });

  test('tracking requires an active session', () async {
    final setupOnly = TestApp(memoryDatabase(), app.clock);
    addTearDown(setupOnly.db.close);
    await setupOnly.winterArc.beginSetup();
    expect(setupOnly.tracking.today(), _failsWith(DomainRule.noActiveSession));
  });
}
