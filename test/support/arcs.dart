import 'package:drift/drift.dart' show DataClass;
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
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

/// Every row of every app table, as JSON, for "exactly the same data"
/// checks across databases. XP row ids are dropped: they are internal
/// insertion counters, not data (a backup doesn't carry them).
///
/// With [renumberSessions], arc ids are replaced by their rank (1 = oldest),
/// for comparing data restored over an existing database, where restored
/// arcs get fresh ids.
Future<Map<String, List<String>>> dumpOf(
  AppDatabase db, {
  bool renumberSessions = false,
}) async {
  final ids = [
    for (final s in await db.select(db.winterArcSessions).get()) s.id,
  ]..sort();
  final rank = {for (final (i, id) in ids.indexed) id: i + 1};
  Future<List<String>> rows<T extends DataClass>(
    Future<List<T>> query, {
    bool dropId = false,
    String? sessionKey = 'sessionId',
  }) async => [
    for (final row in await query)
      () {
        final json = row.toJson()..removeWhere((k, _) => dropId && k == 'id');
        if (renumberSessions && sessionKey != null) {
          json[sessionKey] = rank[json[sessionKey]];
        }
        return json.toString();
      }(),
  ]..sort();
  return {
    'sessions': await rows(
      db.select(db.winterArcSessions).get(),
      sessionKey: 'id',
    ),
    'habits': await rows(db.select(db.habits).get()),
    'revisions': await rows(db.select(db.habitRevisions).get()),
    'progress': await rows(db.select(db.dailyHabitProgressEntries).get()),
    'modes': await rows(db.select(db.dayModes).get()),
    'xp': await rows(db.select(db.xpTransactions).get(), dropId: true),
    'achievements': await rows(db.select(db.achievementUnlocks).get()),
    'reflections': await rows(db.select(db.dailyReflections).get()),
    'reminders': await rows(
      db.select(db.reminderPrefs).get(),
      sessionKey: null,
    ),
  };
}

/// Sets up and joins this year's Seasonal Winter Arc on [joinOn] (09:00),
/// through the real services, with the starter habits. Leaves the clock on
/// [joinOn] and returns the active arc.
Future<WinterArcSession> joinSeason(TestApp app, DateTime joinOn) async {
  app.clock.current = DateTime(joinOn.year, joinOn.month, joinOn.day, 9);
  await app.winterArc.startNewArc(
    NewArcBaseline.fresh,
    kind: ArcKind.seasonalWinter,
  );
  return app.winterArc.startWinterArc();
}
