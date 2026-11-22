import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/features/arc_pause/pause_labels.dart';
import 'package:nextrep/features/arc_pause/paused_arc_card.dart';
import 'package:nextrep/features/summary/summary_screen.dart';

import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12E2 read-only gate (spec § 9.7 "Persistence: Reads only"; task:
/// "read-only views must not mutate the database"): with a paused Arc that
/// has progress, XP, unlocks, a reflection, a waiting goal revision and an
/// earlier closed pause, every row of every table is captured; then the
/// paused Today, the Resume sheet (Not yet, dismissed), Journey (path and
/// calendar), the Weekly Review, the Journal, Arc History, the reminder
/// settings and midnight are visited. After each step every table must be
/// exactly as captured. Then a completed Arc with pauses: its summary and
/// History card show the paused days and write nothing. All synthetic.

final day1 = LocalDate(2027, 3, 1);
LocalDate d(int n) => day1.addDays(n - 1);

Widget _app(TestApp app, String route) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(app.db),
    clockProvider.overrideWithValue(app.clock),
    ambientMotionProvider.overrideWithValue(false),
    reminderSchedulerProvider.overrideWithValue(app.scheduler),
    focusGuardPlatformProvider.overrideWithValue(
      const UnsupportedFocusGuardPlatform(),
    ),
    focusGuardSchedulerProvider.overrideWithValue(
      FakeFocusGuardBackgroundScheduler(),
    ),
    bootLocationProvider.overrideWith((ref) async => route),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('every table is identical after every paused, read-only step', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDays(app, d(1), d(4));
    final service = pauseServiceOf(app);
    at(app, d(4));
    await service.pause(sessionId: arc.id, frozenFrom: d(5));
    at(app, d(8));
    await service.resume(sessionId: arc.id, on: d(8));
    await liveDay(app, d(8)); // Day 5
    await app.reflections.save(
      sessionId: arc.id,
      date: d(8),
      draft: const ReflectionDraft(mood: Mood.good, win: 'Back'),
    );
    await app.tracking.editHabit(
      habitId: 'water',
      edit: const HabitEdit(target: 10, minimumTarget: 4),
      date: d(8),
    );
    await service.pause(sessionId: arc.id, frozenFrom: d(9));
    app.clock.current = DateTime(2027, 3, 12, 23, 59, 50);
    await app.lifecycle.reconcile();
    await app.achievements.reconcile();

    final all = await snapshotAll(app.db);
    for (final table in [
      'winter_arc_sessions',
      'arc_freezes',
      'habits',
      'habit_revisions',
      'daily_habit_progress_entries',
      'xp_transactions',
      'achievement_unlocks',
      'daily_reflections',
    ]) {
      expect(all[table], isNotEmpty, reason: 'populated: $table');
    }
    Future<void> unchanged(String step) async =>
        expect(await snapshotAll(app.db), all, reason: step);

    await tester.pumpWidget(_app(app, AppRoutes.today));
    await tester.pumpAndSettle();
    expect(find.byType(PausedArcCard), findsOneWidget);
    expect(find.text('Paused since Tue 9 Mar · 3 days'), findsOneWidget);
    expect(find.text('You stopped after Day 5 of 92.'), findsOneWidget);
    await unchanged('the paused Today');

    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.title), findsOneWidget);
    expect(find.text('Paused days in this Arc: 6 days.'), findsOneWidget);
    await unchanged('the Resume sheet');
    await tester.tap(find.text(ResumeCopy.notYet));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await unchanged('Not yet, dismissed');

    await tester.tap(
      find.descendant(
        of: find.byType(PausedArcCard),
        matching: find.text(PausedCopy.journey),
      ),
    );
    await tester.pumpAndSettle();
    await unchanged('Journey');
    await tapShown(tester, find.text('Calendar'));
    await unchanged('the Calendar');
    expect(
      find.textContaining('Paused 5–7 Mar', skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.textContaining('Paused since 9 Mar', skipOffstage: false),
      findsWidgets,
    );

    await tester.tap(_tab('Journal'));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.journalReadOnly), findsOneWidget);
    await unchanged('the Journal');

    await tester.tap(_tab('History'));
    await tester.pumpAndSettle();
    expect(find.text('Paused 6 days'), findsOneWidget);
    await unchanged('Arc History');

    await tester.tap(_tab('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await unchanged('reminder settings');

    // Midnight with everything open: one more paused date, no write.
    app.clock.current = DateTime(2027, 3, 13, 0, 0, 1);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Paused since Tue 9 Mar · 4 days'), findsOneWidget);
    await unchanged('midnight');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a completed Arc with pauses: its summary and History card show '
      'the paused days; viewing writes nothing', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDay(app, d(2));
    final service = pauseServiceOf(app);
    at(app, d(2));
    await service.pause(sessionId: arc.id, frozenFrom: d(3));
    at(app, d(12));
    await service.resume(sessionId: arc.id, on: d(12)); // 9 paused dates
    at(app, d(92).addDays(10)); // the day after the moved Day 92
    await app.lifecycle.reconcile();
    await app.achievements.reconcile();
    final done = await stored(app, arc.id);
    expect(done.status.name, 'completed');
    final all = await snapshotAll(app.db);

    await tester.pumpWidget(_app(app, AppRoutes.arc(arc.id)));
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('Paused 9 days'), findsOneWidget);
    expect(find.text('1 Mar – 9 Jun 2027'), findsOneWidget);
    expect(await snapshotAll(app.db), all);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(_app(app, AppRoutes.arcs));
    await tester.pumpAndSettle();
    expect(find.text('Paused 9 days'), findsOneWidget);
    expect(await snapshotAll(app.db), all);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
