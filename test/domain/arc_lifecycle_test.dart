import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/progress/arc_summary.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/arc_lifecycle_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_repository.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Arc close-out with an injected clock. The arc starts on Oct 1, so Day 92
/// is Dec 31 and Day 93 is Jan 1.
void main() {
  late TestApp app;
  final day92 = LocalDate(2026, 12, 31);

  setUp(() async {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 8)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
  });
  tearDown(() => app.db.close());

  // The only session of these tests; once completed it is no longer
  // "current", so look it up as the latest.
  Future<WinterArcStatus> status() async =>
      (await app.sessions.latestSession())!.status;

  test(
    'the arc stays active on every day up to and including Day 92',
    () async {
      for (final date in [
        DateTime(2026, 10, 1, 8),
        DateTime(2026, 11, 15, 12),
        DateTime(2026, 12, 31, 0, 0),
        DateTime(2026, 12, 31, 23, 59, 59),
      ]) {
        app.clock.current = date;
        expect(
          (await app.lifecycle.reconcile())!.status,
          WinterArcStatus.active,
        );
      }
      expect(await status(), WinterArcStatus.active);

      // Day 92 is tracked normally.
      final commit = await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: day92,
      );
      expect(commit.xpAfter, 15);
      expect((await app.tracking.today()).isTrackable, isTrue);
    },
  );

  test('the day after the end closes the arc, once', () async {
    app.clock.current = DateTime(2027, 1, 1, 0, 0, 1);
    final counting = _CountingSessions(app.sessions);
    final lifecycle = ArcLifecycleService(sessions: counting, clock: app.clock);

    final closed = await lifecycle.reconcile();
    expect(closed!.status, WinterArcStatus.completed);
    expect(closed.startDate, LocalDate(2026, 10, 1));
    expect(closed.endDate, day92);
    expect(await status(), WinterArcStatus.completed);

    // Idempotent: further runs (and concurrent ones) write nothing.
    await Future.wait([lifecycle.reconcile(), lifecycle.reconcile()]);
    app.clock.current = DateTime(2027, 3, 1);
    expect((await lifecycle.reconcile())!.status, WinterArcStatus.completed);
    expect(counting.updates, 1);
  });

  test('a session in setup, or no session, is left alone', () async {
    final fresh = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 6, 1)));
    addTearDown(fresh.db.close);
    expect(await fresh.lifecycle.reconcile(), isNull);
    await fresh.winterArc.beginSetup();
    expect((await fresh.lifecycle.reconcile())!.status, WinterArcStatus.setup);
  });

  group('a completed arc', () {
    setUp(() async {
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: LocalDate(2026, 10, 1),
      );
      app.clock.current = DateTime(2027, 1, 2, 9);
      await app.lifecycle.reconcile();
    });

    test('rejects every habit write', () async {
      final today = app.clock.today();
      expect(
        app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: today,
        ),
        _failsWith(DomainRule.arcCompleted),
      );
      expect(
        app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: day92,
        ),
        _failsWith(DomainRule.arcCompleted),
      );
      expect(
        app.tracking.activateMinimumDay(date: today),
        _failsWith(DomainRule.arcCompleted),
      );
      expect(
        app.tracking.editHabit(
          habitId: 'water',
          edit: const HabitEdit(title: 'x'),
          date: today,
        ),
        _failsWith(DomainRule.arcCompleted),
      );
      final summary = await app.tracking.today();
      expect(summary.isTrackable, isFalse);
      expect(summary.canSwitchToMinimum, isFalse);
      final settings = await app.tracking.habitSettings();
      expect(settings.editable, isFalse);
      expect(settings.configEditable, isFalse);
    });

    test('still loads its Journey', () async {
      final journey = await app.tracking.journey();
      expect(journey.days, hasLength(92));
      expect(journey.days.any((d) => d.isToday || d.isFuture), isFalse);
      expect(journey.days.first.xpEarned, 15);
      expect(journey.days.first.state, JourneyDayState.partial);
      expect(journey.days.last.state, JourneyDayState.missed);
      expect(journey.position, isA<ArcFinished>());
    });

    test('still loads and reconciles its achievements', () async {
      final unlocked = await app.achievements.reconcile();
      expect(unlocked.map((u) => u.key), [
        AchievementKey.firstRep,
        AchievementKey.halfway,
        AchievementKey.summit,
      ]);
      expect(unlocked.last.unlockedOn, day92);
      final board = (await app.achievements.board())!;
      expect(board.unlockedCount, 3);
    });

    test('still loads its summary', () async {
      final summary = ArcSummary.fromHistory(
        await app.tracking.history(),
        achievementsUnlocked: 0,
        achievementsTotal: 10,
      );
      expect(summary.daysElapsed, 92);
      expect(summary.totalXp, 15);
      expect(summary.habitsCompleted, 1);
      expect(summary.strongestHabit!.habit.type, HabitType.binary);
    });
  });
}

/// Counts session writes made through it.
final class _CountingSessions implements WinterArcRepository {
  _CountingSessions(this._inner);

  final WinterArcRepository _inner;
  int updates = 0;

  @override
  Future<WinterArcSession?> latestSession() => _inner.latestSession();

  @override
  Future<WinterArcSession?> currentSession() => _inner.currentSession();

  @override
  Future<WinterArcSession?> latestCompletedSession() =>
      _inner.latestCompletedSession();

  @override
  Future<WinterArcSession?> sessionById(int id) => _inner.sessionById(id);

  @override
  Future<List<WinterArcSession>> listSessions() => _inner.listSessions();

  @override
  Future<WinterArcSession> createSetupSession({
    required LocalDate startDate,
    required LocalDate endDate,
    required DateTime createdAt,
    required List<Habit> habits,
  }) => _inner.createSetupSession(
    startDate: startDate,
    endDate: endDate,
    createdAt: createdAt,
    habits: habits,
  );

  @override
  Future<void> updateSession(WinterArcSession session) {
    updates++;
    return _inner.updateSession(session);
  }

  @override
  Future<void> deleteSession(int id, {required WinterArcStatus expected}) =>
      _inner.deleteSession(id, expected: expected);
}
