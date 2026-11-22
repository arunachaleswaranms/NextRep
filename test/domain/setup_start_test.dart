import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';
import '../support/review_db.dart';

/// Phase 12D, spec § 4.3 and addendum § L2 (U + R): what Confirm & Start
/// does, on the real service and an in-memory database. Day 1 of a
/// Rolling Arc is the confirmation date and the days waiting before it are
/// not days of the Arc; Seasonal rules hold whatever the UI shows; a start
/// for a date that is no longer today, a refused start and a failed write
/// all leave every row as it was; pressing twice starts once. All data is
/// synthetic.

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

LocalDate _d(int y, int m, int d) => LocalDate(y, m, d);

void main() {
  late TestApp app;

  setUp(
    () => app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 11, 2))),
  );
  tearDown(() => app.db.close());

  void on(LocalDate date, {int hour = 9, int minute = 0}) => app.clock.current =
      DateTime(date.year, date.month, date.day, hour, minute);

  /// [body] must throw [rule] and leave every table exactly as it was.
  Future<void> refused(Future<void> Function() body, DomainRule rule) async {
    final before = await snapshotAll(app.db);
    await expectLater(body(), _failsWith(rule));
    expect(await snapshotAll(app.db), before, reason: 'nothing written');
  }

  /// The activity tables must be empty: waiting and starting earn nothing.
  Future<void> expectNoActivity() async {
    final all = await snapshotAll(app.db);
    for (final table in [
      'daily_habit_progress_entries',
      'day_modes',
      'xp_transactions',
      'achievement_unlocks',
      'daily_reflections',
      'habit_revisions',
      'arc_freezes',
    ]) {
      expect(all[table], isEmpty, reason: table);
    }
  }

  group('Rolling: Day 1 is the confirmation date (S3)', () {
    test('set up on D, edited D+1, saved D+2, confirmed D+5', () async {
      final d = _d(2026, 11, 2);
      on(d);
      final setup = await app.winterArc.beginSetup();
      on(d.addDays(1));
      await app.winterArc.editSetupHabit(
        'water',
        const HabitDraft(
          title: 'Water',
          type: HabitType.count,
          iconKey: 'water',
          target: 9,
          minimumTarget: 3,
          unit: 'glasses',
        ),
      );
      on(d.addDays(2));
      // Save for Later writes nothing: the setup is as last committed.
      final saved = await snapshotAll(app.db);
      on(d.addDays(5), hour: 7);
      final view = await app.winterArc.setup();
      expect(view.today, d.addDays(5));
      final preview = view.startPreview!;
      expect(await snapshotAll(app.db), saved, reason: 'reading is free');

      final started = await app.winterArc.startWinterArc(
        confirmedOn: view.today,
      );
      expect(started.id, setup.id, reason: 'the setup itself starts');
      expect(started.status, WinterArcStatus.active);
      expect(started.startDate, d.addDays(5));
      expect(started.endDate, d.addDays(96));
      expect(started.participationStartDate, d.addDays(5));
      expect(started.dayNumberOf(d.addDays(5)), 1);
      expect(started.dayNumberOf(d.addDays(96)), 92);
      // Exactly what Confirm & Start showed.
      expect(
        (preview.startDate, preview.endDate, preview.participationStartDate),
        (started.startDate, started.endDate, started.participationStartDate),
      );
      // The waiting days are no days of this Arc.
      for (var i = 0; i < 5; i++) {
        final waiting = d.addDays(i);
        expect(
          started.positionOn(waiting),
          isA<ArcNotStarted>(),
          reason: '$waiting',
        );
        expect(started.isParticipatingOn(waiting), isFalse);
      }
      await expectNoActivity();
      final today = await app.tracking.today();
      expect((today.position as ArcInProgress).dayNumber, 1);
      expect(
        today.entries.firstWhere((e) => e.habit.id == 'water').config.target,
        9,
      );
      final journey = await app.tracking.journey();
      expect(journey.days.first.date, d.addDays(5));
      expect(journey.days, hasLength(92));
    });

    test('the stored order is the order on Today', () async {
      on(_d(2026, 11, 2));
      await app.winterArc.beginSetup();
      final habits = await app.winterArc.setupHabits();
      final order = [for (final h in habits) h.id].reversed.toList();
      final enabled = {
        for (final h in habits)
          if (h.enabled) h.id,
      };
      await app.winterArc.reorderSetupHabits(order);
      await app.winterArc.startWinterArc(confirmedOn: app.clock.today());
      final today = await app.tracking.today();
      // Today lists the habits that are on, in the stored order.
      expect([
        for (final e in today.entries) e.habit.id,
      ], order.where(enabled.contains).toList());
    });

    test('a date that is no longer today starts nothing; clock forward and '
        'back', () async {
      on(_d(2026, 11, 2), hour: 23, minute: 59);
      await app.winterArc.beginSetup();
      final shown = (await app.winterArc.setup()).today;
      on(_d(2026, 11, 3), hour: 0, minute: 1);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: shown),
        DomainRule.startDateChanged,
      );
      // The clock moved back before the shown date.
      on(_d(2026, 11, 1));
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: shown),
        DomainRule.startDateChanged,
      );
      // Re-read and confirmed on the date it now is: Day 1 is that date.
      final now = (await app.winterArc.setup()).today;
      final started = await app.winterArc.startWinterArc(confirmedOn: now);
      expect(started.startDate, _d(2026, 11, 1));
      expect(started.endDate, _d(2027, 1, 31));
    });
  });

  group('Seasonal: start only 1 October – 31 December (S5)', () {
    Future<WinterArcSession> seasonalSetup() async {
      on(_d(2026, 9, 12));
      return app.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
    }

    test('30 September is refused, with or without a shown date', () async {
      await seasonalSetup();
      on(_d(2026, 9, 30), hour: 23, minute: 59);
      final view = await app.winterArc.setup();
      expect(view.blocker, SetupBlocker.seasonNotStarted);
      expect(view.startPreview, isNull);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: view.today),
        DomainRule.seasonNotStarted,
      );
      await refused(
        () => app.winterArc.startWinterArc(),
        DomainRule.seasonNotStarted,
      );
    });

    test('opened 30 September, confirmed after midnight: refused, then the '
        'season Day 1 after a re-read', () async {
      await seasonalSetup();
      on(_d(2026, 9, 30), hour: 23, minute: 59);
      final shown = (await app.winterArc.setup()).today;
      on(_d(2026, 10, 1), hour: 0, minute: 1);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: shown),
        DomainRule.startDateChanged,
      );
      final view = await app.winterArc.setup();
      expect(view.canStart, isTrue);
      expect(view.todayDay, 1);
      final started = await app.winterArc.startWinterArc(
        confirmedOn: view.today,
      );
      expect(started.startDate, _d(2026, 10, 1));
      expect(started.joinDayNumber, 1);
    });

    test(
      '18 October joins on Day 18; earlier season days stay neutral',
      () async {
        final setup = await seasonalSetup();
        on(_d(2026, 10, 18));
        final view = await app.winterArc.setup();
        expect(view.todayDay, 18);
        final started = await app.winterArc.startWinterArc(
          confirmedOn: view.today,
        );
        expect(started.id, setup.id);
        expect(
          (started.startDate, started.endDate, started.participationStartDate),
          (_d(2026, 10, 1), _d(2026, 12, 31), _d(2026, 10, 18)),
        );
        expect(started.joinDayNumber, 18);
        expect(started.isParticipatingOn(_d(2026, 10, 17)), isFalse);
        expect(started.isParticipatingOn(_d(2026, 10, 18)), isTrue);
        await expectNoActivity();
        expect(
          ((await app.tracking.today()).position as ArcInProgress).dayNumber,
          18,
        );
      },
    );

    test('31 December can still join, on Day 92', () async {
      await seasonalSetup();
      on(_d(2026, 12, 31), hour: 22);
      final view = await app.winterArc.setup();
      expect(view.canStart, isTrue);
      expect(view.todayDay, 92);
      final started = await app.winterArc.startWinterArc(
        confirmedOn: view.today,
      );
      expect(started.joinDayNumber, 92);
    });

    test('1 January: the season is over, from every entry, and the setup '
        'is never moved to another year', () async {
      final setup = await seasonalSetup();
      on(_d(2027, 1, 1));
      final view = await app.winterArc.setup();
      expect(view.blocker, SetupBlocker.seasonEnded);
      expect(view.startPreview, isNull);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: view.today),
        DomainRule.seasonEnded,
      );
      await refused(
        () => app.winterArc.startWinterArc(),
        DomainRule.seasonEnded,
      );
      final still = await app.sessions.sessionById(setup.id);
      expect(still!.status, WinterArcStatus.setup);
      expect(
        (still.startDate, still.endDate),
        (_d(2026, 10, 1), _d(2026, 12, 31)),
      );
      expect(still.kind, ArcKind.seasonalWinter);
    });
  });

  group('empty setups can be saved but not started (S6)', () {
    test('no habits, and every habit off', () async {
      on(_d(2026, 11, 2));
      await app.winterArc.beginSetup();
      final ids = [for (final h in await app.winterArc.setupHabits()) h.id];
      for (final id in ids.skip(1)) {
        await app.winterArc.setHabitEnabled(id, enabled: false);
      }
      await app.winterArc.setHabitEnabled(ids.first, enabled: false);
      expect((await app.winterArc.setup()).blocker, SetupBlocker.noneEnabled);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: app.clock.today()),
        DomainRule.noHabitsSelected,
      );
      for (final id in ids) {
        await app.winterArc.deleteSetupHabit(id);
      }
      final empty = await app.winterArc.setup();
      expect(empty.habits, isEmpty);
      expect(empty.blocker, SetupBlocker.noHabits);
      expect(empty.canStart, isFalse);
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: app.clock.today()),
        DomainRule.noHabitsSelected,
      );
    });

    test('with no setup at all there is nothing to start', () async {
      await refused(
        () => app.winterArc.startWinterArc(confirmedOn: app.clock.today()),
        DomainRule.noSession,
      );
    });
  });

  group('one start, atomically', () {
    test('two near-simultaneous confirmations start one Arc', () async {
      on(_d(2026, 11, 2));
      final setup = await app.winterArc.beginSetup();
      final ids = [for (final h in await app.winterArc.setupHabits()) h.id];
      final today = app.clock.today();
      final both = await Future.wait([
        app.winterArc.startWinterArc(confirmedOn: today),
        app.winterArc.startWinterArc(confirmedOn: today),
      ]);
      expect(both[0].id, setup.id);
      expect(both[1].id, setup.id);
      expect(both[0].startedAt, both[1].startedAt);
      final sessions = await app.sessions.listSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.status, WinterArcStatus.active);
      expect(sessions.single.participationStartDate, today);
      expect([
        for (final h in await app.habits.habitsForSession(setup.id)) h.id,
      ], ids);
      await expectNoActivity();
    });

    test('a storage failure during the transition changes nothing; a retry '
        'starts it', () async {
      on(_d(2026, 11, 2));
      final setup = await app.winterArc.beginSetup();
      await app.db.customStatement(
        'CREATE TRIGGER fail_start BEFORE UPDATE OF status ON '
        "winter_arc_sessions WHEN NEW.status = 'active' "
        "BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      final before = await snapshotAll(app.db);
      await expectLater(
        app.winterArc.startWinterArc(confirmedOn: app.clock.today()),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await snapshotAll(app.db), before);
      final still = await app.sessions.sessionById(setup.id);
      expect(still!.status, WinterArcStatus.setup);
      expect((await app.winterArc.setup()).canStart, isTrue);

      await app.db.customStatement('DROP TRIGGER fail_start');
      final started = await app.winterArc.startWinterArc(
        confirmedOn: app.clock.today(),
      );
      expect(started.status, WinterArcStatus.active);
      await expectNoActivity();
    });

    test('starting changes only the session row', () async {
      on(_d(2026, 11, 2));
      final setup = await app.winterArc.beginSetup();
      final before = await snapshotAll(app.db);
      await app.winterArc.startWinterArc(confirmedOn: app.clock.today());
      final after = await snapshotAll(app.db);
      for (final table in before.keys) {
        if (table == 'winter_arc_sessions') continue;
        expect(after[table], before[table], reason: table);
      }
      final row = after['winter_arc_sessions']!.single;
      final old = before['winter_arc_sessions']!.single;
      expect(row['id'], setup.id);
      final changed = {
        for (final key in row.keys)
          if (row[key] != old[key]) key,
      };
      expect(
        changed,
        containsAll(<String>[
          'status',
          'started_at',
          'participation_start_date',
        ]),
      );
      expect(
        changed.difference({
          'status',
          'started_at',
          'participation_start_date',
          'start_date',
          'end_date',
        }),
        isEmpty,
      );
    });
  });

  group('ArcSetup: one snapshot drives every derived value', () {
    test('blocker order: the season before the habits', () async {
      on(_d(2026, 9, 12));
      await app.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
      for (final h in await app.winterArc.setupHabits()) {
        await app.winterArc.deleteSetupHabit(h.id);
      }
      expect(
        (await app.winterArc.setup()).blocker,
        SetupBlocker.seasonNotStarted,
      );
      on(_d(2027, 1, 2));
      expect((await app.winterArc.setup()).blocker, SetupBlocker.seasonEnded);
      on(_d(2026, 10, 2));
      expect((await app.winterArc.setup()).blocker, SetupBlocker.noHabits);
    });

    test('the preview is ArcStartRules.start itself, for any date', () async {
      on(_d(2026, 11, 2));
      final session = await app.winterArc.beginSetup();
      for (var i = 0; i < 400; i += 7) {
        final date = _d(2026, 1, 1).addDays(i);
        final setup = ArcSetup(
          session: session,
          habits: const [],
          startState: ArcStartRules.stateOn(session, date),
          today: date,
        );
        final preview = setup.startPreview!;
        expect(preview.startDate, date);
        expect(preview.endDate, WinterArcRules.endDateFor(date));
        expect(preview.dayNumberOf(preview.endDate), 92);
      }
      // Nothing was written by previews.
      expect(
        (await app.sessions.sessionById(session.id))!.status,
        WinterArcStatus.setup,
      );
    });
  });
}
