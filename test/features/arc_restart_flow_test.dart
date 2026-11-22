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
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/arc_pause/pause_labels.dart';
import 'package:nextrep/features/arc_restart/delete_arc_screen.dart';
import 'package:nextrep/features/arc_restart/restart_labels.dart';
import 'package:nextrep/features/arc_restart/restart_screen.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/habits/habits_screen.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12F through the whole app (real router, screens, services and an
/// in-memory Drift database; injected clock; platform services faked):
/// the Restart entry points, the typed RESTART confirmation (every word,
/// Cancel, Back), Keep and Delete, the success screen, the separate typed
/// DELETE screen (Keep it, Back, export first, failure), midnight, a
/// completed arc meanwhile, refusals and storage failures, and the
/// completed-arc deletion now behind the same typed word (O11). Every
/// non-committing step is checked against a full database snapshot. All
/// data synthetic.

final day1 = LocalDate(2026, 10, 7); // Wednesday
LocalDate d(int n) => day1.addDays(n - 1);

Widget _app(TestApp app, {String boot = AppRoutes.today}) => ProviderScope(
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
    bootLocationProvider.overrideWith((ref) async => boot),
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

final _word = find.byKey(const ValueKey('restart-word'));
final _confirm = find.byKey(const ValueKey('restart-confirm'));
final _deleteWord = find.byKey(const ValueKey('delete-word'));
final _deleteConfirm = find.byKey(const ValueKey('delete-confirm'));

bool _enabled(WidgetTester tester, Finder button) =>
    tester
        .widget<ButtonStyleButton>(
          find.descendant(
            of: button,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            matchRoot: true,
          ),
        )
        .onPressed !=
    null;

/// Android's Back.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Today → Edit habits → the Restart entry at the end of the list.
Future<void> _openRestartFromHabits(
  WidgetTester tester, {
  String entry = 'Restart with this setup',
}) async {
  await clearCelebrations(tester);
  if (find.byType(HabitsScreen).evaluate().isEmpty) {
    await reveal(tester, find.text('Edit habits'));
    await tester.tap(find.text('Edit habits'));
    await tester.pumpAndSettle();
  }
  await tester.drag(find.byType(ListView), const Offset(0, -4000));
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.text(entry));
  expect(find.byType(RestartScreen), findsOneWidget);
}

/// A Rolling arc on Day 10 (Fri 16 Oct 2026): Days 1–9 Perfect, water
/// logged today, a reflection, and a goal edit waiting for tomorrow.
Future<(TestApp, WinterArcSession)> _day10() async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 10, 7, 9)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  final arc = await startRolling(app, day1);
  await liveDays(app, d(1), d(9));
  at(app, d(10), hour: 6);
  await app.reminders.update((p) => p.copyWith(dailyEnabled: true));
  at(app, d(10));
  await completeHabit(app, 'water');
  await app.reflections.save(
    sessionId: arc.id,
    date: d(10),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Still here'),
  );
  await app.tracking.editHabit(
    habitId: 'learning',
    edit: const HabitEdit(target: 45, minimumTarget: 15),
    date: d(10),
  );
  await app.achievements.reconcile();
  return (app, arc);
}

void main() {
  testWidgets('T1: the typed word, Cancel and Back write nothing; Keep: '
      'the restart, its success screen, the old arc in History', (
    tester,
  ) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    final start = await snapshotAll(app.db);

    await _openRestartFromHabits(tester);
    // The approved wording (spec § 9.9).
    expect(find.text('Restart with this setup'), findsWidgets);
    expect(
      find.text(
        'A new Rolling 92-Day Arc starts today on Day 1 with your 7 '
        'habits, goals and order.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Day 1: today, Fri 16 Oct · Day 92: Fri 15 Jan 2027'),
      findsOneWidget,
    );
    expect(find.text('Your current Arc ends at Day 10 of 92.'), findsOneWidget);
    expect(find.text(RestartCopy.notCompleted), findsOneWidget);
    expect(find.text(RestartCopy.ownProgress), findsOneWidget);
    expect(find.text(RestartCopy.lastDay), findsNothing);
    expect(find.text(RestartCopy.keep), findsOneWidget);
    expect(find.text(RestartCopy.delete), findsOneWidget);
    expect(
      tester.widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>)).groupValue,
      isFalse,
      reason: 'D1: Keep is selected by default',
    );

    // The confirm button for every word (addendum § L4).
    expect(_enabled(tester, _confirm), isFalse, reason: 'empty');
    for (final (typed, ok) in [
      ('restart', false),
      ('RESTAR', false),
      ('Restart', false),
      ('RESTARTS', false),
      (' RESTART ', true),
      ('RESTART', true),
      ('', false),
    ]) {
      await _type(tester, _word, typed);
      expect(_enabled(tester, _confirm), ok, reason: '"$typed"');
    }
    // A wrong word can't confirm from the keyboard either.
    await _type(tester, _word, 'restart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await snapshotAll(app.db), start);

    // Cancel: nothing changes; back on Habits.
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, find.text(RestartCopy.cancel));
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(await snapshotAll(app.db), start, reason: 'Cancel');

    // Back (system): nothing changes; the typed text is discarded.
    await _openRestartFromHabits(tester);
    await _type(tester, _word, 'RESTART');
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(await snapshotAll(app.db), start, reason: 'Back');
    await _openRestartFromHabits(tester);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: _word, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      isEmpty,
      reason: 'the typed text is discarded',
    );

    // Restart, keeping the old arc.
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);
    expect(find.text(RestartCopy.started), findsWidgets);
    expect(find.text('Day 1 of 92 · Fri 16 Oct 2026'), findsOneWidget);
    expect(find.text(RestartCopy.previousInHistory), findsOneWidget);
    expect(
      find.textContaining('Ended early · Day 10 of 92 · '),
      findsOneWidget,
    );
    final sessions = await app.sessions.listSessions();
    expect(sessions, hasLength(2));
    final ended = sessions.singleWhere((s) => s.id == arc.id);
    expect(ended.status, WinterArcStatus.ended);
    expect(ended.closedOn, d(10));
    final xp = (await app.progress.loadArc(arc.id)).totalXp;
    expect(
      find.text('Ended early · Day 10 of 92 · ${xpAmount(xp)} XP'),
      findsOneWidget,
    );

    // Reminders are re-planned for the new arc (its Day 2 tomorrow).
    final daily = app.scheduler.pending.where(
      (r) => r.kind == ReminderKind.daily,
    );
    expect(daily.first.title, 'Winter Arc · Day 2');

    // View previous Arc: its read-only summary, "Ended early".
    await _tapVisible(tester, find.text(RestartCopy.viewPrevious));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('WINTER ARC ENDED EARLY'), findsOneWidget);
    expect(find.text('Ended early · Day 10 of 92'), findsOneWidget);
    expect(find.textContaining('COMPLETE'), findsNothing);
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RestartScreen), findsOneWidget);

    // Back from the success screen goes to Today, on the new Day 1.
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0 of \d+ done$')), findsOneWidget);

    // Arc History: the old arc ended early, the new one active.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('History'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArcHistoryScreen), findsOneWidget);
    expect(find.text('ENDED EARLY'), findsOneWidget);
    expect(find.text('Ended early · Day 10 of 92'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('COMPLETED'), findsNothing);
  });

  testWidgets('Delete my old Arc…: Restart commits first; the DELETE screen '
      'counts what is lost; Keep it and Back keep the arc', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(tester);
    await _tapVisible(tester, find.text(RestartCopy.delete));
    expect(
      tester.widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>)).groupValue,
      isTrue,
    );
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);

    // D3: the restart has committed; nothing is deleted yet.
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    final old = (await app.sessions.sessionById(arc.id))!;
    expect(old.status, WinterArcStatus.ended);
    final afterRestart = await snapshotAll(app.db);
    final card = await app.history.card(arc.id);
    expect(find.text(DeleteArcCopy.titleAfterRestart), findsOneWidget);
    expect(find.text(DeleteArcCopy.afterRestartNote), findsOneWidget);
    expect(find.text('Rolling 92-Day · 7 Oct – 16 Oct 2026'), findsOneWidget);
    expect(find.text('Ended early · Day 10 of 92'), findsOneWidget);
    expect(
      find.text('10 days of progress and ${xpAmount(card.summary.totalXp)} XP'),
      findsOneWidget,
    );
    expect(
      find.text(DeleteArcCopy.achievements(card.summary.achievementsUnlocked)),
      findsOneWidget,
    );
    expect(find.text('1 Journal reflection'), findsOneWidget);
    expect(find.text(DeleteArcCopy.journey), findsOneWidget);
    expect(find.text(DeleteArcCopy.insights), findsOneWidget);
    expect(find.text(DeleteArcCopy.othersKept), findsOneWidget);
    expect(find.text(DeleteArcCopy.noUndo), findsOneWidget);

    // The word, as for RESTART: trimmed, case-sensitive.
    expect(_enabled(tester, _deleteConfirm), isFalse);
    for (final (typed, ok) in [
      ('delete', false),
      ('DELET', false),
      ('RESTART', false),
      (' DELETE ', true),
      ('DELETE', true),
    ]) {
      await _type(tester, _deleteWord, typed);
      expect(_enabled(tester, _deleteConfirm), ok, reason: '"$typed"');
    }

    // Export a backup first: Data & Backup, and back here.
    await _tapVisible(tester, find.text(DeleteArcCopy.exportFirst));
    expect(find.byType(DataBackupScreen), findsOneWidget);
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    expect(await snapshotAll(app.db), afterRestart);

    // Keep it: to Today; the old arc stays.
    await _tapVisible(tester, find.byKey(const ValueKey('delete-keep')));
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(await snapshotAll(app.db), afterRestart, reason: 'D4');

    // Back from the screen (opened again after a restart): to Today.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(app, boot: AppRoutes.deleteArc(arc.id, afterRestart: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    await _type(tester, _deleteWord, 'DELETE');
    await _systemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(await snapshotAll(app.db), afterRestart, reason: 'Back');
  });

  testWidgets('T6/T7: DELETE removes exactly the old arc; the new arc and '
      'every setting are identical', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    final outcome = await restartNow(app, arc.id);
    final before = await snapshotAll(app.db);
    await tester.pumpWidget(
      _app(app, boot: AppRoutes.deleteArc(arc.id, afterRestart: true)),
    );
    await tester.pumpAndSettle();
    await _type(tester, _deleteWord, 'DELETE');
    await _tapVisible(tester, _deleteConfirm);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text(DeleteArcCopy.deleted), findsOneWidget);
    expect(await app.sessions.sessionById(arc.id), isNull);
    final after = await snapshotAll(app.db);
    for (final table in before.keys) {
      final rows = before[table]!;
      final kept = [
        for (final r in rows)
          if (!(r['session_id'] == arc.id ||
              (table == 'winter_arc_sessions' && r['id'] == arc.id)))
            r,
      ];
      expect(after[table], kept, reason: table);
    }
    expect((await app.sessions.currentSession())!.id, outcome.started.id);
    // Insights leave the deleted arc out.
    final insights = await app.insights.snapshot();
    expect(insights.overall.arcCount, 1);
  });

  testWidgets('T8: a deletion failure keeps both arcs and offers Retry', (
    tester,
  ) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    await restartNow(app, arc.id);
    final before = await snapshotAll(app.db);
    await tester.pumpWidget(
      _app(app, boot: AppRoutes.deleteArc(arc.id, afterRestart: true)),
    );
    await tester.pumpAndSettle();
    await app.db.customStatement(
      'CREATE TEMP TRIGGER injected_failure BEFORE DELETE ON '
      "winter_arc_sessions BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await _type(tester, _deleteWord, 'DELETE');
    await _tapVisible(tester, _deleteConfirm);
    expect(find.text(DeleteArcCopy.failed), findsOneWidget);
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    expect(await snapshotAll(app.db), before, reason: 'D5');
    await app.db.customStatement('DROP TRIGGER injected_failure');
    await _tapVisible(tester, _deleteConfirm);
    expect(await app.sessions.sessionById(arc.id), isNull);
  });

  testWidgets('process death between restart and deletion: the relaunched '
      'app keeps the old arc and asks nothing', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(tester);
    await _tapVisible(tester, find.text(RestartCopy.delete));
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    final committed = await snapshotAll(app.db);
    // The process dies here; the app is launched again from storage.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(app, boot: AppRoutes.today));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(DeleteArcScreen), findsNothing);
    expect(await snapshotAll(app.db), committed);
    expect(
      (await app.sessions.sessionById(arc.id))!.status,
      WinterArcStatus.ended,
    );
  });

  testWidgets('a storage failure: "Couldn\'t restart. Nothing was changed." '
      'with Retry; nothing changed until the retry works', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    final start = await snapshotAll(app.db);
    await _openRestartFromHabits(tester);
    await app.db.customStatement(
      'CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON habits '
      "BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);
    expect(find.text(RestartCopy.failed), findsOneWidget);
    expect(find.text(RestartCopy.retry), findsOneWidget);
    expect(find.byType(RestartScreen), findsOneWidget);
    expect(await snapshotAll(app.db), start, reason: 'T5');
    await app.db.customStatement('DROP TRIGGER injected_failure');
    await _tapVisible(tester, _confirm);
    expect(find.text(RestartCopy.started), findsWidgets);
    expect(
      (await app.sessions.sessionById(arc.id))!.status,
      WinterArcStatus.ended,
    );
  });

  testWidgets('single-fire: a double tap starts one arc', (tester) async {
    await _tall(tester);
    final (app, _) = await _day10();
    addTearDown(app.db.close);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(tester);
    await _type(tester, _word, 'RESTART');
    await tester.ensureVisible(_confirm);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.tap(_confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(await app.sessions.listSessions(), hasLength(2));
  });

  testWidgets('midnight while open: the details are re-read; the restart '
      'uses the new date', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    app.clock.current = DateTime(2026, 10, 16, 23, 59, 30);
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(tester);
    expect(find.text('Your current Arc ends at Day 10 of 92.'), findsOneWidget);
    app.clock.current = DateTime(2026, 10, 17, 0, 0, 2);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.text(RestartCopy.dateChanged), findsOneWidget);
    expect(
      find.text('Day 1: today, Sat 17 Oct · Day 92: Sat 16 Jan 2027'),
      findsOneWidget,
    );
    // Nothing logged on Day 11 yet: it ends at Day 10.
    expect(find.text('Your current Arc ends at Day 10 of 92.'), findsOneWidget);
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);
    final started = (await app.sessions.currentSession())!;
    expect(started.startDate, d(11));
    expect((await app.sessions.sessionById(arc.id))!.closedOn, d(10));
  });

  testWidgets('Day 92: the extra line; midnight completes the arc and the '
      'screen closes to its summary, nothing ended', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDays(app, d(90), d(91));
    app.clock.current = DateTime(2027, 1, 6, 23, 59, 30); // Day 92
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(tester);
    expect(find.text(RestartCopy.lastDay), findsOneWidget);
    expect(find.text('Your current Arc ends at Day 91 of 92.'), findsOneWidget);
    await _type(tester, _word, 'RESTART');
    app.clock.current = DateTime(2027, 1, 7, 0, 0, 2);
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(find.byType(RestartScreen), findsNothing);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
    final s = (await app.sessions.sessionById(arc.id))!;
    expect(s.status, WinterArcStatus.completed);
    expect(await app.sessions.listSessions(), hasLength(1));
  });

  testWidgets('the phone date is behind the history: the screen names the '
      'date and offers no confirmation', (tester) async {
    await _tall(tester);
    final (app, _) = await _day10();
    addTearDown(app.db.close);
    at(app, d(9));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    final start = await snapshotAll(app.db);
    await _openRestartFromHabits(tester);
    expect(
      find.text(
        "Your phone's date (15 Oct) is earlier than your latest logged day "
        '(16 Oct). You can restart from 16 Oct. Nothing was changed.',
      ),
      findsOneWidget,
    );
    expect(_word, findsNothing);
    expect(_confirm, findsNothing);
    await _tapVisible(tester, find.text(RestartCopy.cancel));
    expect(await snapshotAll(app.db), start);
  });

  testWidgets('Seasonal: "Start a Rolling Arc with this setup"; the season '
      'keeps its dates', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 15)));
    addTearDown(app.db.close);
    final arc = await joinSeason(app, DateTime(2026, 10, 15));
    await liveDays(app, LocalDate(2026, 10, 15), LocalDate(2026, 11, 13));
    at(app, LocalDate(2026, 11, 14));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    await _openRestartFromHabits(
      tester,
      entry: 'Start a Rolling Arc with this setup',
    );
    expect(find.text('Start a Rolling Arc with this setup'), findsOneWidget);
    expect(
      find.text(
        'You will leave the Seasonal Winter Arc on Day 44. A new Rolling '
        '92-Day Arc starts today on Day 1.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('It uses your 7 habits, goals and order.'),
      findsOneWidget,
    );
    expect(find.textContaining('restart the season'), findsNothing);
    await _type(tester, _word, 'RESTART');
    expect(find.text('Start Rolling Arc'), findsOneWidget);
    await _tapVisible(tester, _confirm);
    final ended = (await app.sessions.sessionById(arc.id))!;
    expect(ended.status, WinterArcStatus.ended);
    expect(ended.startDate, LocalDate(2026, 10, 1));
    expect(ended.kind, ArcKind.seasonalWinter);
    final started = (await app.sessions.currentSession())!;
    expect(started.kind, ArcKind.rolling92);
    expect(started.startDate, LocalDate(2026, 11, 14));
  });

  testWidgets('paused Today offers Restart; it removes the open pause', (
    tester,
  ) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDays(app, d(1), d(13));
    at(app, d(13));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(14));
    at(app, d(19));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    expect(find.text(PausedCopy.heading), findsOneWidget);
    await _tapVisible(tester, find.text('Restart with this setup'));
    expect(find.byType(RestartScreen), findsOneWidget);
    expect(find.text(RestartCopy.pauseEnds), findsOneWidget);
    expect(find.text('Your current Arc ends at Day 13 of 92.'), findsOneWidget);
    await _type(tester, _word, 'RESTART');
    await _tapVisible(tester, _confirm);
    final ended = (await app.sessions.sessionById(arc.id))!;
    expect(ended.freezes, isEmpty);
    expect(ended.closedOn, d(13));
    await _tapVisible(tester, find.text(RestartCopy.goToToday));
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text(PausedCopy.heading), findsNothing);
  });

  testWidgets('a scheduled pause: Habits offers Restart and the screen says '
      'the pause is cancelled', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await liveDays(app, d(1), d(4));
    await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: d(5));
    await tester.pumpWidget(_app(app));
    await tester.pumpAndSettle();
    expect(find.text(PauseCopy.bannerTomorrow), findsOneWidget);
    await _openRestartFromHabits(tester);
    expect(find.text(RestartCopy.scheduledPauseRemoved), findsOneWidget);
    expect(find.text('Your current Arc ends at Day 4 of 92.'), findsOneWidget);
  });

  testWidgets('O11: a completed arc is deleted only with DELETE typed on the '
      'same screen; Keep it returns to its summary', (tester) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
    addTearDown(app.db.close);
    final arc = await runFirstArc(app);
    await tester.pumpWidget(_app(app, boot: AppRoutes.arc(arc.id)));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    final start = await snapshotAll(app.db);
    await tester.tap(find.byTooltip('Arc options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Arc'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteArcScreen), findsOneWidget);
    expect(find.text(DeleteArcCopy.titleFromSummary), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text(DeleteArcCopy.afterRestartNote), findsNothing);
    expect(find.text('0 achievements'), findsNothing);
    await _tapVisible(tester, find.byKey(const ValueKey('delete-keep')));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(await snapshotAll(app.db), start);

    await tester.tap(find.byTooltip('Arc options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Arc'));
    await tester.pumpAndSettle();
    await _type(tester, _deleteWord, 'DELETE');
    await _tapVisible(tester, _deleteConfirm);
    expect(await app.sessions.listSessions(), isEmpty);
  });

  testWidgets('an ended arc offers Delete Arc on its summary; the active '
      'arc can never be deleted from the screen', (tester) async {
    await _tall(tester);
    final (app, arc) = await _day10();
    addTearDown(app.db.close);
    final outcome = await restartNow(app, arc.id);
    await tester.pumpWidget(_app(app, boot: AppRoutes.arc(arc.id)));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byTooltip('Arc options'), findsOneWidget);
    // Opened for the active arc (only a crafted link could; the router
    // sends it to Today, see the redirect test): nothing can be confirmed.
    final before = await snapshotAll(app.db);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(
      _app(app, boot: AppRoutes.deleteArc(outcome.started.id)),
    );
    await tester.pumpAndSettle();
    if (find.byType(DeleteArcScreen).evaluate().isNotEmpty) {
      await _type(tester, _deleteWord, 'DELETE');
      expect(_enabled(tester, _deleteConfirm), isFalse);
    }
    expect(await snapshotAll(app.db), before);
  });

  test('the router: Restart needs an active arc; a delete link for the '
      'active or unfinished arc leads away from it', () {
    final active = WinterArcSession(
      id: 2,
      kind: ArcKind.rolling92,
      startDate: d(10),
      endDate: d(10).addDays(91),
      status: WinterArcStatus.active,
      createdAt: DateTime(2026),
      participationStartDate: d(10),
    );
    final ended = WinterArcSession(
      id: 1,
      kind: ArcKind.rolling92,
      startDate: d(1),
      endDate: d(92),
      status: WinterArcStatus.ended,
      createdAt: DateTime(2026),
      participationStartDate: d(1),
      closedOn: d(9),
    );
    // The router passes the location's path (`state.uri.path`).
    String? redirect(ArcResolution r, String location) =>
        AppRoutes.redirect(r, Uri.parse(location).path);
    final running = ArcResolution(current: active, latestCompleted: ended);
    final finishedOnly = ArcResolution(latestCompleted: ended);
    expect(redirect(running, AppRoutes.restartArc(2)), isNull);
    expect(redirect(running, AppRoutes.deleteArc(2)), AppRoutes.today);
    expect(
      redirect(running, AppRoutes.deleteArc(1, afterRestart: true)),
      isNull,
    );
    expect(
      redirect(finishedOnly, AppRoutes.restartArc(1)),
      AppRoutes.arc(1),
      reason: 'no active arc: the screen closes to the finished summary',
    );
    expect(redirect(finishedOnly, AppRoutes.deleteArc(1)), isNull);
  });

  testWidgets('zero counts are shown as 0 (an arc ended on Day 1)', (
    tester,
  ) async {
    await _tall(tester);
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 7)));
    addTearDown(app.db.close);
    final arc = await startRolling(app, day1);
    await restartNow(app, arc.id);
    await tester.pumpWidget(
      _app(app, boot: AppRoutes.deleteArc(arc.id, afterRestart: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 day of progress and 0 XP'), findsOneWidget);
    expect(find.text('0 achievements'), findsOneWidget);
    expect(find.text('0 Journal reflections'), findsOneWidget);
  });
}
