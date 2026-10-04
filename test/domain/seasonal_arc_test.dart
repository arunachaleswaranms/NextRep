import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

final _oct1 = LocalDate(2026, 10, 1);
final _dec31 = LocalDate(2026, 12, 31);

/// Arc kinds: the rolling 92-day arc stays exactly as before, and the
/// Seasonal Winter Arc runs 1 Oct – 31 Dec of one year, whenever it is
/// joined.
void main() {
  late TestApp app;

  setUp(
    () => app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 9, 10, 9))),
  );
  tearDown(() => app.db.close());

  Future<WinterArcSession> seasonalSetup() => app.winterArc.startNewArc(
    NewArcBaseline.fresh,
    kind: ArcKind.seasonalWinter,
  );

  group('rolling regression', () {
    test('Start makes exactly 92 days from today, joined today', () async {
      app.clock.current = DateTime(2026, 3, 14, 9);
      final setup = await app.winterArc.beginSetup();
      expect(setup.kind, ArcKind.rolling92);
      expect(setup.participationStartDate, isNull);

      app.clock.current = DateTime(2026, 3, 16, 21);
      final arc = await app.winterArc.startWinterArc();
      expect(arc.kind, ArcKind.rolling92);
      expect(arc.startDate, LocalDate(2026, 3, 16));
      expect(arc.endDate, LocalDate(2026, 6, 15));
      expect(arc.lengthInDays, 92);
      expect(arc.participationStartDate, arc.startDate);
      expect(WinterArcRules.problemWith(arc), isNull);
    });

    test('Day 92 is start + 91 and the arc closes the day after', () async {
      app.clock.current = DateTime(2026, 3, 16, 9);
      await app.winterArc.beginSetup();
      final arc = await app.winterArc.startWinterArc();
      expect(arc.dayNumberOf(LocalDate(2026, 6, 15)), 92);

      app.clock.current = DateTime(2026, 6, 15, 23, 59);
      await app.lifecycle.reconcile();
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.active,
      );
      app.clock.current = DateTime(2026, 6, 16, 0, 1);
      await app.lifecycle.reconcile();
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.completed,
      );
    });

    test('a rolling arc is available in every month', () async {
      for (final month in [1, 5, 8, 9, 10, 12]) {
        final local = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, month, 3, 9)),
        );
        addTearDown(local.db.close);
        final setup = await local.winterArc.startNewArc(NewArcBaseline.fresh);
        expect(setup.kind, ArcKind.rolling92, reason: 'month $month');
      }
    });
  });

  group('availability', () {
    test(
      'January – August: the season is closed and setup is rejected',
      () async {
        for (final (month, day) in [(1, 1), (5, 20), (8, 31)]) {
          final season = SeasonalWinterRules.availabilityOn(
            LocalDate(2026, month, day),
          );
          expect(season.phase, SeasonPhase.closed);
          expect(season.canSetUp, isFalse);
        }
        app.clock.current = DateTime(2026, 8, 31, 23, 59);
        await expectLater(
          seasonalSetup(),
          _failsWith(DomainRule.seasonNotOpen),
        );
        expect(await app.sessions.listSessions(), isEmpty);
      },
    );

    test('September: preseason setup is allowed for 1 Oct – 31 Dec', () async {
      app.clock.current = DateTime(2026, 9, 1, 0, 5);
      expect(app.winterArc.seasonAvailability().phase, SeasonPhase.preseason);
      final setup = await seasonalSetup();
      expect(setup.kind, ArcKind.seasonalWinter);
      expect(setup.status, WinterArcStatus.setup);
      expect(setup.startDate, _oct1);
      expect(setup.endDate, _dec31);
      expect(setup.participationStartDate, isNull);
      expect(setup.lengthInDays, 92);
    });

    test(
      'October – December: the current season can be set up and joined',
      () async {
        for (final (month, day) in [(10, 1), (11, 15), (12, 31)]) {
          final season = SeasonalWinterRules.availabilityOn(
            LocalDate(2026, month, day),
          );
          expect(season.phase, SeasonPhase.inSeason);
          expect(season.seasonStart, _oct1);
          expect(season.seasonEnd, _dec31);
        }
        app.clock.current = DateTime(2026, 11, 2, 9);
        final setup = await seasonalSetup();
        expect(setup.startDate, _oct1);
        expect(setup.endDate, _dec31);
      },
    );
  });

  group('start rules', () {
    test(
      'a preseason setup cannot start before 1 Oct, even bypassing the UI',
      () async {
        await seasonalSetup();
        app.clock.current = DateTime(2026, 9, 30, 23, 59);
        await expectLater(
          app.winterArc.startWinterArc(),
          _failsWith(DomainRule.seasonNotStarted),
        );
        final setup = (await app.winterArc.setup());
        expect(setup.startState, SetupStartState.seasonNotStarted);
        expect(setup.canStart, isFalse);
        expect(setup.session.status, WinterArcStatus.setup);
      },
    );

    test('it is never started automatically at midnight', () async {
      await seasonalSetup();
      app.clock.current = DateTime(2026, 10, 1, 0, 1);
      await app.lifecycle.reconcile();
      final current = (await app.sessions.currentSession())!;
      expect(current.status, WinterArcStatus.setup);
      expect((await app.winterArc.setup()).startState, SetupStartState.ready);
    });

    for (final (date, day) in [
      (DateTime(2026, 10, 1), 1),
      (DateTime(2026, 10, 15), 15),
      (DateTime(2026, 11, 15), 46),
      (DateTime(2026, 12, 31), 92),
    ]) {
      test(
        'joining on ${LocalDate.fromDateTime(date)} is Day $day of 92',
        () async {
          final arc = await joinSeason(app, date);
          expect(arc.kind, ArcKind.seasonalWinter);
          expect(arc.status, WinterArcStatus.active);
          // Joining never moves the season.
          expect(arc.startDate, _oct1);
          expect(arc.endDate, _dec31);
          expect(arc.participationStartDate, LocalDate.fromDateTime(date));
          expect(arc.joinDayNumber, day);
          expect(arc.joinedLate, day > 1);
          expect(arc.participationLengthInDays, 92 - day + 1);
          final position = arc.positionOn(app.clock.today());
          expect(position, isA<ArcInProgress>());
          expect((position as ArcInProgress).dayNumber, day);
          final today = (await app.tracking.today()).position;
          expect((today as ArcInProgress).dayNumber, day);
          expect(today.totalDays, 92);
          expect(WinterArcRules.problemWith(arc), isNull);
        },
      );
    }

    test('a preseason setup joined on 1 Oct is Day 1', () async {
      await seasonalSetup();
      app.clock.current = DateTime(2026, 10, 1, 7);
      final arc = await app.winterArc.startWinterArc();
      expect(arc.participationStartDate, _oct1);
      expect(arc.joinedLate, isFalse);
    });

    test(
      'a setup that reaches 1 Jan is never started or moved to next year',
      () async {
        app.clock.current = DateTime(2026, 12, 20, 9);
        final setup = await seasonalSetup();
        app.clock.current = DateTime(2027, 1, 1, 9);
        await expectLater(
          app.winterArc.startWinterArc(),
          _failsWith(DomainRule.seasonEnded),
        );
        final state = await app.winterArc.setup();
        expect(state.startState, SetupStartState.seasonEnded);
        expect(state.session.startDate, _oct1);
        expect(state.session.endDate, _dec31);
        // It can still be cancelled, and then a new Arc can be chosen.
        await app.winterArc.cancelSetup();
        expect(await app.sessions.sessionById(setup.id), isNull);
        final rolling = await app.winterArc.startNewArc(NewArcBaseline.fresh);
        expect(rolling.kind, ArcKind.rolling92);
      },
    );

    test('starting is idempotent', () async {
      final arc = await joinSeason(app, DateTime(2026, 10, 15));
      app.clock.current = DateTime(2026, 10, 16, 9);
      final again = await app.winterArc.startWinterArc();
      expect(again.participationStartDate, arc.participationStartDate);
    });
  });

  group('close-out', () {
    test(
      'a seasonal arc stays active through all of 31 Dec, joined late',
      () async {
        final arc = await joinSeason(app, DateTime(2026, 12, 20));
        app.clock.current = DateTime(2026, 12, 31, 23, 59);
        await app.lifecycle.reconcile();
        expect(
          (await app.sessions.sessionById(arc.id))!.status,
          WinterArcStatus.active,
        );
      },
    );

    test('1 Jan closes it, without moving any date', () async {
      final arc = await joinSeason(app, DateTime(2026, 10, 15));
      app.clock.current = DateTime(2027, 1, 1, 0, 1);
      final closed = (await app.lifecycle.reconcile())!;
      expect(closed.id, arc.id);
      expect(closed.status, WinterArcStatus.completed);
      expect(closed.startDate, _oct1);
      expect(closed.endDate, _dec31);
      expect(closed.participationStartDate, LocalDate(2026, 10, 15));
    });
  });

  group('session invariants', () {
    WinterArcSession session({
      required ArcKind kind,
      required LocalDate start,
      required LocalDate end,
      WinterArcStatus status = WinterArcStatus.active,
      LocalDate? joined,
    }) => WinterArcSession(
      id: 1,
      kind: kind,
      startDate: start,
      endDate: end,
      status: status,
      createdAt: DateTime(2026),
      participationStartDate: joined,
    );

    test('rolling: 92 days, joined on the start once started', () {
      final start = LocalDate(2026, 3, 1);
      final end = WinterArcRules.endDateFor(start);
      expect(
        WinterArcRules.problemWith(
          session(
            kind: ArcKind.rolling92,
            start: start,
            end: end,
            joined: start,
          ),
        ),
        isNull,
      );
      expect(
        WinterArcRules.problemWith(
          session(
            kind: ArcKind.rolling92,
            start: start,
            end: end,
            joined: start.addDays(3),
          ),
        ),
        isNotNull,
      );
      expect(
        WinterArcRules.problemWith(
          session(kind: ArcKind.rolling92, start: start, end: end),
        ),
        isNotNull,
        reason: 'a started arc has a participation date',
      );
      expect(
        WinterArcRules.problemWith(
          session(
            kind: ArcKind.rolling92,
            start: start,
            end: end.addDays(1),
            joined: start,
          ),
        ),
        isNotNull,
      );
    });

    test('seasonal: 1 Oct – 31 Dec of one year, joined inside it', () {
      expect(
        WinterArcRules.problemWith(
          session(
            kind: ArcKind.seasonalWinter,
            start: _oct1,
            end: _dec31,
            joined: LocalDate(2026, 11, 3),
          ),
        ),
        isNull,
      );
      for (final (start, end, joined) in [
        (LocalDate(2026, 10, 2), _dec31, LocalDate(2026, 10, 2)),
        (_oct1, LocalDate(2027, 12, 31), _oct1),
        (_oct1, _dec31, LocalDate(2026, 9, 30)),
        (_oct1, _dec31, LocalDate(2027, 1, 1)),
      ]) {
        expect(
          WinterArcRules.problemWith(
            session(
              kind: ArcKind.seasonalWinter,
              start: start,
              end: end,
              joined: joined,
            ),
          ),
          isNotNull,
          reason: '$start – $end joined $joined',
        );
      }
    });

    test(
      'a setup has no participation date; the end never precedes the start',
      () {
        expect(
          WinterArcRules.problemWith(
            session(
              kind: ArcKind.seasonalWinter,
              start: _oct1,
              end: _dec31,
              status: WinterArcStatus.setup,
              joined: _oct1,
            ),
          ),
          isNotNull,
        );
        expect(
          WinterArcRules.problemWith(
            session(
              kind: ArcKind.rolling92,
              start: _dec31,
              end: _oct1,
              status: WinterArcStatus.setup,
            ),
          ),
          isNotNull,
        );
      },
    );

    test(
      'kind is stored, never inferred: a rolling arc from 1 Oct stays rolling',
      () async {
        app.clock.current = DateTime(2026, 10, 1, 9);
        await app.winterArc.beginSetup();
        final arc = await app.winterArc.startWinterArc();
        expect(arc.startDate, _oct1);
        expect(arc.endDate, _dec31);
        expect(arc.kind, ArcKind.rolling92);
        expect(
          (await app.sessions.sessionById(arc.id))!.kind,
          ArcKind.rolling92,
        );
      },
    );

    test('only one unfinished arc, whatever its kind', () async {
      await seasonalSetup();
      await expectLater(
        app.winterArc.startNewArc(NewArcBaseline.fresh),
        _failsWith(DomainRule.arcInProgress),
      );
    });
  });
}
