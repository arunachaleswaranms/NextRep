import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_habit_repository.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_repository.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/confirm_start_screen.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/habit_setup/review_setup_screen.dart';
import 'package:nextrep/features/habit_setup/saved_setup_screen.dart';
import 'package:nextrep/features/habit_setup/setup_labels.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';
import 'package:nextrep/features/shell/unknown_page_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12D (spec §§ 4, 9.1–9.5; addendum § L2, W): habit ordering, Save
/// for Later, the saved-setup hub, Review Setup and Confirm & Start, driven
/// through the real app on an in-memory database. All data is synthetic.

Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FakeReminderScheduler? scheduler,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    reminderSchedulerProvider.overrideWithValue(
      scheduler ?? FakeReminderScheduler(),
    ),
    ...overrides,
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _launch(
  WidgetTester tester,
  TestApp app, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    _app(app.db, app.clock, scheduler: app.scheduler, overrides: overrides),
  );
  await tester.pumpAndSettle();
}

Future<void> _stayOpen(
  WidgetTester tester,
  FakeClock clock,
  Duration wait,
) async {
  clock.advance(wait);
  await tester.pump(wait);
  await tester.pumpAndSettle();
}

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// The stored order of the current setup (or of [sessionId]).
Future<List<String>> _stored(TestApp app, [int? sessionId]) async {
  final id = sessionId ?? (await app.winterArc.currentSession())!.id;
  return [for (final h in await app.habits.habitsForSession(id)) h.id];
}

/// The habit cards of Habit Setup from the top of the list, by title.
Future<List<String>> _onScreen(WidgetTester tester) async {
  await showIn(tester, find.text('YOUR HABITS'));
  final tiles = tester.widgetList<HabitToggleTile>(
    find.byType(HabitToggleTile),
  );
  final placed = [
    for (final t in tiles)
      (
        t.habit.title,
        tester.getTopLeft(find.byWidget(t, skipOffstage: false)).dy,
      ),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (title, _) in placed) title];
}

/// Nothing has started: one setup, no activity.
Future<void> _stillSetup(TestApp app) async {
  final sessions = await app.sessions.listSessions();
  expect(sessions.where((s) => s.status == WinterArcStatus.active), isEmpty);
  expect(
    sessions.where((s) => s.status == WinterArcStatus.setup),
    hasLength(1),
  );
  final all = await snapshotAll(app.db);
  for (final table in [
    'daily_habit_progress_entries',
    'xp_transactions',
    'day_modes',
    'achievement_unlocks',
  ]) {
    expect(all[table], isEmpty, reason: table);
  }
}

/// Records the screen reader announcements the app sends.
List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        said.add((map['data']! as Map<Object?, Object?>)['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return said;
}

/// Performs the custom screen-reader action [label] on the node [node].
void _customAction(WidgetTester tester, Finder node, String label) {
  final semantics = tester.getSemantics(node);
  final id = CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
  semantics.owner!.performAction(
    semantics.id,
    SemanticsAction.customAction,
    id,
  );
}

Future<void> _openMenu(WidgetTester tester, String title) =>
    tapShown(tester, find.byTooltip('Options for $title'));

PopupMenuItem<Object?> _menuItem(WidgetTester tester, String label) =>
    tester.widget<PopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );

/// The filled button [label], scrolled into view first (lists are lazy).
Future<FilledButton> _filledShown(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  return tester.widget<FilledButton>(finder);
}

FilledButton _filled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

/// The system back gesture (Habit Setup has no back button of its own).
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Habits whose reorder always fails, as a full disk would.
final class _FailingReorder implements HabitRepository {
  _FailingReorder(this._inner);

  final HabitRepository _inner;

  @override
  Future<void> reorderSetupHabits(int sessionId, List<String> orderedIds) =>
      throw const PersistenceFailure('Storage operation failed: reorder');

  @override
  Future<List<Habit>> habitsForSession(int sessionId) =>
      _inner.habitsForSession(sessionId);
  @override
  Future<HabitHistory> historyForSession(int sessionId) =>
      _inner.historyForSession(sessionId);
  @override
  Future<Habit?> habit(int sessionId, String habitId) =>
      _inner.habit(sessionId, habitId);
  @override
  Future<bool> setEnabled(
    int sessionId,
    String habitId, {
    required bool enabled,
  }) => _inner.setEnabled(sessionId, habitId, enabled: enabled);
  @override
  Future<void> addSetupHabit(int sessionId, Habit habit) =>
      _inner.addSetupHabit(sessionId, habit);
  @override
  Future<bool> updateSetupHabit(int sessionId, Habit habit) =>
      _inner.updateSetupHabit(sessionId, habit);
  @override
  Future<bool> deleteSetupHabit(int sessionId, String habitId) =>
      _inner.deleteSetupHabit(sessionId, habitId);
}

void main() {
  late TestApp app;

  TestApp make(DateTime now) {
    final made = TestApp(memoryDatabase(), FakeClock(now));
    addTearDown(made.db.close);
    return made;
  }

  // Each test makes its database inside its own body: one created in
  // setUp (outside the test's fake-async zone) can't be awaited in it.

  testWidgets('§ 30: choose Rolling, edit, add, switch off, reorder, save, '
      'reopen, review, confirm days later, start', (tester) async {
    app = make(DateTime(2026, 11, 2, 9));
    final semantics = tester.ensureSemantics();
    _phone(tester);
    await _launch(tester, app);
    await tapShown(tester, find.text("Let's Begin"));
    await tapShown(tester, find.text('Rolling 92-Day Arc'));
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    await _stillSetup(app);

    // 4. Water: 8 → 9 glasses.
    await _openMenu(tester, 'Water Intake');
    await tapShown(tester, find.text('Edit'));
    await tester.tap(find.byTooltip('Increase Daily goal'));
    await tester.pumpAndSettle();
    await tapShown(tester, find.text('Save'));
    expect(find.text('9 glasses · Minimum 3 glasses'), findsOneWidget);

    // 5. A custom habit, added last.
    await tapShown(tester, find.text('Add Habit'));
    await tester.scrollUntilVisible(
      find.text('Create your own'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapShown(tester, find.text('Create your own'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Sketch');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add habit'));
    await tapShown(tester, find.text('Add habit'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect((await _stored(app)).last, startsWith('custom_'));

    // 6. Learning switched off.
    await tapShown(
      tester,
      find.descendant(
        of: find.widgetWithText(HabitToggleTile, 'Learning / Skills'),
        matching: find.byType(Switch),
      ),
    );

    // 7. Sketch moved to the top with the menu (three moves up shown;
    // the rest with the screen-reader action).
    for (var i = 0; i < 3; i++) {
      await _openMenu(tester, 'Sketch');
      await tapShown(tester, find.text('Move up'));
    }
    final custom = (await _stored(app))[4];
    while ((await _stored(app)).first != custom) {
      final at = (await _stored(app)).indexOf(custom);
      final habits = await app.winterArc.setupHabits();
      final card = find.bySemanticsLabel(
        SetupLabels.habitCard(habits[at], index: at, of: habits.length),
      );
      await showIn(tester, card);
      _customAction(tester, card, 'Move up');
      await tester.pumpAndSettle();
    }
    final chosen = await _stored(app);
    expect(chosen.first, custom);
    expect((await _onScreen(tester)).first, 'Sketch');
    await _stillSetup(app);

    // 8. Save for Later: the hub, and nothing written.
    final saved = await snapshotAll(app.db);
    await tapShown(tester, find.text('Save for Later'));
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    expect(find.text(SetupLabels.saved), findsOneWidget);
    expect(find.text(SetupLabels.savedDetail), findsOneWidget);
    expect(find.text('Rolling 92-Day · 8 habits · 4 on'), findsOneWidget);
    expect(find.text('Day 1 will be the day you start.'), findsOneWidget);
    expect(await snapshotAll(app.db), saved);

    // 9–11. Closed; reopened four days later: the hub.
    await _shutDown(tester);
    app.clock.current = DateTime(2026, 11, 6, 8);
    await _launch(tester, app);
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    expect(find.text(SetupLabels.hubTitle), findsOneWidget);
    expect(find.byType(HabitSetupScreen), findsNothing);

    // 12–13. Continue Editing: everything as saved.
    await continueEditing(tester);
    expect((await _onScreen(tester)).first, 'Sketch');
    expect(await _stored(app), chosen);
    expect(find.text('9 glasses · Minimum 3 glasses'), findsOneWidget);

    // 14–15. Review & Start: on habits in order, Learning under Off.
    await startFromSetupReviewOnly(tester);
    expect(find.byType(ReviewSetupScreen), findsOneWidget);
    expect(find.text('YOUR HABITS (4)'), findsOneWidget);
    expect(find.text('OFF (4)'), findsOneWidget);
    final setup = await app.winterArc.setup();
    final on = setup.enabledHabits;
    expect(on.first.id, custom);
    for (final (i, h) in on.indexed) {
      expect(
        find.bySemanticsLabel(SetupLabels.reviewHabit(h, position: i + 1)),
        findsOneWidget,
      );
    }
    expect(
      find.bySemanticsLabel(
        SetupLabels.reviewHabit(
          setup.habits.firstWhere((h) => h.id == 'learning'),
        ),
      ),
      findsOneWidget,
    );

    // 16–17. Confirm & Start: Day 1 is the day it is confirmed.
    await tapShown(tester, find.text('Continue to Start'));
    expect(find.byType(ConfirmStartScreen), findsOneWidget);
    expect(find.text(SetupLabels.confirmTitle), findsOneWidget);
    expect(find.text('Rolling 92-Day Arc · 4 habits'), findsOneWidget);
    expect(find.text('Today, Fri 6 Nov 2026'), findsOneWidget);
    expect(find.text('Fri 5 Feb 2027'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Day 1: Today, Friday 6 November 2026'),
      findsOneWidget,
    );

    // 18–19. Save for Later again, then back through the review.
    await tapShown(tester, find.text('Save for Later'));
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    await _stillSetup(app);
    await tapShown(tester, find.text('Start Challenge'));
    expect(find.byType(ReviewSetupScreen), findsOneWidget);
    await _stillSetup(app);

    // 20–22. Confirm: Today, Day 1, in the chosen order.
    await confirmFromReview(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    final arc = (await app.sessions.listSessions()).single;
    expect(arc.status, WinterArcStatus.active);
    expect(arc.startDate, app.clock.today());
    expect(await _stored(app, arc.id), chosen);
    final today = await app.tracking.today();
    expect(
      [for (final e in today.entries) e.habit.id],
      [for (final h in on) h.id],
    );
    expect(
      today.entries.firstWhere((e) => e.habit.id == 'water').config.target,
      9,
    );
    semantics.dispose();
    await _shutDown(tester);
  });

  group('Habit Setup ordering', () {
    Future<void> openEditor(WidgetTester tester) async {
      await app.winterArc.beginSetup();
      _phone(tester);
      await _launch(tester, app);
      await continueEditing(tester);
    }

    testWidgets('the menu moves any habit; first and last moves are '
        'disabled; edits keep places; the order is announced', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      final said = _announcements(tester);
      await openEditor(tester);
      expect(find.text(SetupLabels.reorderHint), findsOneWidget);

      await _openMenu(tester, 'Workout');
      expect(_menuItem(tester, 'Move up').enabled, isFalse);
      expect(_menuItem(tester, 'Move down').enabled, isTrue);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      await tapShown(tester, find.text('Move down'));
      expect((await _stored(app)).take(2), ['water', 'workout']);
      expect(said, ['Workout moved to position 2 of 7']);

      // A disabled habit moves too (Meditation is off and last).
      await _openMenu(tester, 'Meditation');
      expect(_menuItem(tester, 'Move down').enabled, isFalse);
      await tapShown(tester, find.text('Move up'));
      expect((await _stored(app)).sublist(5), ['meditation', 'sleep_before']);
      final habits = await app.winterArc.setupHabits();
      expect(habits.firstWhere((h) => h.id == 'meditation').enabled, isFalse);
      expect(said.last, 'Meditation moved to position 6 of 7');
      await _shutDown(tester);
    });

    testWidgets('one habit: both moves disabled, no handle, no drag', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      await app.winterArc.beginSetup();
      for (final id in (await _stored(app)).skip(1)) {
        await app.winterArc.deleteSetupHabit(id);
      }
      await openEditor(tester);
      expect(find.bySemanticsLabel(RegExp('^Reorder ')), findsNothing);
      expect(find.text(SetupLabels.reorderHint), findsNothing);
      await _openMenu(tester, 'Workout');
      expect(_menuItem(tester, 'Move up').enabled, isFalse);
      expect(_menuItem(tester, 'Move down').enabled, isFalse);
      await _shutDown(tester);
    });

    testWidgets('screen-reader actions: each card says its place and offers '
        'only the moves it has', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      final handle = tester.ensureSemantics();
      final said = _announcements(tester);
      await openEditor(tester);
      var habits = await app.winterArc.setupHabits();
      String label(int i) =>
          SetupLabels.habitCard(habits[i], index: i, of: habits.length);
      expect(label(1), 'Water Intake, 8 glasses, on, 2 of 7');

      bool has(int i, String action) => tester
          .getSemantics(find.bySemanticsLabel(label(i)))
          .getSemanticsData()
          .customSemanticsActionIds!
          .contains(
            CustomSemanticsAction.getIdentifier(
              CustomSemanticsAction(label: action),
            ),
          );
      expect(has(0, 'Move up'), isFalse);
      expect(has(0, 'Move down'), isTrue);
      expect(has(1, 'Move up'), isTrue);
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(label(6)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(has(6, 'Move down'), isFalse);

      await tester.scrollUntilVisible(
        find.bySemanticsLabel(label(1)),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      _customAction(tester, find.bySemanticsLabel(label(1)), 'Move up');
      await tester.pumpAndSettle();
      expect((await _stored(app)).first, 'water');
      expect(said, ['Water Intake moved to position 1 of 7']);
      habits = await app.winterArc.setupHabits();
      expect(
        find.bySemanticsLabel('Water Intake, 8 glasses, on, 1 of 7'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Reorder Water Intake'), findsOneWidget);
      handle.dispose();
      await _shutDown(tester);
    });

    testWidgets('drag by the handle, and by a long press on the card; a '
        'drop in place writes nothing; a short tap still switches', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      await openEditor(tester);
      final before = await _stored(app);
      Future<void> drag(Finder from, double dy, {bool long = false}) async {
        final gesture = await tester.startGesture(tester.getCenter(from));
        if (long) await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump(const Duration(milliseconds: 50));
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(Offset(0, dy / 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // Handle: Workout down past two cards.
      final card = tester.getSize(find.byType(HabitToggleTile).first).height;
      await drag(find.bySemanticsLabel('Reorder Workout'), card * 2.2);
      var after = await _stored(app);
      expect(after.indexOf('workout'), 2);
      expect([...after]..sort(), [...before]..sort());

      // Long press on the card body: Meditation up one place.
      final meditation = find.text('Meditation');
      await tester.scrollUntilVisible(
        meditation,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(meditation);
      await tester.pumpAndSettle();
      final wasAt = after.indexOf('meditation');
      await drag(meditation, -card * 1.2, long: true);
      after = await _stored(app);
      expect(after.indexOf('meditation'), wasAt - 1);
      final habits = await app.winterArc.setupHabits();
      expect(
        habits.firstWhere((h) => h.id == 'meditation').enabled,
        isFalse,
        reason: 'a drag never switches a habit',
      );

      // Dropped where it was: nothing is written.
      final water = find.bySemanticsLabel('Reorder Water Intake');
      await tester.scrollUntilVisible(
        water,
        -100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final rows = await snapshotAll(app.db);
      // Picked up, moved a card down and back, dropped at its own place.
      final gesture = await tester.startGesture(tester.getCenter(water));
      await tester.pump(const Duration(milliseconds: 50));
      for (final dy in [...List.filled(6, 12.0), ...List.filled(6, -12.0)]) {
        await gesture.moveBy(Offset(0, dy));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(await snapshotAll(app.db), rows);
      // A tap on the grip never switches the habit.
      await tester.tap(water);
      await tester.pumpAndSettle();
      expect(await snapshotAll(app.db), rows);

      // A short tap still switches.
      await tapShown(tester, find.text('Meditation'));
      expect(
        (await app.winterArc.setupHabits())
            .firstWhere((h) => h.id == 'meditation')
            .enabled,
        isTrue,
      );
      await _shutDown(tester);
    });

    testWidgets('a failed save puts the stored order back and says so (O4)', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      await app.winterArc.beginSetup();
      _phone(tester);
      await _launch(
        tester,
        app,
        overrides: [
          habitRepositoryProvider.overrideWith(
            (ref) => _FailingReorder(DriftHabitRepository(app.db)),
          ),
        ],
      );
      await continueEditing(tester);
      final before = await _stored(app);
      await _openMenu(tester, 'Workout');
      await tapShown(tester, find.text('Move down'));
      expect(find.text(SetupLabels.reorderFailed), findsOneWidget);
      expect(await _stored(app), before);
      expect((await _onScreen(tester)).take(2), ['Workout', 'Water Intake']);
      await _shutDown(tester);
    });
  });

  group('the saved-setup hub', () {
    testWidgets('zero habits: saved, reopened, cannot start; Continue '
        'Editing leads; no starter habit returns (S6)', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      for (final id in await _stored(app)) {
        await app.winterArc.deleteSetupHabit(id);
      }
      await _launch(tester, app);
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      expect(find.text('Rolling 92-Day · 0 habits · 0 on'), findsOneWidget);
      expect(find.text(SetupLabels.addAHabit), findsWidgets);
      expect(_filled(tester, 'Start Challenge').onPressed, isNull);
      expect(_filled(tester, 'Continue Editing').onPressed, isNotNull);
      expect(
        find.bySemanticsLabel(
          'Start Challenge, unavailable. Add a habit to start.',
        ),
        findsOneWidget,
      );
      // Review stays readable, with no way on to Confirm.
      await tapShown(tester, find.text('Review Setup'));
      expect(find.text(SetupLabels.noHabitsYet), findsOneWidget);
      expect(
        (await _filledShown(tester, 'Continue to Start')).onPressed,
        isNull,
      );
      expect((await _filledShown(tester, 'Edit Setup')).onPressed, isNotNull);
      // Save for Later works with nothing in it.
      await tapShown(tester, find.text('Save for Later'));
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      expect(await _stored(app), isEmpty);
      await _shutDown(tester);
    });

    testWidgets('every habit off: Start explains why', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      for (final id in await _stored(app)) {
        await app.winterArc.setHabitEnabled(id, enabled: false);
      }
      await _launch(tester, app);
      expect(_filled(tester, 'Start Challenge').onPressed, isNull);
      expect(find.text(SetupLabels.turnOneOn), findsOneWidget);
      await tapShown(tester, find.text('Review Setup'));
      expect(find.text(SetupLabels.noneOn), findsOneWidget);
      expect(find.text('OFF (7)'), findsOneWidget);
      expect(
        (await _filledShown(tester, 'Continue to Start')).onPressed,
        isNull,
      );
      await _shutDown(tester);
    });

    testWidgets('Seasonal: before, during and after the season', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      app.clock.current = DateTime(2026, 9, 20, 9);
      await app.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
      await _launch(tester, app);
      expect(find.text(SetupLabels.seasonNotStarted), findsWidgets);
      expect(_filled(tester, 'Start Challenge').onPressed, isNull);
      await tapShown(tester, find.text('Review Setup'));
      expect(
        (await _filledShown(tester, 'Continue to Start')).onPressed,
        isNull,
      );
      // Straight to Confirm & Start: still refused.
      GoRouter.of(tester.element(find.byType(ReviewSetupScreen)))
          .push('/setup/confirm');
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmStartScreen), findsOneWidget);
      expect(_filled(tester, 'Confirm & Join Season').onPressed, isNull);
      expect(find.text('Day 1'), findsNothing, reason: 'no dates to start');
      await _shutDown(tester);

      app.clock.current = DateTime(2026, 10, 18, 9);
      await _launch(tester, app);
      expect(
        find.text(
          'The season is on Day 18 of 92. Join now and start on Day 18.',
        ),
        findsOneWidget,
      );
      await tapShown(tester, find.text('Start Challenge'));
      await tapShown(tester, find.text('Continue to Start'));
      expect(find.text('You join today on Day 18 of 92.'), findsOneWidget);
      expect(find.textContaining("Earlier days won't count"), findsOneWidget);
      expect(find.text('Thu 1 Oct 2026'), findsOneWidget);
      expect(find.text('Thu 31 Dec 2026'), findsOneWidget);
      await _shutDown(tester);

      app.clock.current = DateTime(2027, 1, 1, 9);
      await _launch(tester, app);
      expect(find.text(SetupLabels.seasonEnded), findsWidgets);
      expect(_filled(tester, 'Start Challenge').onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Review Setup'),
            )
            .onPressed,
        isNull,
      );
      await _stillSetup(app);
      await _shutDown(tester);
    });

    testWidgets('settings and history links open over the hub and come back; '
        'Focus Guard only where supported, Arc History only with history', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      await _launch(tester, app);
      expect(find.text('Arc History'), findsNothing);
      expect(find.text('Focus Guard'), findsNothing, reason: 'unsupported');
      for (final (label, screen) in [
        ('Reminders', ReminderSettingsScreen),
        ('Data & Backup', null),
        ('About NextRep', null),
      ]) {
        await tapShown(tester, find.text(label));
        expect(find.byType(SavedSetupScreen), findsNothing);
        if (screen != null) expect(find.byType(screen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(SavedSetupScreen), findsOneWidget, reason: label);
      }
      expect(app.scheduler.pending, isEmpty);
      await _shutDown(tester);

      // With a finished Arc and Focus Guard available.
      final returning = make(DateTime(2026, 7, 1));
      await runFirstArc(returning);
      await returning.winterArc.startNewArc(NewArcBaseline.reuseLast);
      await _launch(
        tester,
        returning,
        overrides: [
          focusGuardPlatformProvider.overrideWithValue(
            FakeFocusGuardPlatform(),
          ),
        ],
      );
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      expect(find.text('Focus Guard'), findsOneWidget);
      await tapShown(tester, find.text('Arc History'));
      expect(find.byType(ArcHistoryScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('Cancel setup: the same dialog; Keep Setup keeps it, Cancel '
        'Setup deletes only the draft', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      await _launch(tester, app);
      await tapShown(tester, find.text('Cancel setup'));
      expect(find.text('Cancel this setup?'), findsOneWidget);
      await tapShown(tester, find.text('Keep Setup'));
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      await _stillSetup(app);
      await tapShown(tester, find.text('Cancel setup'));
      await tapShown(tester, find.widgetWithText(FilledButton, 'Cancel Setup'));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(await app.sessions.listSessions(), isEmpty);
      await _shutDown(tester);
    });
  });

  group('Review Setup', () {
    testWidgets('shows goals, Minimum Day goals, clock times, Off and the '
        'reminders; Edit Setup and Back return where it came from', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      await app.winterArc.setHabitEnabled('sleep_before', enabled: true);
      await app.reminders.update(
        (p) => p.copyWith(
          dailyEnabled: true,
          dailyTime: const ReminderTime(7, 15),
        ),
      );
      await _launch(tester, app);
      await tapShown(tester, find.text('Review Setup'));
      expect(find.text('Rolling 92-Day Arc'), findsOneWidget);
      expect(find.text('Starts the day you confirm · 92 days'), findsOneWidget);
      expect(find.text('30 min · Min 10 min'), findsOneWidget);
      expect(find.text('Before 23:30'), findsOneWidget);
      expect(
        find.bySemanticsLabel('2. Water Intake. 8 glasses. Minimum 3 glasses.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Reminders: '),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'Reminders: Daily 07:15 · Reflection off · Hydration Coach off',
        ),
        findsOneWidget,
      );
      expect(find.text(SetupLabels.remindersWait), findsOneWidget);
      expect(app.scheduler.pending, isEmpty);

      // Opened from the hub: Back and Edit Setup.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      await tapShown(tester, find.text('Review Setup'));
      await tapShown(tester, find.text('Edit Setup'));
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      await _systemBack(tester);
      expect(find.byType(SavedSetupScreen), findsOneWidget);

      // Opened from the editor: Edit Setup goes back to it.
      await continueEditing(tester);
      await tapShown(tester, find.text('Review & Start'));
      await tapShown(tester, find.text('Edit Setup'));
      expect(find.byType(HabitSetupScreen), findsOneWidget);
      expect(find.byType(ReviewSetupScreen), findsNothing);
      await _stillSetup(app);
      await _shutDown(tester);
    });
  });

  group('Confirm & Start', () {
    Future<void> openConfirm(WidgetTester tester) async {
      await app.winterArc.beginSetup();
      _phone(tester);
      await _launch(tester, app);
      await tapShown(tester, find.text('Start Challenge'));
      await tapShown(tester, find.text('Continue to Start'));
      expect(find.byType(ConfirmStartScreen), findsOneWidget);
    }

    testWidgets('focus starts on the heading; Enter starts nothing; the two '
        'actions are 24 dp apart; Back returns to Review', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      await openConfirm(tester);
      final focus = FocusManager.instance.primaryFocus!;
      expect(
        find.descendant(
          of: find.byWidget(focus.context!.widget),
          matching: find.text(SetupLabels.confirmTitle),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmStartScreen), findsOneWidget);
      await _stillSetup(app);

      final start = tester.getRect(
        find.widgetWithText(FilledButton, 'Confirm & Start Challenge'),
      );
      final save = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Save for Later'),
      );
      expect(save.top - start.bottom, greaterThanOrEqualTo(24));
      expect(start.height, greaterThanOrEqualTo(48));
      expect(save.height, greaterThanOrEqualTo(48));
      expect(find.text(SetupLabels.rollingConsequence), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSetupScreen), findsOneWidget);
      await _stillSetup(app);
      await _shutDown(tester);
    });

    testWidgets('a double tap starts one Arc and opens one Today', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      await openConfirm(tester);
      final button = find.widgetWithText(
        FilledButton,
        'Confirm & Start Challenge',
      );
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
      final sessions = await app.sessions.listSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.status, WinterArcStatus.active);
      expect(
        await snapshotAll(app.db).then((t) => t['xp_transactions']),
        isEmpty,
      );
      // Back from Today doesn't lead to the setup screens.
      expect(find.byType(ConfirmStartScreen), findsNothing);
      expect(find.byType(SavedSetupScreen), findsNothing);
      await _shutDown(tester);
    });

    testWidgets('a storage failure keeps the setup: the message, no Today, '
        'and a retry starts it', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      await openConfirm(tester);
      await app.db.customStatement(
        'CREATE TRIGGER fail_start BEFORE UPDATE OF status ON '
        "winter_arc_sessions WHEN NEW.status = 'active' "
        "BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      final before = await snapshotAll(app.db);
      await tapShown(tester, find.text('Confirm & Start Challenge'));
      expect(find.text(SetupLabels.startFailed), findsOneWidget);
      expect(find.byType(ConfirmStartScreen), findsOneWidget);
      expect(find.byType(TodayScreen), findsNothing);
      expect(await snapshotAll(app.db), before);
      expect(
        _filled(tester, 'Confirm & Start Challenge').onPressed,
        isNotNull,
        reason: 'not left busy',
      );
      await app.db.customStatement('DROP TRIGGER fail_start');
      await tapShown(tester, find.text('Confirm & Start Challenge'));
      expect(find.byType(TodayScreen), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('midnight with the screen open moves Day 1 and Day 92; no '
        'start happens by itself', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      app.clock.current = DateTime(2026, 11, 2, 23, 59, 50);
      await openConfirm(tester);
      expect(find.text('Today, Mon 2 Nov 2026'), findsOneWidget);
      expect(find.text('Mon 1 Feb 2027'), findsOneWidget);
      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      expect(find.text('Today, Tue 3 Nov 2026'), findsOneWidget);
      expect(find.text('Tue 2 Feb 2027'), findsOneWidget);
      expect(find.text('Today, Mon 2 Nov 2026'), findsNothing);
      await _stillSetup(app);
      await tapShown(tester, find.text('Confirm & Start Challenge'));
      final arc = (await app.sessions.listSessions()).single;
      expect(arc.startDate, LocalDate(2026, 11, 3));
      await _shutDown(tester);
    });

    testWidgets('the date changed unseen (clock moved, no signal yet): '
        'nothing starts, the new dates are shown, then it starts on them', (
      tester,
    ) async {
      app = make(DateTime(2026, 11, 2, 9));
      await openConfirm(tester);
      expect(find.text('Today, Mon 2 Nov 2026'), findsOneWidget);
      // Forward a day without any timer or resume firing.
      app.clock.current = DateTime(2026, 11, 3, 9);
      await tapShown(tester, find.text('Confirm & Start Challenge'));
      expect(
        find.text(
          'The date has changed. Check the new dates, then confirm again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Today, Tue 3 Nov 2026'), findsOneWidget);
      await _stillSetup(app);
      // Backward, before the shown date, then a resume re-reads.
      app.clock.current = DateTime(2026, 11, 1, 9);
      _resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Today, Sun 1 Nov 2026'), findsOneWidget);
      await tapShown(tester, find.text('Confirm & Start Challenge'));
      expect(find.byType(TodayScreen), findsOneWidget);
      final arc = (await app.sessions.listSessions()).single;
      expect(arc.startDate, app.clock.today());
      await _shutDown(tester);
    });

    testWidgets('Seasonal at midnight: 30 Sep → 1 Oct opens; 31 Dec → 1 Jan '
        'closes, from the open screen', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      app.clock.current = DateTime(2026, 9, 30, 23, 59, 50);
      await app.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
      _phone(tester);
      await _launch(tester, app);
      await tapShown(tester, find.text('Review Setup'));
      GoRouter.of(tester.element(find.byType(ReviewSetupScreen)))
          .push('/setup/confirm');
      await tester.pumpAndSettle();
      expect(_filled(tester, 'Confirm & Join Season').onPressed, isNull);
      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      expect(_filled(tester, 'Confirm & Join Season').onPressed, isNotNull);
      expect(find.text('You join today on Day 1 of 92.'), findsOneWidget);
      expect(find.textContaining("Earlier days won't count"), findsNothing);
      await _shutDown(tester);

      app.clock.current = DateTime(2026, 12, 31, 23, 59, 50);
      await _launch(tester, app);
      await tapShown(tester, find.text('Start Challenge'));
      await tapShown(tester, find.text('Continue to Start'));
      expect(find.text('You join today on Day 92 of 92.'), findsOneWidget);
      expect(_filled(tester, 'Confirm & Join Season').onPressed, isNotNull);
      await _stayOpen(tester, app.clock, const Duration(seconds: 15));
      expect(_filled(tester, 'Confirm & Join Season').onPressed, isNull);
      expect(find.text(SetupLabels.seasonEnded), findsOneWidget);
      await _stillSetup(app);
      await _shutDown(tester);
    });
  });

  group('routes', () {
    testWidgets('an active Arc leaves every setup route for Today; an '
        'unknown setup route is the safe page', (tester) async {
      app = make(DateTime(2026, 11, 2, 9));
      _phone(tester);
      await app.winterArc.beginSetup();
      await _launch(tester, app);
      final router = GoRouter.of(tester.element(find.byType(SavedSetupScreen)));
      router.go('/setup/nope');
      await tester.pumpAndSettle();
      expect(find.byType(UnknownPageScreen), findsOneWidget);
      await _shutDown(tester);

      await app.winterArc.startWinterArc();
      await _launch(tester, app);
      expect(find.byType(TodayScreen), findsOneWidget);
      final active = GoRouter.of(tester.element(find.byType(TodayScreen)));
      for (final location in [
        '/setup',
        '/setup/saved',
        '/setup/review',
        '/setup/confirm',
      ]) {
        active.go(location);
        await tester.pumpAndSettle();
        expect(find.byType(TodayScreen), findsOneWidget, reason: location);
        expect(find.byType(ConfirmStartScreen), findsNothing);
      }
      expect((await app.sessions.listSessions()), hasLength(1));
      await _shutDown(tester);
    });
  });
}

/// Review & Start from Habit Setup, stopping on Review Setup.
Future<void> startFromSetupReviewOnly(WidgetTester tester) =>
    tapShown(tester, find.text('Review & Start'));
