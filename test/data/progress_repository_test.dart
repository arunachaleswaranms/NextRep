import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/day_rules.dart';
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
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  DailyHabitProgress done(String habitId) => DailyHabitProgress(
    habitId: habitId,
    date: date,
    currentValue: 1,
    completed: true,
    completedAt: now,
  );

  /// Commits [change] for [date] through the real settlement rules.
  Future<void> commit(DayChange change) => app.progress.commitDay(
    sessionId: sessionId,
    date: date,
    build: (day) => (DayRules.settle(day, change, now: now), null),
  );

  Future<List<XpTransactionRow>> ledger() =>
      app.db.select(app.db.xpTransactions).get();

  test('progress round trip preserves every field', () async {
    await commit(DayChange(progress: [done('no_junk_food')]));
    final [stored] = await app.progress.progressOn(sessionId, date);
    expect(stored.habitId, 'no_junk_food');
    expect(stored.date, date);
    expect(stored.currentValue, 1);
    expect(stored.completed, isTrue);
    expect(stored.completedAt, now);
    expect(await app.progress.progressOn(sessionId, date.addDays(1)), isEmpty);
  });

  test('progress and its XP are written together', () async {
    await commit(DayChange(progress: [done('no_junk_food')]));
    final [row] = await ledger();
    expect(row.sourceKey, XpRules.habitCompletionKey('no_junk_food', date));
    expect(row.reason, XpReason.habitCompleted);
    expect(row.amount, XpRules.habitCompletion);
    expect(row.habitId, 'no_junk_food');
  });

  test('re-committing the same state writes nothing new', () async {
    for (var i = 0; i < 3; i++) {
      await commit(DayChange(progress: [done('no_junk_food')]));
    }
    expect(await ledger(), hasLength(1));
    expect(await app.progress.totalXp(sessionId), XpRules.habitCompletion);
  });

  test('the ledger ignores a duplicate award for the same key', () async {
    // Bypass the settlement's diff to exercise the unique index directly.
    final award = DayRules.settle(
      await _context(app, sessionId, date),
      DayChange(progress: [done('no_junk_food')]),
      now: now,
    );
    for (var i = 0; i < 3; i++) {
      await app.progress.commitDay(
        sessionId: sessionId,
        date: date,
        build: (_) => (award, null),
      );
    }
    expect(await app.progress.totalXp(sessionId), XpRules.habitCompletion);
  });

  test('a commit reports XP before and after from the same transaction', () {
    return app.progress
        .commitDay(
          sessionId: sessionId,
          date: date,
          build: (day) => (
            DayRules.settle(
              day,
              DayChange(progress: [done('no_junk_food')]),
              now: now,
            ),
            null,
          ),
        )
        .then((commit) {
          expect(commit.xpBefore, 0);
          expect(commit.xpAfter, XpRules.habitCompletion);
        });
  });

  test('a throwing builder writes nothing', () async {
    await expectLater(
      app.progress.commitDay<void>(
        sessionId: sessionId,
        date: date,
        build: (_) => throw const DomainFailure(DomainRule.habitDisabled, 'x'),
      ),
      throwsA(isA<DomainFailure>()),
    );
    expect(await app.progress.progressOn(sessionId, date), isEmpty);
  });

  test('a failed write rolls back the whole commit', () async {
    final valid = DayRules.settle(
      await _context(app, sessionId, date),
      DayChange(
        mode: DayMode.minimum,
        progress: [
          done('no_junk_food'),
          // violates the habits foreign key
          DailyHabitProgress(
            habitId: 'not_a_habit',
            date: date,
            currentValue: 1,
            completed: true,
            completedAt: now,
          ),
        ],
      ),
      now: now,
    );
    await expectLater(
      app.progress.commitDay(
        sessionId: sessionId,
        date: date,
        build: (_) => (valid, null),
      ),
      throwsA(
        isA<PersistenceFailure>().having((f) => f.cause, 'cause', isNotNull),
      ),
    );
    expect(await app.progress.progressOn(sessionId, date), isEmpty);
    expect(await app.progress.totalXp(sessionId), 0);
    expect(await app.db.select(app.db.dayModes).get(), isEmpty);
  });

  test('loadArc returns a consistent snapshot of the arc', () async {
    await commit(DayChange(progress: [done('no_junk_food')]));
    await commit(const DayChange(mode: DayMode.minimum));
    final arc = await app.progress.loadArc(sessionId);
    expect(arc.totalXp, XpRules.habitCompletion);
    expect(arc.xpByDate, {date: XpRules.habitCompletion});
    expect(arc.modeOn(date), DayMode.minimum);
    expect(arc.modeOn(date.addDays(1)), DayMode.normal);
    expect(arc.progressOn(date).keys, ['no_junk_food']);
    expect(arc.habits.habits, hasLength(7));
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

  test('schema rejects a minimum target above the target', () async {
    await expectLater(
      app.db
          .into(app.db.habitRevisions)
          .insert(
            HabitRevisionsCompanion.insert(
              sessionId: sessionId,
              habitId: 'water',
              effectiveFrom: date,
              target: 3,
              minimumTarget: 4,
              enabled: true,
              createdAt: now,
            ),
          ),
      throwsA(anything),
    );
  });
}

/// Reads [date]'s context through a no-op commit.
Future<DayContext> _context(TestApp app, int sessionId, LocalDate date) async {
  late DayContext context;
  await app.progress.commitDay(
    sessionId: sessionId,
    date: date,
    build: (day) {
      context = day;
      return (
        DayRules.settle(day, const DayChange(), now: app.clock.now()),
        null,
      );
    },
  );
  return context;
}
