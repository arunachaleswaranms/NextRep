import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/features/arc_pause/pause_labels.dart';
import 'package:nextrep/features/arc_pause/paused_arc_card.dart';
import 'package:nextrep/features/focus_guard/focus_guard_settings_screen.dart';
import 'package:nextrep/features/habits/habits_screen.dart';
import 'package:nextrep/features/today/widgets/habit_progress_tile.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12E2 through the whole app (real router, screens, services and an
/// in-memory Drift database; injected clock; platform services faked):
/// the Pause sheet from Today and from Habits, Not now / Back / dismiss,
/// the scheduled banner and Cancel pause, midnight with the app open, the
/// paused Today, the Resume sheet, failures, refusals, reminders and Focus
/// Guard. All data synthetic.

final day1 = LocalDate(2027, 3, 1); // Monday
LocalDate d(int n) => day1.addDays(n - 1);

Widget _app(
  TestApp app, {
  FocusGuardPlatform? focusGuard,
  FakeFocusGuardBackgroundScheduler? background,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(app.db),
    clockProvider.overrideWithValue(app.clock),
    ambientMotionProvider.overrideWithValue(false),
    reminderSchedulerProvider.overrideWithValue(app.scheduler),
    focusGuardPlatformProvider.overrideWithValue(
      focusGuard ?? const UnsupportedFocusGuardPlatform(),
    ),
    focusGuardSchedulerProvider.overrideWithValue(
      background ?? FakeFocusGuardBackgroundScheduler(),
    ),
    bootLocationProvider.overrideWith((ref) async => AppRoutes.today),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> _tall(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Opens "Pause Arc" from Today's overflow menu.
Future<void> _openPauseFromToday(WidgetTester tester) async {
  await clearCelebrations(tester);
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(PauseCopy.menuItem));
  await tester.pumpAndSettle();
  expect(find.text(PauseCopy.sheetTitle), findsOneWidget);
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// Scrolls the Habits list (lazy) to its end and proves the end is built,
/// so a "Pause Arc is absent" check can't pass merely because the last
/// row was never built.
Future<void> _scrolledToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -4000));
  await tester.pumpAndSettle();
  expect(find.text('Meditation'), findsOneWidget, reason: 'last habit');
}

Future<void> _snackGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pause, cancel, pause from Habits, midnight, Resume: the whole '
      'flow, with every non-committing step writing nothing', (tester) async {
    await _tall(tester);
    final app = TestApp(
      memoryDatabase(),
      FakeClock(DateTime(2027, 3, 1, 9)),
      scheduler: FakeReminderScheduler(granted: true),
    );
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(25), hour: 6);
    await app.reminders.update(
      (p) => p.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
        hydrationEnabled: true,
      ),
    );
    await completeHabit(app, 'water');
    app.clock.current = DateTime(2027, 3, 25, 23, 50);
    await app.achievements.reconcile();

    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    expect(find.text('Day 25 of 92'), findsOneWidget);
    final start = await snapshotAll(app.db);
    expect(
      app.scheduler.pending.any(
        (r) => !LocalDate.fromDateTime(r.at).isBefore(d(26)),
      ),
      isTrue,
      reason: 'reminders planned for the coming days before the pause',
    );

    // The sheet, as approved (spec § 9.6).
    await _openPauseFromToday(tester);
    expect(
      find.text(
        'From tomorrow, Fri 26 Mar, your Arc stops counting days until you '
        'resume.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Today (Day 25) still counts. You can finish it, or use a Minimum '
        'Day.',
      ),
      findsOneWidget,
    );
    expect(find.text(PauseCopy.neverMissed), findsOneWidget);
    expect(
      find.text(
        'You continue on Day 26 when you resume; your last day moves later.',
      ),
      findsOneWidget,
    );
    expect(find.text(PauseCopy.remindersPause), findsOneWidget);
    expect(find.text(PauseCopy.focusGuardLink), findsNothing, reason: 'n/a');

    // Not now, then dismissing, then Back: nothing is written.
    await tester.tap(find.text(PauseCopy.notNow));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.sheetTitle), findsNothing);
    expect(await snapshotAll(app.db), start);
    await _openPauseFromToday(tester);
    await tester.tapAt(const Offset(20, 20)); // the barrier
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.sheetTitle), findsNothing);
    expect(await snapshotAll(app.db), start);
    await _openPauseFromToday(tester);
    await tester.binding.handlePopRoute(); // system Back
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.sheetTitle), findsNothing);
    expect(await snapshotAll(app.db), start);

    // Pause from tomorrow.
    await _openPauseFromToday(tester);
    await tester.tap(find.text(PauseCopy.pauseAction));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.sheetTitle), findsNothing);
    expect(find.text(PauseCopy.bannerTomorrow), findsOneWidget);
    expect(find.text(PauseCopy.cancelAction), findsOneWidget);
    expect(find.byTooltip('More options'), findsNothing, reason: 'F4');
    var session = await stored(app, arc.id);
    expect(session.freezes.single.frozenFrom, d(26));
    // Reminders re-planned straight away: nothing for a paused date (at
    // 23:50 nothing of today is left either).
    expect(
      app.scheduler.pending.every(
        (r) => LocalDate.fromDateTime(r.at).isBefore(d(26)),
      ),
      isTrue,
    );
    // Today is still a normal, trackable day.
    expect(find.byType(HabitProgressTile), findsWidgets);
    expect(find.text('Having a rough day?'), findsOneWidget);

    // Cancel pause: back to exactly the starting rows.
    await tester.tap(find.text(PauseCopy.cancelAction));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.cancelled), findsOneWidget);
    expect(find.text(PauseCopy.bannerTomorrow), findsNothing);
    expect(await snapshotAll(app.db), start);
    expect(
      app.scheduler.pending.any(
        (r) => !LocalDate.fromDateTime(r.at).isBefore(d(26)),
      ),
      isTrue,
      reason: 're-planned after Cancel',
    );
    await _snackGone(tester);

    // From the Habits screen.
    await tapShown(tester, find.text('Edit habits'));
    expect(find.byType(HabitsScreen), findsOneWidget);
    await tapShown(tester, find.text(PauseCopy.menuItem));
    await tester.tap(find.text(PauseCopy.pauseAction));
    await tester.pumpAndSettle();
    await showIn(tester, find.textContaining('apply when you resume'));
    expect(find.textContaining('apply when you resume'), findsOneWidget);
    await _scrolledToEnd(tester);
    expect(find.text(PauseCopy.menuItem), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.bannerTomorrow), findsOneWidget);
    final scheduled = await snapshotAll(app.db);

    // Midnight with the app open: paused, with no write.
    app.clock.current = DateTime(2027, 3, 26, 0, 0, 1);
    await tester.pump(const Duration(minutes: 11));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    expect(find.text('Paused since today, Fri 26 Mar'), findsOneWidget);
    expect(find.text('You stopped after Day 25 of 92.'), findsOneWidget);
    expect(
      find.text('When you resume, that day becomes Day 26.'),
      findsOneWidget,
    );
    expect(find.text(PausedCopy.noCount), findsOneWidget);
    expect(find.text(PausedCopy.resumeAction), findsOneWidget);
    expect(find.byType(HabitProgressTile), findsNothing);
    expect(find.text('Having a rough day?'), findsNothing);
    expect(find.text('Edit habits'), findsNothing);
    expect(await snapshotAll(app.db), scheduled, reason: 'no midnight write');
    expect(app.scheduler.pending, isEmpty, reason: 'Z8');

    // Six days later.
    app.clock.current = DateTime(2027, 4, 1, 9);
    await tester.pump(const Duration(hours: 24));
    await tester.pumpAndSettle();
    expect(find.text('Paused since Fri 26 Mar · 6 days'), findsOneWidget);

    // The Resume sheet; Not yet keeps it paused.
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.title), findsOneWidget);
    expect(
      find.text('Today, Thu 1 Apr, becomes Day 26 of 92.'),
      findsOneWidget,
    );
    expect(find.text('Your new last day is Sun 6 Jun.'), findsOneWidget);
    expect(find.text('You paused for 6 days.'), findsOneWidget);
    await tester.tap(find.text(ResumeCopy.notYet));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    expect(await snapshotAll(app.db), scheduled);

    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.title), findsNothing);
    expect(find.text('Day 26 of 92'), findsOneWidget);
    expect(find.byType(HabitProgressTile), findsWidgets);
    session = await stored(app, arc.id);
    expect(session.freezes.single.resumedOn, LocalDate(2027, 4, 1));
    expect(session.endDate, LocalDate(2027, 6, 6));
    final daily = app.scheduler.pending
        .where((r) => r.kind == ReminderKind.daily)
        .toList();
    expect(daily, isNotEmpty, reason: 're-planned after Resume');
    // 09:00: today's 08:00 reminder has passed; tomorrow is Day 27, and
    // tonight's reflection is about Day 26.
    expect(daily.map((r) => r.title), contains('Winter Arc · Day 27'));
    expect(
      app.scheduler.pending
          .where((r) => r.kind == ReminderKind.reflection)
          .map((r) => r.body),
      contains('Take 20 seconds to reflect on Day 26.'),
    );

    // Arc History shows the paused days.
    await tester.tap(_tab('History'));
    await tester.pumpAndSettle();
    expect(find.text('Paused 6 days'), findsOneWidget);
  });

  testWidgets('not offered for a Seasonal Arc, nor on Day 92', (tester) async {
    await _tall(tester);
    for (final seasonal in [true, false]) {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
      addTearDown(app.db.close);
      if (seasonal) {
        await joinSeason(app, DateTime(2027, 10, 5));
      } else {
        await startRolling(app, day1);
        at(app, d(92));
      }
      await tester.pumpWidget(_app(app));
      await tester.pumpAndSettle();
      expect(find.byTooltip('More options'), findsNothing);
      await tapShown(tester, find.text('Edit habits'));
      await _scrolledToEnd(tester);
      expect(find.text(PauseCopy.menuItem), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }
  });

  testWidgets('the phone date is behind the history: the sheet names the '
      'dates and offers no Pause; nothing is written', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    await startRolling(app, day1);
    await liveDay(app, d(18));
    at(app, d(17));
    final before = await snapshotAll(app.db);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openPauseFromToday(tester);
    expect(
      find.text(
        "Your phone's date (17 Mar) is earlier than your latest logged day "
        '(18 Mar). You can pause from 18 Mar. Nothing was changed.',
      ),
      findsOneWidget,
    );
    expect(find.text(PauseCopy.pauseAction), findsNothing);
    await tester.tap(find.text(PauseCopy.notNow));
    await tester.pumpAndSettle();
    expect(await snapshotAll(app.db), before);
  });

  testWidgets('a failed pause says nothing changed and offers Retry', (
    tester,
  ) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(5));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    final before = await snapshotAll(app.db);
    await app.db.customStatement(
      'CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON arc_freezes '
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await _openPauseFromToday(tester);
    await tester.tap(find.text(PauseCopy.pauseAction));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.pauseFailed), findsOneWidget);
    expect(find.text(PauseCopy.retry), findsOneWidget);
    expect(await snapshotAll(app.db), before);
    await app.db.customStatement('DROP TRIGGER injected_failure');
    await tester.tap(find.text(PauseCopy.retry));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.bannerTomorrow), findsOneWidget);
    expect((await stored(app, arc.id)).freezes, hasLength(1));
  });

  testWidgets('a failed resume: "Couldn\'t resume. Your Arc is still '
      'paused." Never shown as resumed before it is stored', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(5));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(6));
    at(app, d(9));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    final before = await snapshotAll(app.db);
    await app.db.customStatement(
      'CREATE TEMP TRIGGER injected_failure BEFORE UPDATE ON '
      "winter_arc_sessions BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.failed), findsOneWidget);
    expect(find.text(PauseCopy.retry), findsOneWidget);
    expect(await snapshotAll(app.db), before);
    await tester.tap(find.text(ResumeCopy.notYet));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    await app.db.customStatement('DROP TRIGGER injected_failure');
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text('Day 6 of 92'), findsOneWidget);
  });

  testWidgets('midnight while the Pause sheet is open: it re-reads and shows '
      'the new dates; the stored start is the one shown', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    app.clock.current = DateTime(2027, 3, 25, 23, 59, 30);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openPauseFromToday(tester);
    expect(find.textContaining('Fri 26 Mar'), findsOneWidget);
    app.clock.current = DateTime(2027, 3, 26, 0, 0, 2);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.dateChanged), findsOneWidget);
    expect(find.textContaining('Sat 27 Mar'), findsOneWidget);
    expect(find.textContaining('Today (Day 26)'), findsOneWidget);
    await tester.tap(find.text(PauseCopy.pauseAction));
    await tester.pumpAndSettle();
    expect((await stored(app, arc.id)).freezes.single.frozenFrom, d(27));
  });

  testWidgets('midnight while the Resume sheet is open: it re-reads; the '
      'stored resume date is the one shown', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(5));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(6));
    app.clock.current = DateTime(2027, 3, 9, 23, 59, 30);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text('Today, Tue 9 Mar, becomes Day 6 of 92.'), findsOneWidget);
    app.clock.current = DateTime(2027, 3, 10, 0, 0, 2);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.dateChanged), findsOneWidget);
    expect(
      find.text('Today, Wed 10 Mar, becomes Day 6 of 92.'),
      findsOneWidget,
    );
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    final s = await stored(app, arc.id);
    expect(s.freezes.single.resumedOn, d(10));
  });

  testWidgets('Focus Guard: the sheet links to its settings; the paused Today '
      'keeps its card; Freeze and Resume never touch it', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(5));
    final background = FakeFocusGuardBackgroundScheduler();
    final platform = FakeFocusGuardPlatform(access: UsageAccess.granted);
    await tester.pumpWidget(
      _app(app, focusGuard: platform, background: background),
    );
    await tester.pumpAndSettle();
    final focusRows = (await snapshotAll(app.db))['focus_guard_preferences'];

    await _openPauseFromToday(tester);
    expect(
      find.text('${PauseCopy.remindersPause} ${PauseCopy.focusGuardOwn}'),
      findsOneWidget,
    );
    await tester.tap(find.text(PauseCopy.focusGuardLink));
    await tester.pumpAndSettle();
    expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
    expect((await stored(app, arc.id)).freezes, isEmpty, reason: 'no write');
    await tester.pageBack();
    await tester.pumpAndSettle();

    final calls = (background.scheduleCalls, background.cancelCalls);
    final queries = platform.queries.length;
    await _openPauseFromToday(tester);
    await tester.tap(find.text(PauseCopy.pauseAction));
    await tester.pumpAndSettle();
    expect((background.scheduleCalls, background.cancelCalls), calls);
    expect((await snapshotAll(app.db))['focus_guard_preferences'], focusRows);

    at(app, d(8));
    await tester.pump(const Duration(days: 3));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    expect(find.text('Focus Guard'), findsWidgets, reason: 'card kept');
    final resumeCalls = (background.scheduleCalls, background.cancelCalls);
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    expect((background.scheduleCalls, background.cancelCalls), resumeCalls);
    expect((await snapshotAll(app.db))['focus_guard_preferences'], focusRows);
    expect(platform.queries.length, greaterThanOrEqualTo(queries));
  });

  testWidgets('a date moved back into a closed pause: paused, "Continues "'
      'on", no Resume', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(10));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(11));
    at(app, d(15));
    await pauseServiceOf(app).resume(sessionId: arc.id, on: d(15));
    at(app, d(13));
    final before = await snapshotAll(app.db);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    expect(find.text('Paused Thu 11 Mar – Sun 14 Mar'), findsOneWidget);
    expect(find.text('Continues on Mon 15 Mar.'), findsOneWidget);
    expect(find.text(PausedCopy.resumeAction), findsNothing);
    expect(await snapshotAll(app.db), before);
  });

  testWidgets('paused: Habits and Journal say "paused", read-only', (
    tester,
  ) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDay(app, d(3));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(4));
    at(app, d(6));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await tester.tap(_tab('Journal'));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.journalReadOnly), findsOneWidget);
    expect(find.textContaining('complete'), findsNothing);
    await tester.tap(_tab('Today'));
    await tester.pumpAndSettle();
    // Habits is reachable by its route only while paused: read-only, and
    // no Pause entry.
    GoRouter.of(tester.element(find.byType(PausedArcCard)))
        .push(AppRoutes.habits);
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.habitsReadOnly), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
    for (final element in find.byType(Switch).evaluate()) {
      expect((element.widget as Switch).onChanged, isNull, reason: 'locked');
    }
    await _scrolledToEnd(tester);
    expect(find.text(PauseCopy.menuItem), findsNothing);
    final before = await snapshotAll(app.db);
    await tester.tap(find.text('Meditation'));
    await tester.pumpAndSettle();
    expect(find.text('Edit habit'), findsNothing, reason: 'no editor');
    expect(await snapshotAll(app.db), before);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PausedArcCard),
        matching: find.text(PausedCopy.journey),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paused after Day 3 of 92'), findsWidgets);
  });

  testWidgets('the date moves back before the pause while the Resume sheet '
      'is open: one clear message, nothing written', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 3, 1)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    at(app, d(5));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(6));
    at(app, d(9));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PausedCopy.resumeAction));
    await tester.pumpAndSettle();
    final before = await snapshotAll(app.db);
    at(app, d(5)); // before the first paused date
    await tester.tap(find.text(ResumeCopy.resumeAction));
    await tester.pumpAndSettle();
    expect(find.text(ResumeCopy.notPaused), findsOneWidget);
    expect(find.text(ResumeCopy.failed), findsNothing);
    expect(await snapshotAll(app.db), before);
  });
}
