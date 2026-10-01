import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/starter_habits.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 8)));
  });
  tearDown(() => app.db.close());

  group('session configuration', () {
    test('no session exists before onboarding', () async {
      expect(await app.winterArc.currentSession(), isNull);
    });

    test(
      'beginSetup creates a setup session seeded with starter habits',
      () async {
        final session = await app.winterArc.beginSetup();
        expect(session.status, WinterArcStatus.setup);

        final habits = await app.winterArc.setupHabits();
        expect(habits.map((h) => h.id), StarterHabits.all.map((t) => t.id));
        expect(
          habits.map((h) => h.enabled),
          StarterHabits.all.map((t) => t.enabledByDefault),
        );
      },
    );

    test('beginSetup is idempotent, including concurrent calls', () async {
      final results = await Future.wait([
        app.winterArc.beginSetup(),
        app.winterArc.beginSetup(),
        app.winterArc.beginSetup(),
      ]);
      expect(results.map((s) => s.id).toSet(), hasLength(1));
      final rows = await app.db.select(app.db.winterArcSessions).get();
      expect(rows, hasLength(1));
    });

    test(
      'startWinterArc activates with Day 1 = today and a 92-day window',
      () async {
        await app.winterArc.beginSetup();
        app.clock.current = DateTime(2026, 10, 1, 21, 15);

        final started = await app.winterArc.startWinterArc();

        expect(started.status, WinterArcStatus.active);
        expect(started.startDate, LocalDate(2026, 10, 1));
        expect(started.endDate, LocalDate(2026, 12, 31));
        expect(started.startedAt, DateTime(2026, 10, 1, 21, 15));
        final reloaded = await app.winterArc.currentSession();
        expect(reloaded!.status, WinterArcStatus.active);
        expect(reloaded.endDate, LocalDate(2026, 12, 31));
      },
    );

    test('start date is recomputed if setup spans midnight', () async {
      await app.winterArc.beginSetup();
      app.clock.current = DateTime(2026, 10, 2, 0, 5);
      final started = await app.winterArc.startWinterArc();
      expect(started.startDate, LocalDate(2026, 10, 2));
      expect(started.endDate, LocalDate(2027, 1, 1));
    });

    test('cannot start with no habits selected', () async {
      await app.winterArc.beginSetup();
      for (final t in StarterHabits.all) {
        await app.winterArc.setHabitEnabled(t.id, enabled: false);
      }
      expect(
        app.winterArc.startWinterArc(),
        _failsWith(DomainRule.noHabitsSelected),
      );
      expect(
        (await app.winterArc.currentSession())!.status,
        WinterArcStatus.setup,
      );
    });

    test('startWinterArc is idempotent once active', () async {
      await app.winterArc.beginSetup();
      final first = await app.winterArc.startWinterArc();
      app.clock.advance(const Duration(days: 3));
      final second = await app.winterArc.startWinterArc();
      expect(second.startDate, first.startDate);
    });

    test('habits cannot be reconfigured through setup once active', () async {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      expect(
        app.winterArc.setHabitEnabled('water', enabled: false),
        _failsWith(DomainRule.sessionNotInSetup),
      );
    });

    test('unknown habit is reported, not ignored', () async {
      await app.winterArc.beginSetup();
      expect(
        app.winterArc.setHabitEnabled('nope', enabled: true),
        _failsWith(DomainRule.habitNotFound),
      );
    });
  });

  group('habit selection persistence', () {
    test('toggles are persisted and survive a new service instance', () async {
      await app.winterArc.beginSetup();
      await app.winterArc.setHabitEnabled('english', enabled: true);
      await app.winterArc.setHabitEnabled('water', enabled: false);

      final fresh = TestApp(app.db, app.clock);
      final habits = {
        for (final h in await fresh.winterArc.setupHabits()) h.id: h,
      };
      expect(habits['english']!.enabled, isTrue);
      expect(habits['water']!.enabled, isFalse);
    });
  });
}
