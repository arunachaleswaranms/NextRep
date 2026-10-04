import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/seasonal_backup.dart';

Uint8List _v1Fixture() =>
    File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync();

/// An empty app on [now], with its own scheduler.
TestApp _empty(DateTime now) {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(now),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  return app;
}

Future<void> _restoreInto(TestApp target, Uint8List bytes) async =>
    target.backup.restore(await target.backup.inspect(bytes));

void main() {
  test(
    'a Phase 5 format-1 backup restores into a schema-v5 database',
    () async {
      final target = _empty(DateTime(2026, 10, 3, 10));
      await _restoreInto(target, _v1Fixture());

      final sessions = await target.sessions.listSessions();
      expect(sessions, hasLength(2));
      for (final s in sessions) {
        expect(s.kind, ArcKind.rolling92);
        expect(s.participationStartDate, s.startDate);
      }
      final rows = await target.db.select(target.db.winterArcSessions).get();
      expect(rows.map((r) => r.arcKind), everyElement(ArcKind.rolling92));
      expect(rows.map((r) => r.participationStartDate), [
        LocalDate(2026, 7, 1),
        LocalDate(2026, 10, 1),
      ]);
      // The restored data works as before: the running arc tracks on.
      final today = await target.tracking.today();
      expect((today.position as ArcInProgress).dayNumber, 3);
      expect(today.session.kind, ArcKind.rolling92);
      final reminders = await target.reminderStore.load();
      expect(reminders.anyEnabled, isFalse);
    },
  );

  group('format 2 round trip', () {
    late TestApp source;
    late TestApp target;

    setUp(() async {
      source = await seasonalSource();
      addTearDown(source.db.close);
      target = _empty(source.clock.now());
      await _restoreInto(target, (await source.backup.export()).bytes);
    });

    test('every row comes back the same', () async {
      final before = await dumpOf(source.db);
      final after = await dumpOf(target.db);
      for (final table in before.keys) {
        if (table == 'reminders') continue; // restored off, by design
        expect(after[table], before[table], reason: table);
      }
    });

    test('the seasonal arc keeps its kind, dates and join day', () async {
      final arc = (await target.sessions.currentSession())!;
      expect(arc.kind, ArcKind.seasonalWinter);
      expect(arc.startDate, LocalDate(2026, 10, 1));
      expect(arc.endDate, LocalDate(2026, 12, 31));
      expect(arc.participationStartDate, LocalDate(2026, 10, 15));
      final journey = await target.tracking.journey();
      expect(journey.days.take(14).map((d) => d.state).toSet(), {
        JourneyDayState.notJoined,
      });
      expect((journey.position as ArcInProgress).dayNumber, 16);
    });

    test(
      'custom and clock-time habits keep working after the restore',
      () async {
        final today = await target.tracking.today();
        final sleep = today.record.entryFor('sleep_before')!;
        expect(sleep.habit.type, HabitType.timeBefore);
        expect(sleep.target, NightTime(0, 30).value);
        expect(sleep.progress.currentValue, NightTime(0, 45).value);
        expect(sleep.progress.completed, isFalse);
        await target.tracking.perform(
          habitId: 'sleep_before',
          action: HabitAction.setTime,
          time: NightTime(0, 20),
          date: today.date,
        );
        expect(
          (await target.tracking.today()).record
              .entryFor('sleep_before')!
              .progress
              .completed,
          isTrue,
        );
        expect(today.record.entryFor(pagesId)!.habit.title, 'Pages');
      },
    );

    test('reminders come back off and pending ones are cancelled', () async {
      final prefs = await target.reminderStore.load();
      expect(prefs.anyEnabled, isFalse);
      expect(target.scheduler.pending, isEmpty);
    });

    test('exporting again gives the same data', () async {
      final again = await target.backup.inspect(
        (await target.backup.export()).bytes,
      );
      expect(again.data.arcs[1].session.kind, ArcKind.seasonalWinter);
      expect(
        again.data.arcs[1].session.participationStartDate,
        LocalDate(2026, 10, 15),
      );
    });
  });

  test('a failed format-2 restore rolls back everything', () async {
    final source = await seasonalSource();
    addTearDown(source.db.close);
    final backup = await source.backup.inspect(
      (await source.backup.export()).bytes,
    );
    final target = _empty(DateTime(2026, 10, 16, 21));
    await joinSeason(target, DateTime(2026, 10, 16));
    await completeAll(target);
    final original = await dumpOf(target.db);
    await target.db.customStatement(
      'CREATE TEMP TRIGGER fail_restore BEFORE INSERT ON daily_reflections '
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    Object? error;
    try {
      await target.backup.restore(backup);
    } catch (e) {
      error = e;
    }
    expect(error, isA<PersistenceFailure>());
    expect(error.toString(), isNot(contains('Synthetic win')));
    expect(error.toString(), isNot(contains('Pages')));
    expect(await dumpOf(target.db), original, reason: 'rolled back');
  });

  test(
    'a preseason seasonal setup (starting after the export) round-trips',
    () async {
      final source = _empty(DateTime(2026, 9, 10, 9));
      await source.winterArc.startNewArc(
        NewArcBaseline.fresh,
        kind: ArcKind.seasonalWinter,
      );
      final bytes = (await source.backup.export()).bytes;
      final target = _empty(DateTime(2026, 9, 11, 9));
      await _restoreInto(target, bytes);
      final setup = (await target.sessions.currentSession())!;
      expect(setup.kind, ArcKind.seasonalWinter);
      expect(setup.status, WinterArcStatus.setup);
      expect(setup.startDate, LocalDate(2026, 10, 1));
      expect(setup.participationStartDate, isNull);
      expect(
        (await target.winterArc.setup()).startState,
        SetupStartState.seasonNotStarted,
      );
    },
  );

  test(
    'a setup emptied of habits can still be exported and restored',
    () async {
      final source = _empty(DateTime(2026, 10, 4, 9));
      await source.winterArc.beginSetup();
      for (final habit in await source.winterArc.setupHabits()) {
        await source.winterArc.deleteSetupHabit(habit.id);
      }
      final bytes = (await source.backup.export()).bytes;
      final target = _empty(DateTime(2026, 10, 4, 10));
      await _restoreInto(target, bytes);
      final setup = await target.winterArc.setup();
      expect(setup.habits, isEmpty);
      expect(setup.canStart, isFalse);
    },
  );

  test('restored ids never reuse an id this device used', () async {
    final source = await seasonalSource();
    addTearDown(source.db.close);
    final bytes = (await source.backup.export()).bytes;
    final target = await seasonalSource(); // its own arcs 1 and 2
    addTearDown(target.db.close);
    final stale = await target.tracking.today();

    await _restoreInto(target, bytes);
    final ids = [for (final s in await target.sessions.listSessions()) s.id];
    expect(ids, [4, 3]);
    expect(await target.sessions.sessionById(2), isNull);
    final before = await dumpOf(target.db);
    await expectLater(
      target.tracking.perform(
        habitId: 'sleep_before',
        action: HabitAction.clearTime,
        date: stale.date,
        sessionId: stale.session.id,
      ),
      throwsA(isA<DomainFailure>()),
    );
    expect(await dumpOf(target.db), before);
    final restored = (await target.sessions.currentSession())!;
    expect(restored.kind, ArcKind.seasonalWinter);
    expect(restored.participationStartDate, LocalDate(2026, 10, 15));
  });
}
