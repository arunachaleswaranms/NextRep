import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/fakes.dart';

void main() {
  late TestApp app;
  late int sessionId;
  final date = LocalDate(2026, 10, 1);
  final now = DateTime(2026, 10, 1, 10);

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(now));
    sessionId = (await app.winterArc.beginSetup()).id;
  });
  tearDown(() => app.db.close());

  ProgressTransition grant(DailyHabitProgress current) => ProgressTransition(
    before: current,
    after: DailyHabitProgress(
      habitId: current.habitId,
      date: date,
      currentValue: 1,
      completed: true,
      completedAt: now,
    ),
    xpEffect: GrantXp(
      XpAward(
        sourceKey: XpRules.habitCompletionKey(current.habitId, date),
        reason: XpReason.habitCompleted,
        amount: XpRules.habitCompletion,
        date: date,
        habitId: current.habitId,
        awardedAt: now,
      ),
    ),
  );

  test('progress round trip preserves every field', () async {
    await app.progress.applyTransition(
      sessionId: sessionId,
      habitId: 'no_junk_food',
      date: date,
      build: grant,
    );
    final [stored] = await app.progress.progressOn(sessionId, date);
    expect(stored.habitId, 'no_junk_food');
    expect(stored.date, date);
    expect(stored.currentValue, 1);
    expect(stored.completed, isTrue);
    expect(stored.completedAt, now);
    expect(await app.progress.progressOn(sessionId, date.addDays(1)), isEmpty);
  });

  test('the ledger ignores a duplicate award for the same key', () async {
    // Bypass the rules' no-op detection to exercise the unique index directly.
    for (var i = 0; i < 3; i++) {
      await app.progress.applyTransition(
        sessionId: sessionId,
        habitId: 'no_junk_food',
        date: date,
        build: (_) => grant(
          DailyHabitProgress.empty(habitId: 'no_junk_food', date: date),
        ),
      );
    }
    expect(await app.progress.totalXp(sessionId), XpRules.habitCompletion);
  });

  test('a throwing builder writes nothing', () async {
    await expectLater(
      app.progress.applyTransition(
        sessionId: sessionId,
        habitId: 'water',
        date: date,
        build: (_) => throw const DomainFailure(DomainRule.habitDisabled, 'x'),
      ),
      throwsA(isA<DomainFailure>()),
    );
    expect(await app.progress.progressOn(sessionId, date), isEmpty);
  });

  test('storage errors surface as PersistenceFailure', () async {
    await expectLater(
      app.progress.applyTransition(
        sessionId: sessionId,
        habitId: 'not_a_habit', // violates the habits foreign key
        date: date,
        build: grant,
      ),
      throwsA(
        isA<PersistenceFailure>().having((f) => f.cause, 'cause', isNotNull),
      ),
    );
    expect(await app.progress.totalXp(sessionId), 0);
  });

  test('foreign keys are enforced', () async {
    final result = await app.db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(result.read<int>('foreign_keys'), 1);
  });

  test('schema rejects negative progress values', () async {
    await expectLater(
      app.db
          .into(app.db.dailyHabitProgressEntries)
          .insert(
            DailyHabitProgressEntriesCompanion.insert(
              sessionId: sessionId,
              habitId: 'water',
              date: date,
              currentValue: -1,
              completed: false,
              updatedAt: now,
              completedAt: const Value(null),
            ),
          ),
      throwsA(anything),
    );
  });
}
