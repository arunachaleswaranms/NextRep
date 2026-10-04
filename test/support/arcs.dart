import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import 'fakes.dart';

/// Completes [habitId] today through the real tracking service, one tap at
/// a time, as a user would.
Future<void> completeHabit(TestApp app, String habitId) async {
  while (true) {
    final today = await app.tracking.today();
    final entry = today.entries.firstWhere((e) => e.habit.id == habitId);
    if (entry.progress.completed) return;
    await app.tracking.perform(
      habitId: habitId,
      action: entry.habit.type.isNumeric
          ? HabitAction.increment
          : HabitAction.complete,
      date: today.date,
    );
  }
}

/// Completes every habit enabled today.
Future<void> completeAll(TestApp app) async {
  for (final entry in (await app.tracking.today()).entries) {
    await completeHabit(app, entry.habit.id);
  }
}

/// Arc 1, run through the real services from [start] (default Wed 1 Jul
/// 2026, so Day 92 is 30 Sep) and closed out on Day 93:
///
/// * Day 1: a Perfect Day (the four default habits).
/// * Day 2: workout renamed "Strength"; water's goal raised to 10 (minimum
///   4) and learning turned off, both effective from Day 3.
/// * Day 3: a completed Minimum Day and a reflection.
///
/// Leaves the clock on Day 93 at 09:00 (1 Oct 2026 by default) and returns
/// the completed arc.
Future<WinterArcSession> runFirstArc(TestApp app, {DateTime? start}) async {
  final day1 = start ?? DateTime(2026, 7, 1);
  DateTime day(int n, int hour) =>
      DateTime(day1.year, day1.month, day1.day + n - 1, hour);
  app.clock.current = day(1, 8);
  await app.winterArc.beginSetup();
  final arc = await app.winterArc.startWinterArc();
  await completeAll(app);

  app.clock.current = day(2, 8);
  final day2 = app.clock.today();
  for (final (id, edit) in const [
    ('workout', HabitEdit(title: 'Strength')),
    ('water', HabitEdit(target: 10, minimumTarget: 4)),
    ('learning', HabitEdit(enabled: false)),
  ]) {
    await app.tracking.editHabit(habitId: id, edit: edit, date: day2);
  }

  app.clock.current = day(3, 8);
  await app.tracking.activateMinimumDay(date: app.clock.today());
  await completeAll(app);
  await app.reflections.save(
    sessionId: arc.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Showed up'),
  );
  await app.achievements.reconcile();

  app.clock.current = day(93, 9);
  await app.lifecycle.reconcile();
  await app.achievements.reconcile(); // Summit
  return (await app.sessions.sessionById(arc.id))!;
}

/// Every stored row that belongs to [sessionId], for "nothing changed"
/// checks. Drift rows compare by value.
Future<List<Object>> snapshotOf(AppDatabase db, int sessionId) async => [
  ...await (db.select(
    db.winterArcSessions,
  )..where((r) => r.id.equals(sessionId))).get(),
  ...await (db.select(
    db.habits,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.habitRevisions,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.dailyHabitProgressEntries,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.dayModes,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.xpTransactions,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.achievementUnlocks,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
  ...await (db.select(
    db.dailyReflections,
  )..where((r) => r.sessionId.equals(sessionId))).get(),
];
