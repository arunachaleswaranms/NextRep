import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1, 8)));
  });
  tearDown(() => app.db.close());

  test('lists started arcs newest first, without the arc in setup', () async {
    expect(await app.history.sessions(), isEmpty);
    final first = await runFirstArc(app);
    await app.winterArc.startNewArc(NewArcBaseline.fresh);
    expect((await app.history.sessions()).map((s) => s.id), [first.id]);

    app.clock.current = DateTime(2026, 10, 2, 8);
    final second = await app.winterArc.startWinterArc();
    final listed = await app.history.sessions();
    expect(listed.map((s) => s.id), [second.id, first.id]);
    expect(listed.map((s) => s.status), [
      WinterArcStatus.active,
      WinterArcStatus.completed,
    ]);
  });

  test('a completed arc card shows its final results', () async {
    final first = await runFirstArc(app);
    final card = await app.history.card(first.id);
    final s = card.summary;
    // Day 1 Perfect (4 × 15 + 30), Day 3 a completed Minimum Day (3 × 15).
    expect(s.totalXp, 135);
    expect(s.level.level, 1);
    expect(s.perfectDays, 1);
    expect(s.bestPerfectStreak, 1);
    expect(s.minimumDaysCompleted, 1);
    expect(s.fullDays, 2);
    expect(s.daysElapsed, 92);
    expect(s.consistencyPercent, 2); // 2 of 92 days, rounded down
    expect(s.achievementsUnlocked, 6);
    expect(s.achievementsTotal, 15);
    expect(card.reflectionCount, 1);
    expect(card.session.startDate, first.startDate);
  });

  test(
    'the active arc card reflects today so far, only its own data',
    () async {
      final first = await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      app.clock.current = DateTime(2026, 10, 2, 8);
      final second = await app.winterArc.startWinterArc();
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: app.clock.today(),
      );
      final card = await app.history.card(second.id);
      expect(card.summary.totalXp, 15);
      expect(card.summary.daysElapsed, 1);
      expect(card.summary.achievementsUnlocked, 0); // not reconciled yet
      expect(card.reflectionCount, 0);
      expect((await app.history.card(first.id)).summary.totalXp, 135);

      await app.reflections.save(
        sessionId: second.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(win: 'Back at it'),
      );
      expect((await app.history.card(second.id)).reflectionCount, 1);
      expect((await app.history.card(first.id)).reflectionCount, 1);
    },
  );

  test('a setup or unknown arc has no card', () async {
    final setup = await app.winterArc.beginSetup();
    await expectLater(
      app.history.card(setup.id),
      throwsA(
        isA<DomainFailure>().having(
          (f) => f.rule,
          'rule',
          DomainRule.noActiveSession,
        ),
      ),
    );
    await expectLater(
      app.history.card(999),
      throwsA(
        isA<DomainFailure>().having(
          (f) => f.rule,
          'rule',
          DomainRule.sessionNotFound,
        ),
      ),
    );
  });
}
