import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/arc_refresh.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';

import '../support/fakes.dart';
import '../support/review_db.dart';
import '../support/review_fakes.dart';
import '../support/review_seed.dart';

/// Phase 12B merge gate (spec R5, PHASE_12A § D7, addendum F3-5 / F4-14):
/// opening and browsing Weekly Reviews writes nothing. A populated
/// database (every table with data: sessions, habits, revisions, progress,
/// day modes, XP, unlocks, reflections, freezes, reminder, Focus Guard and
/// feedback preferences) is captured row for row; then reviews are opened,
/// navigated, refreshed, carried over midnight, opened for a completed and
/// an ended Arc, and failed and retried. After every step every table must
/// be exactly as captured.
///
/// The router holds only the review routes and a stand-in Journey page, so
/// the check isolates the review's own reads from the Journey's existing
/// entry-point writes (close-out, achievement sync), which are not part of
/// it (spec K4 wording). The app's real routes are covered by
/// `weekly_review_screen_test.dart`. All data is synthetic.

void main() {
  testWidgets('every table is identical after every review operation', (
    tester,
  ) async {
    // Tall enough that the whole review is built without scrolling.
    tester.view
      ..physicalSize = const Size(1080, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    addTearDown(db.close);
    final app = TestApp(db, FakeClock(DateTime(2026, 7, 1)));
    final seed = await seedReviewData(app);
    final progress = CountingProgressRepository(
      DriftProgressRepository(db, app.clock),
    );
    final sessions = CountingSessionRepository(DriftWinterArcRepository(db));
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(app.clock),
        ambientMotionProvider.overrideWithValue(false),
        progressRepositoryProvider.overrideWithValue(progress),
        winterArcRepositoryProvider.overrideWithValue(sessions),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    final captured = await snapshotAll(db);
    // Every table that can hold data has some.
    for (final table in [
      'winter_arc_sessions',
      'habits',
      'habit_revisions',
      'daily_habit_progress_entries',
      'day_modes',
      'xp_transactions',
      'achievement_unlocks',
      'daily_reflections',
      'arc_freezes',
      'reminder_preferences',
      'focus_guard_preferences',
      'focus_guard_selected_apps',
      'feedback_preferences',
    ]) {
      expect(captured[table], isNotEmpty, reason: table);
    }

    var step = 0;
    Future<void> unchanged(String what) async {
      step++;
      expect(await snapshotAll(db), captured, reason: 'after $what');
      expect(progress.writes, 0, reason: 'after $what');
      expect(sessions.writes, 0, reason: 'after $what');
    }

    final router = GoRouter(
      initialLocation: '/journey',
      routes: [
        GoRoute(
          path: '/journey',
          builder: (context, state) => const _StandIn(),
          routes: [
            GoRoute(
              path: 'review',
              builder: (context, state) => WeeklyReviewScreen(
                requestedWeek: AppRoutes.reviewWeekOf(state.uri),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/arc/:sessionId',
          builder: (context, state) => const _StandIn(),
          routes: [
            GoRoute(
              path: 'review',
              builder: (context, state) => WeeklyReviewScreen(
                sessionId: int.parse(state.pathParameters['sessionId']!),
                requestedWeek: AppRoutes.reviewWeekOf(state.uri),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildWinterTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await unchanged('the stand-in Journey');

    // Open the active Arc's review of the current week.
    router.push(AppRoutes.activeReview(2));
    await tester.pumpAndSettle();
    expect(find.text('Week 2 review'), findsOneWidget);
    expect(find.textContaining('Today counts once it ends.'), findsWidgets);
    await unchanged('opening the review');

    // Another week, and back.
    await tester.tap(find.text('Week 1'));
    await tester.pumpAndSettle();
    expect(find.text('Week 1 review'), findsOneWidget);
    await unchanged('navigating to Week 1');
    await tester.tap(find.text('Week 2'));
    await tester.pumpAndSettle();
    expect(find.text('Week 2 review'), findsOneWidget);
    await unchanged('navigating back to Week 2');

    // Open every day's read-only detail.
    for (final label in ['Day 8,', 'Day 12,', 'Day 13,']) {
      await tester.tap(find.bySemanticsLabel(RegExp('^$label')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();
    }
    await unchanged('opening day details');

    // A refresh (the Arc refresh signal).
    final loadsBefore = progress.loadArcCalls;
    container.read(arcRefreshProvider.notifier).changed();
    await tester.pumpAndSettle();
    expect(progress.loadArcCalls, loadsBefore + 1);
    await unchanged('a refresh');

    // Midnight with the review open: still Week 2, now one more settled day.
    at(app, ReviewSeed.today.addDays(1), hour: 0);
    container.read(dayChangedProvider.notifier).changed();
    await tester.pumpAndSettle();
    expect(find.text('Week 2 review'), findsOneWidget);
    await unchanged('crossing midnight');

    // A completed Arc's review, and an ended Arc's.
    router.go(AppRoutes.arcReview(seed.completedId, 13));
    await tester.pumpAndSettle();
    expect(find.text('Week 13 review'), findsOneWidget);
    await unchanged('the completed Arc review');
    router.go(AppRoutes.arcReview(seed.endedId, 1));
    await tester.pumpAndSettle();
    expect(find.text('Week 1 review'), findsOneWidget);
    expect(find.textContaining('Ended early'), findsOneWidget);
    await unchanged('the ended Arc review');

    // A failed read, then Try again.
    progress.failNextLoads = 1;
    container.read(arcRefreshProvider.notifier).changed();
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await unchanged('a failed read');
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Week 1 review'), findsOneWidget);
    await unchanged('the retry');

    expect(step, 11);
    expect(progress.otherReads, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

class _StandIn extends StatelessWidget {
  const _StandIn();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Stand-in Journey')));
}
