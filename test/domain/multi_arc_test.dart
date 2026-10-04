import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/habit/starter_habits.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

void main() {
  late TestApp app;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1, 8)));
  });
  tearDown(() => app.db.close());

  Future<String> home() async => AppRoutes.home(await app.lifecycle.resolve());

  group('starting another arc', () {
    test('a completed arc allows a new setup arc', () async {
      final first = await runFirstArc(app);
      expect(first.status, WinterArcStatus.completed);
      expect(await app.winterArc.currentSession(), isNull);

      final next = await app.winterArc.startNewArc(NewArcBaseline.fresh);
      expect(next.id, isNot(first.id));
      expect(next.status, WinterArcStatus.setup);
      expect((await app.winterArc.currentSession())!.id, next.id);
      expect(await app.sessions.listSessions(), hasLength(2));
    });

    test('an active arc prevents another arc', () async {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      for (final baseline in NewArcBaseline.values) {
        await expectLater(
          app.winterArc.startNewArc(baseline),
          _failsWith(DomainRule.arcInProgress),
        );
      }
      expect(await app.sessions.listSessions(), hasLength(1));
    });

    test('a setup arc prevents another setup arc', () async {
      await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.fresh);
      await expectLater(
        app.winterArc.startNewArc(NewArcBaseline.reuseLast),
        _failsWith(DomainRule.arcInProgress),
      );
      // Even concurrent attempts create a single arc.
      final attempts = await Future.wait([
        for (var i = 0; i < 3; i++)
          app.winterArc
              .startNewArc(NewArcBaseline.fresh)
              .then<Object>((s) => s, onError: (Object e) => e),
      ]);
      expect(attempts.whereType<WinterArcSession>(), isEmpty);
      expect(await app.sessions.listSessions(), hasLength(2));
    });

    test('the store itself refuses a second unfinished arc', () async {
      await app.winterArc.beginSetup();
      await expectLater(
        app.sessions.createSetupSession(
          kind: ArcKind.rolling92,
          startDate: app.clock.today(),
          endDate: WinterArcRules.endDateFor(app.clock.today()),
          createdAt: app.clock.now(),
          habits: StarterHabits.seed(app.clock.now()),
        ),
        _failsWith(DomainRule.arcInProgress),
      );
      // The database index backs this up even if the check were bypassed.
      await expectLater(
        app.db.customStatement(
          'INSERT INTO winter_arc_sessions (start_date, end_date, status, '
          "created_at) VALUES ('2026-07-01', '2026-09-30', 'active', 0)",
        ),
        throwsA(anything),
      );
    });

    test('reusing needs a completed arc', () async {
      await expectLater(
        app.winterArc.startNewArc(NewArcBaseline.reuseLast),
        _failsWith(DomainRule.noCompletedArc),
      );
      expect(await app.winterArc.reusableHabits(), isNull);
      expect(await app.sessions.listSessions(), isEmpty);
    });

    test('a fresh arc starts from the starter habits', () async {
      await runFirstArc(app);
      final next = await app.winterArc.startNewArc(NewArcBaseline.fresh);
      final habits = await app.habits.habitsForSession(next.id);
      expect(habits.map((h) => h.id), StarterHabits.all.map((t) => t.id));
      for (final (h, t) in [
        for (final h in habits)
          (h, StarterHabits.all.firstWhere((t) => t.id == h.id)),
      ]) {
        expect(h.title, t.title);
        expect(h.target, t.target);
        expect(h.minimumTarget, t.minimumTarget);
        expect(h.enabled, t.enabledByDefault);
      }
    });

    test(
      'a reused arc starts from the final effective configuration',
      () async {
        await runFirstArc(app);
        final next = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
        final habits = {
          for (final h in await app.habits.habitsForSession(next.id)) h.id: h,
        };
        expect(habits.keys, StarterHabits.all.map((t) => t.id));
        // The rename, the raised goal and the switch-off made during Arc 1
        // are the new baseline; untouched habits keep theirs.
        expect(habits['workout']!.title, 'Strength');
        expect(habits['workout']!.target, 30);
        expect(habits['water']!.target, 10);
        expect(habits['water']!.minimumTarget, 4);
        expect(habits['learning']!.enabled, isFalse);
        expect(habits['no_junk_food']!.enabled, isTrue);
        expect(habits['english']!.enabled, isFalse);
        for (final h in habits.values) {
          final t = StarterHabits.all.firstWhere((t) => t.id == h.id);
          expect(h.type, t.type);
          expect(h.unit, t.unit);
          expect(h.iconKey, t.iconKey);
          expect(h.sortOrder, StarterHabits.all.indexOf(t));
        }
        // The preview shows exactly what reuse creates.
        final preview = await app.winterArc.reusableHabits();
        expect(
          preview!.map((h) => (h.id, h.title, h.target, h.enabled)),
          habits.values.map((h) => (h.id, h.title, h.target, h.enabled)),
        );
      },
    );

    test('a reused arc copies no progress, XP, revisions, modes, achievements '
        'or reflections', () async {
      final first = await runFirstArc(app);
      final next = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      app.clock.current = DateTime(2026, 10, 2, 8);
      await app.winterArc.startWinterArc();

      final today = await app.tracking.today();
      expect(today.session.id, next.id);
      expect(today.totalXp, 0);
      expect(today.level.level, 1);
      expect(today.perfectDays.total, 0);
      expect(today.entries.every((e) => e.progress.currentValue == 0), isTrue);
      expect(today.habitStreaks.values.every((s) => s.best == 0), isTrue);

      final rows = await snapshotOf(app.db, next.id);
      // Only the session row and its seven habits.
      expect(rows, hasLength(1 + StarterHabits.all.length));
      expect((await app.achievements.boardFor(next.id)).unlockedCount, isZero);
      expect((await app.reflections.journalFor(next.id)).count, isZero);
      // First Rep, Clean Sweep, Still Moving, Looking Inward, Midwinter,
      // Summit.
      expect((await app.achievements.boardFor(first.id)).unlockedCount, 6);
    });

    test('starting another arc never changes the completed one', () async {
      final first = await runFirstArc(app);
      final before = await snapshotOf(app.db, first.id);
      final summaryBefore = await app.history.card(first.id);
      final journeyBefore = await app.tracking.journeyFor(first.id);

      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      app.clock.current = DateTime(2026, 10, 2, 8);
      await app.winterArc.startWinterArc();
      await app.tracking.activateMinimumDay(date: app.clock.today());
      await completeAll(app);
      await app.reflections.save(
        sessionId: (await app.winterArc.currentSession())!.id,
        date: app.clock.today(),
        draft: const ReflectionDraft(mood: Mood.excellent),
      );
      await app.achievements.reconcile();

      expect(await snapshotOf(app.db, first.id), before);
      final summaryAfter = await app.history.card(first.id);
      expect(summaryAfter.summary.totalXp, summaryBefore.summary.totalXp);
      expect(
        summaryAfter.summary.achievementsUnlocked,
        summaryBefore.summary.achievementsUnlocked,
      );
      expect(summaryAfter.reflectionCount, 1);
      final journeyAfter = await app.tracking.journeyFor(first.id);
      expect(
        journeyAfter.days.map((d) => (d.state, d.xpEarned)),
        journeyBefore.days.map((d) => (d.state, d.xpEarned)),
      );
    });

    test('the second arc has Day 1 on its own start date', () async {
      final first = await runFirstArc(app);
      final next = await app.winterArc.startNewArc(NewArcBaseline.fresh);
      // Set up on 1 Oct, started two days later: the start date is the day
      // Start is pressed.
      app.clock.current = DateTime(2026, 10, 3, 7);
      final started = await app.winterArc.startWinterArc();
      expect(started.id, next.id);
      expect(started.startDate, LocalDate(2026, 10, 3));
      expect(started.endDate, LocalDate(2027, 1, 2));
      expect(started.startedAt, DateTime(2026, 10, 3, 7));
      final today = await app.tracking.today();
      expect(today.position, isA<ArcInProgress>());
      expect((today.position as ArcInProgress).dayNumber, 1);
      // Arc 1 keeps its own window.
      final firstAfter = (await app.sessions.sessionById(first.id))!;
      expect(firstAfter.startDate, LocalDate(2026, 7, 1));
      expect(firstAfter.endDate, LocalDate(2026, 9, 30));
    });

    test(
      'the second arc closes out on its own and leaves Arc 1 alone',
      () async {
        final first = await runFirstArc(app);
        await app.winterArc.startNewArc(NewArcBaseline.fresh);
        app.clock.current = DateTime(2026, 10, 2, 8);
        final second = await app.winterArc.startWinterArc();
        // Arc 2 runs 2 Oct → 1 Jan, so 2 Jan is its Day 93.
        app.clock.current = DateTime(2027, 1, 2, 8);
        final lead = await app.lifecycle.reconcile();
        expect(lead!.id, second.id);
        expect(lead.status, WinterArcStatus.completed);
        expect(
          (await app.sessions.sessionById(first.id))!.status,
          WinterArcStatus.completed,
        );
        expect(await home(), AppRoutes.arc(second.id));
      },
    );
  });

  group('boot resolution', () {
    test('no sessions → onboarding', () async {
      expect(await home(), AppRoutes.onboarding);
    });

    test('a setup arc → Habit Setup', () async {
      await app.winterArc.beginSetup();
      expect(await home(), AppRoutes.habitSetup);
    });

    test('an active arc → Today', () async {
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      expect(await home(), AppRoutes.today);
    });

    test('only completed arcs → the latest completed summary', () async {
      final first = await runFirstArc(app);
      expect(await home(), AppRoutes.arc(first.id));
      // A second completed arc becomes the home.
      await app.winterArc.startNewArc(NewArcBaseline.fresh);
      final second = await app.winterArc.startWinterArc();
      app.clock.current = DateTime(2027, 1, 1, 8);
      expect(await home(), AppRoutes.arc(second.id));
    });

    test('a completed arc plus a new setup arc → Habit Setup', () async {
      await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      expect(await home(), AppRoutes.habitSetup);
    });

    test('a completed arc plus an active arc → Today', () async {
      await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      await app.winterArc.startWinterArc();
      expect(await home(), AppRoutes.today);
    });

    test('nothing is created automatically', () async {
      await runFirstArc(app);
      for (var i = 0; i < 3; i++) {
        await home();
      }
      expect(await app.sessions.listSessions(), hasLength(1));
    });
  });

  test('Arc A and Arc B never leak into each other', () async {
    final a = await runFirstArc(app);
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    app.clock.current = DateTime(2026, 10, 2, 8);
    final b = await app.winterArc.startWinterArc();
    // Arc B, Day 1: only No Junk Food, and a rough-day reflection.
    await app.tracking.perform(
      habitId: 'no_junk_food',
      action: HabitAction.complete,
      date: app.clock.today(),
    );
    await app.reflections.save(
      sessionId: b.id,
      date: app.clock.today(),
      draft: const ReflectionDraft(mood: Mood.rough),
    );
    await app.achievements.reconcile();

    final historyA = await app.tracking.historyFor(a.id);
    final historyB = await app.tracking.historyFor(b.id);
    expect(historyA.records.totalXp, 4 * 15 + 30 + 3 * 15);
    expect(historyB.records.totalXp, 15);

    // Habits and their revisions.
    expect(historyA.records.habits.revisions, hasLength(2));
    expect(historyB.records.habits.revisions, isEmpty);
    final waterA = historyA.records.habits.habit('water')!;
    expect(historyA.records.habits.configOn(waterA, a.startDate).target, 8);
    final waterB = historyB.records.habits.habit('water')!;
    expect(historyB.records.habits.configOn(waterB, b.startDate).target, 10);

    // Progress and day modes.
    final journeyA = await app.tracking.journeyFor(a.id);
    final journeyB = await app.tracking.journeyFor(b.id);
    expect(journeyA.days.take(3).map((d) => d.state), [
      JourneyDayState.perfect,
      JourneyDayState.missed,
      JourneyDayState.minimumComplete,
    ]);
    expect(journeyB.days.first.state, JourneyDayState.today);
    expect(journeyB.days.first.record!.completion.completed, 1);
    expect(historyB.records.modes, isEmpty);

    // Achievements and reflections.
    final boardA = await app.achievements.boardFor(a.id);
    final boardB = await app.achievements.boardFor(b.id);
    bool has(AchievementBoard board, AchievementKey key) =>
        board.entries.any((e) => e.definition.key == key && e.unlocked);
    expect(has(boardA, AchievementKey.summit), isTrue);
    expect(has(boardB, AchievementKey.summit), isFalse);
    expect(has(boardB, AchievementKey.firstRep), isTrue);
    expect(has(boardB, AchievementKey.firstReflection), isTrue);
    final journalA = await app.reflections.journalFor(a.id);
    final journalB = await app.reflections.journalFor(b.id);
    expect(journalA.past.single.mood, Mood.good);
    expect(journalB.todayEntry!.mood, Mood.rough);
    expect(journalB.past, isEmpty);

    // The home views follow the active arc only.
    expect((await app.tracking.today()).session.id, b.id);
    expect((await app.achievements.board())!.startDate, b.startDate);
    expect((await app.reflections.journal()).session.id, b.id);
  });
}
