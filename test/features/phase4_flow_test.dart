import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/journal/journal_screen.dart';
import 'package:nextrep/features/journal/widgets/reflection_editor.dart';
import 'package:nextrep/features/new_arc/new_arc_screen.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FakeReminderScheduler? scheduler,
  Stream<String?>? taps,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    if (scheduler != null)
      reminderSchedulerProvider.overrideWithValue(scheduler),
    if (taps != null) reminderTapsProvider.overrideWithValue(taps),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Finder get _navBar => find.byType(NavigationBar);

Future<void> _openTab(WidgetTester tester, String label) async {
  await clearCelebrations(tester);
  await tester.tap(find.descendant(of: _navBar, matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// Scrolls the first scrollable until [finder] is visible, then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A database holding Arc 1 (see [runFirstArc]), completed; the clock is on
/// 1 Oct 2026.
Future<TestApp> _completedArc() async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
  await runFirstArc(app);
  return app;
}

/// Arc 1 completed and Arc 2 active since 2 Oct (fresh starter habits).
Future<TestApp> _secondArcRunning() async {
  final app = await _completedArc();
  await app.winterArc.startNewArc(NewArcBaseline.fresh);
  app.clock.current = DateTime(2026, 10, 2, 20);
  await app.winterArc.startWinterArc();
  return app;
}

void main() {
  testWidgets('after an arc: Start New Arc → Reuse Last Setup → Setup → '
      'Today, without onboarding', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _completedArc();
    addTearDown(seeded.db.close);

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Arc History'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start New Arc'), findsOneWidget);
    expect(find.text('View Journal'), findsOneWidget);

    await _tapVisible(tester, find.text('Start New Arc'));
    expect(find.byType(NewArcScreen), findsOneWidget);
    // The reuse choice previews the final habits of Arc 1.
    expect(find.textContaining('Strength · 30 min'), findsOneWidget);
    expect(find.textContaining('Water Intake · 10 glasses'), findsOneWidget);
    expect(find.textContaining('Learning'), findsNothing); // turned off

    await tester.tap(find.text('Reuse last setup'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('10 glasses'), findsOneWidget);
    expect(find.text('3 habits selected'), findsOneWidget);
    expect(find.textContaining('days to a better you'), findsNothing);

    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('0 XP'), findsOneWidget);
    expect(find.text('0 of 3 done'), findsOneWidget);
    for (final tab in ['Today', 'Journey', 'Journal', 'History']) {
      expect(
        find.descendant(of: _navBar, matching: find.text(tab)),
        findsOneWidget,
      );
    }
    final arcs = await seeded.sessions.listSessions();
    expect(arcs, hasLength(2));
    expect(await seeded.progress.totalXp(arcs.last.id), 135);
    await _shutDown(tester);
  });

  testWidgets('Start Fresh uses the starter habits', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _completedArc();
    addTearDown(seeded.db.close);
    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Start New Arc'));
    await tester.tap(find.text('Start fresh'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Strength'), findsNothing);
    expect(find.text('4 habits selected'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Journal: write, validate, save, edit; past entries newest '
      'first', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    final arc2 = (await seeded.winterArc.currentSession())!;
    // Two earlier reflections of Arc 2 (Day 1 and Day 2).
    for (final (day, win) in [(2, 'First day back'), (3, 'Kept it up')]) {
      seeded.clock.current = DateTime(2026, 10, day, 21);
      await seeded.reflections.save(
        sessionId: arc2.id,
        date: seeded.clock.today(),
        draft: ReflectionDraft(win: win),
      );
    }
    seeded.clock.current = DateTime(2026, 10, 4, 21); // Day 3

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Journal');
    expect(find.byType(JournalScreen), findsOneWidget);
    expect(find.text('TODAY · DAY 3'), findsOneWidget);
    expect(find.byType(ReflectionEditor), findsOneWidget);

    // Past entries, newest first; days without one aren't invented.
    await tester.scrollUntilVisible(
      find.text('First day back'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final day2 = tester.getTopLeft(find.text('Kept it up')).dy;
    final day1 = tester.getTopLeft(find.text('First day back')).dy;
    expect(day2, lessThan(day1));
    expect(find.text('Day 2'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);

    // Saving nothing is explained, not stored.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Reflection'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pick a mood or write a few words before saving.'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Mood: Good'));
    await tester.enterText(
      find.widgetWithText(TextField, 'One win today'),
      '  Finished my workout even though I was tired.  ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'One thing to improve'),
      'Sleep\nearlier',
    );
    // Answers are one line: a pasted line break becomes a space.
    expect(find.text('Sleep earlier'), findsOneWidget);
    await tester.tap(find.text('Save Reflection'));
    await tester.pumpAndSettle();
    expect(find.text('Reflection saved'), findsOneWidget);
    expect(
      find.text('Finished my workout even though I was tired.'),
      findsOneWidget,
    );
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(ReflectionEditor), findsNothing);
    // Arc 2 had two reflections; this third one isn't the seventh yet, but
    // Looking Inward was earned by the first.
    final stored = await seeded.reflectionStore.reflectionOn(
      arc2.id,
      seeded.clock.today(),
    );
    expect(stored!.mood, Mood.good);
    expect(stored.win, 'Finished my workout even though I was tired.');

    // Editing updates the same day.
    await clearCelebrations(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Mood: Excellent'));
    await tester.tap(find.text('Update Reflection'));
    await tester.pumpAndSettle();
    expect(find.text('Reflection updated'), findsOneWidget);
    expect(await seeded.reflectionStore.countFor(arc2.id), 3);
    await _shutDown(tester);
  });

  testWidgets('the first reflection unlocks Looking Inward once', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Journal');
    await tester.tap(find.bySemanticsLabel('Mood: Okay'));
    await tester.tap(find.text('Save Reflection'));
    await tester.pumpAndSettle();
    expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
    expect(find.text('Looking Inward'), findsOneWidget);
    await clearCelebrations(tester);
    expect(
      await seeded.db.select(seeded.db.achievementUnlocks).get(),
      hasLength(6 + 1),
    );
    await _shutDown(tester);
  });

  testWidgets('History: newest first; a past arc opens read-only, scoped to '
      'that arc', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    final arc1 = (await seeded.sessions.latestCompletedSession())!;

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'History');
    expect(find.byType(ArcHistoryScreen), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    final active = tester.getTopLeft(find.text('ACTIVE')).dy;
    final done = tester.getTopLeft(find.text('COMPLETED')).dy;
    expect(active, lessThan(done));
    expect(find.text('1 Jul – 30 Sep 2026'), findsOneWidget);
    expect(find.text('135 XP'), findsOneWidget);
    expect(find.text('2%'), findsOneWidget); // consistency
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Winter Arc, 1 Jul – 30 Sep 2026, completed'),
      ),
      findsOneWidget,
    );

    // Arc 1's overview: its own numbers, no New Arc while Arc 2 runs.
    await tester.tap(find.text('1 Jul – 30 Sep 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Total XP: 135'), findsOneWidget);
    expect(find.bySemanticsLabel('Achievements: 6 / 15'), findsOneWidget);
    expect(find.text('Start New Arc'), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);

    // Its Journal: read-only, its own reflection only.
    await _tapVisible(tester, find.text('View Journal'));
    expect(find.text('Winter Arc · 1 Jul – 30 Sep 2026'), findsOneWidget);
    expect(find.text('Showed up'), findsOneWidget);
    expect(find.text('Day 3'), findsOneWidget);
    expect(find.byType(ReflectionEditor), findsNothing);
    expect(find.text('Save Reflection'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Its Journey: Day 1 Perfect, the arc complete.
    await _tapVisible(tester, find.text('View Journey'));
    expect(find.text('Winter Arc · 1 Jul – 30 Sep 2026'), findsOneWidget);
    expect(find.text('Winter Arc complete'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r', today$')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Its achievements.
    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Achievements'),
    );
    expect(find.text('6 of 15 unlocked'), findsOneWidget);
    expect(seeded.clock.today().toIsoString(), '2026-10-02');
    // Nothing about Arc 1 changed by browsing it.
    final before = await snapshotOf(seeded.db, arc1.id);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await snapshotOf(seeded.db, arc1.id), before);
    await _shutDown(tester);
  });

  testWidgets('large text keeps the Journal, History and New Arc usable', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'Journal');
    expect(tester.takeException(), isNull);
    // Every mood label stays whole.
    for (final mood in ['Rough', 'Okay', 'Good', 'Excellent']) {
      expect(find.text(mood), findsOneWidget);
    }
    await tester.tap(find.bySemanticsLabel('Mood: Excellent'));
    await _tapVisible(tester, find.text('Save Reflection'));
    expect(find.text('Excellent'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _openTab(tester, 'History');
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('COMPLETED'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('135 XP'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shutDown(tester);

    // A completed arc's New Arc choices.
    final done = await _completedArc();
    addTearDown(done.db.close);
    await tester.pumpWidget(_app(done.db, done.clock));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Start New Arc'));
    expect(find.byType(NewArcScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shutDown(tester);
  });

  testWidgets('reminder settings: off by default; on schedules; a denial '
      'keeps it off', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    final scheduler = FakeReminderScheduler();
    await tester.pumpWidget(
      _app(seeded.db, seeded.clock, scheduler: scheduler),
    );
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettingsScreen), findsOneWidget);
    final switches = find.byType(Switch);
    expect(tester.widgetList<Switch>(switches).map((s) => s.value), [
      false,
      false,
    ]);
    expect(scheduler.pending, isEmpty);

    await tester.tap(find.text('Evening reflection'));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(tester.widgetList<Switch>(switches).last.value, isTrue);
    expect(scheduler.pending.map((r) => r.kind).toSet(), {
      ReminderKind.reflection,
    });
    // The time row and the switch are separate accessible controls.
    final time = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^Evening reflection time, ')),
    );
    expect(time.label, isNot(contains('How did today go')));
    expect(
      tester.getSemantics(find.byType(Switch).last).label,
      isNot(contains('time')),
    );

    // The user denies the next prompt: the switch stays off.
    scheduler
      ..granted = false
      ..grant = false;
    await tester.tap(find.text('Daily reminder'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Notifications weren't allowed"),
      findsOneWidget,
    );
    expect(tester.widgetList<Switch>(switches).first.value, isFalse);
    expect(scheduler.pending.map((r) => r.kind).toSet(), {
      ReminderKind.reflection,
    });
    expect(
      find.textContaining('turned off for NextRep in system settings'),
      findsOneWidget,
    );
    await _shutDown(tester);
  });

  testWidgets('a tapped reminder opens the Journal, or the summary once '
      'the arc is over', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    final taps = StreamController<String?>.broadcast();
    addTearDown(taps.close);
    await tester.pumpWidget(_app(seeded.db, seeded.clock, taps: taps.stream));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);

    taps.add(ReminderKind.reflection.payload);
    await tester.pumpAndSettle();
    expect(find.byType(JournalScreen), findsOneWidget);

    taps.add(ReminderKind.daily.payload);
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);

    // Arc 2 (from 2 Oct) is over on 2 Jan: a stale reminder lands on its
    // summary, never on a writable Today.
    seeded.clock.current = DateTime(2027, 1, 2, 8);
    taps.add(ReminderKind.daily.payload);
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
    expect(_navBar, findsNothing);
    await _shutDown(tester);
  });
}
