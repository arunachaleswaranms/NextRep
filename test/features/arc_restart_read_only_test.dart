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
import 'package:nextrep/features/achievements/achievements_screen.dart';
import 'package:nextrep/features/journal/journal_screen.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';

import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12F read-only gate (spec § 3 invariant 4: "COMPLETED and ENDED
/// are read-only history. Nothing writes to them except their own
/// deletion"; § 6.5): after a restart, the old arc's Summary, Journey
/// (path and calendar), Journal, Achievements, every Weekly Review and the
/// Arc History card are opened, on its closing date and long after its
/// planned end. Every row of the old arc must stay exactly as it was, and
/// no Summit, XP or unlock may appear for it. All data synthetic.

final day1 = LocalDate(2026, 10, 7);
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

/// Every row of arc [id] in every table.
Future<DbSnapshot> _rowsOf(TestApp app, int id) async => {
  for (final MapEntry(key: table, value: rows) in (await snapshotAll(
    app.db,
  )).entries)
    table: [
      for (final r in rows)
        if (r['session_id'] == id ||
            (table == 'winter_arc_sessions' && r['id'] == id))
          r,
    ],
};

void main() {
  testWidgets('the ended arc is identical after every history screen, on '
      'and long after its last day', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDays(app, d(1), d(16));
    at(app, d(16));
    await app.reflections.save(
      sessionId: arc.id,
      date: d(16),
      draft: const ReflectionDraft(mood: Mood.good, win: 'Kept'),
    );
    await app.tracking.editHabit(
      habitId: 'water',
      edit: const HabitEdit(target: 12, minimumTarget: 4),
      date: d(16),
    );
    at(app, d(17));
    await restartNow(app, arc.id);
    final reference = await _rowsOf(app, arc.id);
    expect(reference['achievement_unlocks'], isNotEmpty);

    for (final today in [d(17), d(30), d(95), d(400)]) {
      at(app, today);
      for (final route in [
        AppRoutes.arc(arc.id),
        AppRoutes.arcJourney(arc.id),
        AppRoutes.arcJournal(arc.id),
        AppRoutes.arcAchievements(arc.id),
        for (var week = 1; week <= 13; week++)
          AppRoutes.arcReview(arc.id, week),
        AppRoutes.history,
      ]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(_app(app, route));
        await tester.pumpAndSettle();
        await clearCelebrations(tester);
        expect(tester.takeException(), isNull, reason: route);
        expect(
          await _rowsOf(app, arc.id),
          reference,
          reason: '$route on $today',
        );
      }
      // The Summary reads "ended early", never complete; no Summit.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(_app(app, AppRoutes.arc(arc.id)));
      await tester.pumpAndSettle();
      expect(find.byType(SummaryScreen), findsOneWidget);
      expect(find.text('WINTER ARC ENDED EARLY'), findsOneWidget);
      expect(find.text('Ended early · Day 16 of 92'), findsOneWidget);
      expect(find.textContaining('COMPLETE'), findsNothing);
    }
    // Sanity: each screen was really shown at least once.
    for (final (route, type) in [
      (AppRoutes.arcJourney(arc.id), JourneyScreen),
      (AppRoutes.arcJournal(arc.id), JournalScreen),
      (AppRoutes.arcAchievements(arc.id), AchievementsScreen),
      (AppRoutes.arcReview(arc.id, 3), WeeklyReviewScreen),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(_app(app, route));
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget, reason: route);
    }
    expect(await _rowsOf(app, arc.id), reference);
  });
}
