import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_achievement_repository.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/features/journey/widgets/day_detail_sheet.dart';
import 'package:nextrep/features/review/weekly_review_screen.dart';

import '../support/arcs.dart';
import '../support/calendar_support.dart';
import '../support/fakes.dart';
import '../support/review_app.dart';
import '../support/review_db.dart';
import '../support/review_fakes.dart';
import '../support/review_seed.dart';

/// Phase 12C merge gate (spec K4, PHASE_12A § L2, roadmap "viewing a review
/// or the calendar writes nothing"): using the Calendar writes nothing.
///
/// A real in-memory Drift database with every table populated (sessions,
/// habits, revisions, progress, day modes, XP, unlocks, reflections,
/// freezes, reminder, Focus Guard and feedback preferences) is opened in
/// the real app at a Journey. The Journey's own entry-point work (close-out
/// check, achievement sync) runs and settles first: that is existing
/// behaviour, not the Calendar's. Only then is every row and column of
/// every table captured. After each Calendar operation (switching views,
/// scrolling weeks, opening and dismissing day details, a before-joining
/// note, a week review from a heading and Back, switching again) every
/// table must be exactly as captured, and no repository write may have
/// been made. Repeated for the active, a completed, an ended, a paused and
/// a late-joined Seasonal Arc. All data synthetic.

typedef _Repos = ({
  CountingProgressRepository progress,
  CountingSessionRepository sessions,
  CountingAchievementRepository achievements,
});

Future<void> _exercise(
  WidgetTester tester,
  AppDatabase db,
  FakeClock clock, {
  required String name,
  required String route,
  required List<int> days,
  required int reviewWeek,
  int? neutralDay,
  bool checkPopulated = false,
}) async {
  final repos = (
    progress: CountingProgressRepository(DriftProgressRepository(db, clock)),
    sessions: CountingSessionRepository(DriftWinterArcRepository(db)),
    achievements: CountingAchievementRepository(DriftAchievementRepository(db)),
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpWidget(
    reviewApp(
      db,
      clock,
      route,
      progress: repos.progress,
      sessions: repos.sessions,
      achievements: repos.achievements,
    ),
  );
  await tester.pumpAndSettle();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  // The Journey has loaded and its own entry-point work has finished.
  final captured = await snapshotAll(db);
  if (checkPopulated) {
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
  }
  final writesBefore = _writes(repos);
  final loadsBefore = repos.progress.loadArcCalls;
  final otherReadsBefore = repos.progress.otherReads;

  Future<void> unchanged(String what) async {
    final why = '$name: after $what';
    expect(await snapshotAll(db), captured, reason: why);
    expect(_writes(repos), writesBefore, reason: why);
  }

  await choose(tester, 'Calendar');
  await unchanged('switching Path → Calendar');
  expect(repos.progress.loadArcCalls, loadsBefore, reason: name);

  await reveal(tester, weekHeading(1));
  await reveal(tester, weekHeading(13));
  await reveal(tester, weekHeading(reviewWeek));
  await unchanged('scrolling between weeks');

  for (final day in days) {
    await reveal(tester, dayCell(day));
    await tester.tap(dayCell(day));
    await tester.pumpAndSettle();
    expect(find.byType(DayDetailSheet), findsOneWidget, reason: '$name $day');
    await unchanged('opening Day $day');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(DayDetailSheet), findsNothing);
    await unchanged('dismissing Day $day');
  }

  if (neutralDay != null) {
    await reveal(tester, dayCell(neutralDay));
    await tester.tap(dayCell(neutralDay));
    await tester.pumpAndSettle();
    expect(find.byType(NotJoinedDaySheet), findsOneWidget);
    await unchanged('the before-joining note');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }
  expect(repos.progress.loadArcCalls, loadsBefore, reason: name);

  await reveal(tester, weekHeading(reviewWeek));
  await tester.tap(weekHeading(reviewWeek));
  await tester.pumpAndSettle();
  expect(find.text('Week $reviewWeek review'), findsOneWidget, reason: name);
  await unchanged('opening the Week $reviewWeek review');
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
  expect(find.byType(WeeklyReviewScreen), findsNothing);
  await unchanged('Back to the Calendar');

  await choose(tester, 'Path');
  await unchanged('switching Calendar → Path');
  await choose(tester, 'Calendar');
  await unchanged('switching Path → Calendar again');
  // The review's own snapshot read (one loadArc) is all that was read.
  expect(repos.progress.otherReads, otherReadsBefore, reason: name);
  expect(repos.progress.loadArcCalls, loadsBefore + 1, reason: name);

  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

List<int> _writes(_Repos r) => [
  r.progress.writes,
  r.sessions.writes,
  r.achievements.writes,
];

void main() {
  void tallPhone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1080, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('active, completed and ended Arcs: every table identical after '
      'every Calendar operation', (tester) async {
    tallPhone(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 7, 1));
    final seed = await seedReviewData(TestApp(db, clock));

    await _exercise(
      tester,
      db,
      clock,
      name: 'active Arc',
      route: AppRoutes.journey,
      days: [1, 6, 7, 13],
      reviewWeek: 2,
      checkPopulated: true,
    );
    await _exercise(
      tester,
      db,
      clock,
      name: 'completed Arc',
      route: AppRoutes.arcJourney(seed.completedId),
      days: [1, 3, 92],
      reviewWeek: 13,
    );
    await _exercise(
      tester,
      db,
      clock,
      name: 'ended Arc',
      route: AppRoutes.arcJourney(seed.endedId),
      days: [1, 3],
      reviewWeek: 1,
    );
  });

  testWidgets('a paused Arc: every table identical after every Calendar '
      'operation', (tester) async {
    tallPhone(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 7, 1));
    await seedReviewData(TestApp(db, clock), pausedFrom: ReviewSeed.today);
    await _exercise(
      tester,
      db,
      clock,
      name: 'paused Arc',
      route: AppRoutes.journey,
      days: [2, 12],
      reviewWeek: 2,
      checkPopulated: true,
    );
  });

  testWidgets('a late-joined Seasonal Arc: the before-joining note and every '
      'other operation write nothing', (tester) async {
    tallPhone(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 1));
    final app = TestApp(db, clock);
    await joinSeason(app, DateTime(2026, 10, 18));
    for (var d = 18; d <= 21; d++) {
      at(app, LocalDate(2026, 10, d));
      if (d != 20) await completeAll(app);
      await app.achievements.sync();
    }
    at(app, LocalDate(2026, 10, 22), hour: 13);
    await _exercise(
      tester,
      db,
      clock,
      name: 'Seasonal Arc joined on Day 18',
      route: AppRoutes.journey,
      days: [18, 20, 22],
      reviewWeek: 3,
      neutralDay: 8,
    );
  });

  test('the Calendar code reads no repository or provider and has no write, '
      'reconcile, network, platform or storage access', () {
    final files = [
      File('lib/domain/journey/arc_calendar.dart'),
      File('lib/features/journey/calendar_labels.dart'),
      File('lib/features/journey/widgets/arc_calendar_view.dart'),
      File('lib/features/journey/widgets/calendar_day_cell.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final banned in [
        'Repository',
        'Provider',
        'ref.',
        'riverpod',
        'loadArc',
        'commitDay',
        'AchievementService',
        'achievementSync',
        'reconcile',
        'ArcLifecycleService',
        'Clock',
        'DateTime.now',
        'dart:io',
        'package:http',
        'SharedPreferences',
        'MethodChannel',
        'drift',
        'Database',
      ]) {
        expect(
          source,
          isNot(contains(banned)),
          reason: '${file.path}: $banned',
        );
      }
    }
  });
}
