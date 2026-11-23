import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/habit/night_time.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/features/today/widgets/time_before_tile.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/sound_app.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// When a habit action sounds (ARC_CONTROL_SPEC § 8.1, N1–N4; addendum § L5
/// "W"): through the real Today screen, its real commit and ledger, and a
/// recording player. Each step moves the monotonic clock past the throttle
/// unless the step is about the throttle.
void main() {
  late FakeSoundPlayer player;
  late FakeMonotonic monotonic;

  setUp(() {
    player = FakeSoundPlayer();
    monotonic = FakeMonotonic();
  });

  /// Lets every throttle window close.
  void later() => monotonic.advance(const Duration(seconds: 4));

  Future<void> setTime(WidgetTester tester, int hour, int minute) async {
    await reveal(tester, find.byType(TimeBeforeHabitTile));
    tester
        .widget<TimeBeforeHabitTile>(find.byType(TimeBeforeHabitTile))
        .onSetTime(NightTime(hour, minute));
    await tester.pumpAndSettle();
  }

  Future<void> clearTime(WidgetTester tester) async {
    await reveal(tester, find.byType(TimeBeforeHabitTile));
    tester
        .widget<TimeBeforeHabitTile>(find.byType(TimeBeforeHabitTile))
        .onClear();
    await tester.pumpAndSettle();
  }

  testWidgets('every kind of completion: the habit sound only on the step '
      'that completes it; the Perfect Day sound alone on the last', (
    tester,
  ) async {
    await phoneSize(tester);
    final haptics = recordHaptics(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    expect(player.plays, isEmpty, reason: 'opening Today plays nothing');
    expect(player.prepares, 1, reason: 'Today loads the sounds');

    // Binary: one tap completes it.
    later();
    await tapTooltip(tester, 'Complete Stretch');
    expect(player.plays, [(SoundTheme.iceCrystal, CompletionSound.habit)]);

    // Count: silent below the target, a sound on the step that reaches it.
    later();
    await tapTooltip(tester, 'Add to Glasses');
    later();
    await tapTooltip(tester, 'Add to Glasses');
    expect(player.plays, hasLength(1));
    later();
    await tapTooltip(tester, 'Add to Glasses');
    expect(player.sounds, [CompletionSound.habit, CompletionSound.habit]);

    // Duration: 5 of 10 min is silent, reaching 10 sounds.
    later();
    await tapTooltip(tester, 'Add to Focus');
    expect(player.plays, hasLength(2));
    later();
    await tapTooltip(tester, 'Add to Focus');
    expect(player.plays, hasLength(3));

    // Clock time after the goal: logged, not complete, silent.
    later();
    await setTime(tester, 23, 30);
    expect(find.textContaining('after the goal'), findsWidgets);
    expect(player.plays, hasLength(3));

    // At the goal: it completes the last habit, so today is a Perfect Day:
    // exactly one event, the Perfect Day sound, no habit sound.
    later();
    await setTime(tester, 23, 0);
    expect(player.sounds, [
      CompletionSound.habit,
      CompletionSound.habit,
      CompletionSound.habit,
      CompletionSound.perfectDay,
    ]);
    final today = await app.tracking.today();
    expect(today.completion.completed, 4);

    // Haptics unchanged: a light impact per habit completion; Perfect Day's
    // own haptic plays with its card, not the habit one.
    await clearCelebrations(tester);
    expect(
      haptics.where((h) => h == 'HapticFeedbackType.lightImpact').length,
      greaterThanOrEqualTo(3),
    );
    expect(player.plays, hasLength(4), reason: 'celebrations add no sound');
    await shutDown(tester);
  });

  testWidgets('reversals are silent; a restored completion sounds again, '
      'subject to the 3 s per-habit throttle', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();

    later();
    await tapTooltip(tester, 'Complete Stretch');
    expect(player.plays, hasLength(1));

    // Undo, then complete again within 3 s: both silent.
    monotonic.advance(const Duration(milliseconds: 800));
    await tapTooltip(tester, 'Undo Stretch');
    monotonic.advance(const Duration(milliseconds: 800));
    await tapTooltip(tester, 'Complete Stretch');
    expect(player.plays, hasLength(1));
    expect((await app.tracking.today()).completion.completed, 1);

    // Undo and redo after the window: the restored completion sounds.
    later();
    await tapTooltip(tester, 'Undo Stretch');
    later();
    await tapTooltip(tester, 'Complete Stretch');
    expect(player.plays, hasLength(2));

    // Decrement below a count target: silent; back up to it: a sound.
    for (var i = 0; i < 3; i++) {
      later();
      await tapTooltip(tester, 'Add to Glasses');
    }
    expect(player.plays, hasLength(3));
    later();
    await tapTooltip(tester, 'Decrease Glasses');
    expect(player.plays, hasLength(3));
    later();
    await tapTooltip(tester, 'Add to Glasses');
    expect(player.plays, hasLength(4));

    // Clearing a goal-met time: silent.
    later();
    await setTime(tester, 22, 15);
    expect(player.plays, hasLength(5));
    later();
    await clearTime(tester);
    expect(player.plays, hasLength(5));
    expect(
      player.sounds.where((s) => s == CompletionSound.perfectDay),
      isEmpty,
    );
    await shutDown(tester);
  });

  testWidgets('the snackbar Undo of a completion is silent', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    later();
    await tapTooltip(tester, 'Complete Stretch');
    later();
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect((await app.tracking.today()).completion.completed, 0);
    expect(player.plays, hasLength(1));
    await shutDown(tester);
  });

  testWidgets('a clock-time Undo that restores a goal-met time is a '
      'restored completion: the habit sound, after the window', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    later();
    await setTime(tester, 22, 15); // goal met: a sound
    later();
    await setTime(tester, 23, 30); // after the goal: marked not done
    expect(player.plays, hasLength(1));
    expect(find.text('Lights Out marked not done'), findsOneWidget);
    later();
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect((await app.tracking.today()).completion.completed, 1);
    expect(player.sounds, [CompletionSound.habit, CompletionSound.habit]);
    await shutDown(tester);
  });

  testWidgets('rapid taps: at most one sound per window, never queued', (
    tester,
  ) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    later();
    // Stretch, then Glasses to its target, all inside one 500 ms window.
    await reveal(tester, find.byTooltip('Complete Stretch'));
    await tester.tap(find.byTooltip('Complete Stretch'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Add to Glasses'));
      monotonic.advance(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
    final today = await app.tracking.today();
    expect(today.completion.completed, 2, reason: 'every tap was saved');
    expect(player.plays, hasLength(1));
    // Nothing turns up afterwards.
    later();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(player.plays, hasLength(1));
    await shutDown(tester);
  });

  testWidgets('Minimum Day: switching is silent, completing a habit on it '
      'sounds, returning to full targets is silent', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    // Two of 3 glasses and 5 of 10 min: above both minimums, so the switch
    // completes Glasses and Focus.
    final ids = {
      for (final e in (await app.tracking.today()).entries)
        e.habit.title: e.habit.id,
    };
    await completeHabit(app, ids['Stretch']!);
    await app.tracking.perform(
      habitId: ids['Glasses']!,
      action: HabitAction.increment,
      date: app.clock.today(),
    );
    await app.tracking.perform(
      habitId: ids['Glasses']!,
      action: HabitAction.increment,
      date: app.clock.today(),
    );
    await app.tracking.perform(
      habitId: ids['Focus']!,
      action: HabitAction.increment,
      date: app.clock.today(),
    );
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();

    Future<void> switchToMinimum() async {
      later();
      await reveal(tester, find.text('Having a rough day?'));
      await tester.tap(find.text('Having a rough day?'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Switch to Minimum Day'));
      await tester.tap(find.text('Switch to Minimum Day'));
      await tester.pumpAndSettle();
      expect(find.text('Minimum Day activated'), findsOneWidget);
    }

    // Switching completes Glasses and Focus: silent.
    await switchToMinimum();
    expect((await app.tracking.today()).completion.completed, 3);
    expect(player.plays, isEmpty);

    // Back to full targets (un-completes them): silent.
    later();
    await reveal(
      tester,
      find.widgetWithText(TextButton, 'Return to full targets'),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Return to full targets'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Return to full targets'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Back to full targets'), findsOneWidget);
    expect((await app.tracking.today()).completion.completed, 1);
    expect(player.plays, isEmpty);

    // Minimum Day again (silent), then the last habit reaches its goal. A
    // completed Minimum Day is not a Perfect Day: the habit sound, no
    // special sound (spec § 8.1).
    monotonic.advance(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await switchToMinimum();
    expect(player.plays, isEmpty);
    later();
    await setTime(tester, 22, 0);
    expect((await app.tracking.today()).completion.completed, 4);
    expect(player.sounds, [CompletionSound.habit]);
    await shutDown(tester);
  });

  testWidgets('a completion on a Minimum Day that is not the last plays the '
      'habit sound', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await app.tracking.activateMinimumDay(date: app.clock.today());
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    expect(player.plays, isEmpty);
    later();
    await tapTooltip(tester, 'Add to Glasses'); // minimum 1
    expect(player.sounds, [CompletionSound.habit]);
    await shutDown(tester);
  });

  testWidgets('sounds off: a whole Perfect Day plays nothing, and the '
      'haptics are unchanged', (tester) async {
    await phoneSize(tester);
    final haptics = recordHaptics(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    await DriftFeedbackPreferencesRepository(app.db).save(
      const FeedbackPreferences(
        soundsEnabled: false,
        soundTheme: SoundTheme.warmEmber,
      ),
      at: app.clock.now(),
    );
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();

    later();
    await tapTooltip(tester, 'Complete Stretch');
    for (var i = 0; i < 3; i++) {
      later();
      await tapTooltip(tester, 'Add to Glasses');
    }
    for (var i = 0; i < 2; i++) {
      later();
      await tapTooltip(tester, 'Add to Focus');
    }
    later();
    await setTime(tester, 21, 30);
    await clearCelebrations(tester);
    expect((await app.tracking.today()).completion.completed, 4);
    expect(player.plays, isEmpty);
    expect(player.prepares, 0, reason: 'nothing is even loaded');
    expect(
      haptics.where((h) => h == 'HapticFeedbackType.lightImpact').length,
      greaterThanOrEqualTo(3),
    );
    await shutDown(tester);
  });

  testWidgets('launching, refreshing and crossing midnight on completed '
      'habits play nothing', (tester) async {
    await phoneSize(tester);
    final app = await fourKindsArc();
    addTearDown(app.db.close);
    // A Perfect Day, already stored.
    for (final entry in (await app.tracking.today()).entries) {
      if (entry.habit.type.isClockTime) {
        await app.tracking.perform(
          habitId: entry.habit.id,
          action: HabitAction.setTime,
          date: app.clock.today(),
          time: NightTime(22, 0),
        );
      } else {
        await completeHabit(app, entry.habit.id);
      }
    }
    await app.achievements.reconcile();
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await clearCelebrations(tester);

    // Resume (Today refreshes) and a midnight rollover.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    app.clock.current = DateTime(2026, 10, 5, 0, 1);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect((await app.tracking.today()).date, app.clock.today());
    expect(player.plays, isEmpty);
    await shutDown(tester);
  });
}
