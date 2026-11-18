import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';

import 'arcs.dart';
import 'fakes.dart';
import 'review_db.dart';

/// Phase 12B: a populated synthetic database for the Weekly Review's
/// widget, read-only and layout tests. Every table that holds data has
/// rows: sessions (completed, ended, active), habits, revisions, progress,
/// day modes, XP, unlocks, reflections, freezes, reminder, Focus Guard and
/// feedback preferences.
final class ReviewSeed {
  const ReviewSeed({
    required this.completedId,
    required this.endedId,
    required this.activeId,
  });

  /// Arc 1: Rolling, 1 Jul – 30 Sep 2026, completed (Days 1–3 lived).
  final int completedId;

  /// Arc 2: Rolling from 2 Oct 2026, ended on its Day 3 (4 Oct).
  final int endedId;

  /// Arc 3: Rolling from 6 Oct 2026 with a long custom habit, paused 9–11
  /// Oct (resumed 12 Oct), lived through 20 Oct.
  final int activeId;

  /// Day 1 of Arc 3.
  static final activeStart = LocalDate(2026, 10, 6);

  /// "Today" for the in-progress state: 21 Oct, Day 13 (Week 2, Days
  /// 8–14 = 16–22 Oct).
  static final today = LocalDate(2026, 10, 21);

  /// The long custom habit's title.
  static final longTitle = 'W' * 40;
}

/// Seeds [app]. With [pausedFrom] Arc 3 is also paused from that date
/// (open), and the clock is left inside the pause; otherwise it is left on
/// [ReviewSeed.today] at 13:00 with one habit done today.
Future<ReviewSeed> seedReviewData(TestApp app, {LocalDate? pausedFrom}) async {
  final completed = await runFirstArc(app); // leaves the clock on 1 Oct

  at(app, LocalDate(2026, 10, 2));
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  final ended = await app.winterArc.startWinterArc();
  for (final d in [2, 3, 4]) {
    at(app, LocalDate(2026, 10, d));
    await completeAll(app);
    await app.achievements.sync();
  }
  await endArc(app, ended.id, LocalDate(2026, 10, 4));

  at(app, ReviewSeed.activeStart);
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  await app.winterArc.addCustomHabit(
    HabitDraft(
      title: ReviewSeed.longTitle,
      type: HabitType.count,
      iconKey: 'star',
      target: 12,
      minimumTarget: 3,
      unit: 'pages',
    ),
  );
  final active = await app.winterArc.startWinterArc();
  for (final d in [6, 7, 8]) {
    at(app, LocalDate(2026, 10, d));
    await completeAll(app);
    await app.achievements.sync();
  }
  // Paused 9–11 Oct, resumed 12 Oct (as Freeze and Resume will store it).
  await addFreeze(app.db, active.id, LocalDate(2026, 10, 9));
  await resume(app, active.id, LocalDate(2026, 10, 9), LocalDate(2026, 10, 12));

  final habits = (await app.tracking.today()).entries;
  for (var d = 12; d <= 20; d++) {
    final date = LocalDate(2026, 10, d);
    at(app, date);
    switch (d) {
      case 13: // a hard day: one habit
        await completeHabit(app, habits.first.habit.id);
      case 14: // a completed Minimum Day
        await app.tracking.activateMinimumDay(date: date);
        await completeAll(app);
      case 15: // nothing logged
        break;
      case 16:
        await app.tracking.editHabit(
          habitId: habits.first.habit.id,
          edit: const HabitEdit(target: 10, minimumTarget: 3),
          date: date,
        );
        await completeAll(app);
      default:
        await completeAll(app);
    }
    await app.achievements.sync();
  }
  at(app, LocalDate(2026, 10, 20));
  await app.reflections.save(
    sessionId: active.id,
    date: LocalDate(2026, 10, 20),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Kept going'),
  );

  await app.reminders.update(
    (p) => p.copyWith(
      dailyEnabled: true,
      reflectionEnabled: true,
      hydrationEnabled: true,
      hydrationMode: HydrationMode.supportive,
    ),
  );
  await DriftFocusGuardSettingsRepository(app.db).save(
    const FocusGuardSettings(
      enabled: true,
      dailyBudgetMinutes: 45,
      selectedPackages: ['org.example.video'],
    ),
    at: app.clock.now(),
  );
  await DriftFeedbackPreferencesRepository(app.db).save(
    const FeedbackPreferences(
      soundsEnabled: false,
      soundTheme: SoundTheme.warmEmber,
    ),
    at: app.clock.now(),
  );

  if (pausedFrom != null) {
    await addFreeze(app.db, active.id, pausedFrom);
    at(app, pausedFrom.addDays(2), hour: 13);
  } else {
    final today = ReviewSeed.today;
    at(app, today, hour: 13);
    await completeHabit(app, habits.first.habit.id);
  }
  return ReviewSeed(
    completedId: completed.id,
    endedId: ended.id,
    activeId: active.id,
  );
}
