import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/confirm_start_screen.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/habit_setup/review_setup_screen.dart';
import 'package:nextrep/features/habit_setup/saved_setup_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';
import '../support/ui.dart';

/// Phase 12D read-only gate (task § 37, spec § 4.2 "Save for Later writes
/// nothing", § 9.3–9.4 "Reads only"): with a populated database (a
/// completed Arc with progress, XP, day modes, revisions, unlocks and a
/// reflection; a reused, reordered setup beside it; reminder preferences),
/// every row of every table is captured. Then the hub, Review Setup (and
/// its scrolling), Confirm & Start, Back, Save for Later, the editor and
/// the settings pages are opened and left, the app is resumed and kept open
/// past midnight. After every step every table must be exactly as
/// captured, and nothing may be scheduled. All data is synthetic.

void main() {
  testWidgets('every table is identical after every read-only setup step', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final app = TestApp(
      memoryDatabase(),
      FakeClock(DateTime(2026, 7, 1)),
      scheduler: FakeReminderScheduler(granted: true),
    );
    addTearDown(app.db.close);
    await runFirstArc(app); // leaves the clock on 1 Oct 2026, 09:00
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    await app.winterArc.reorderSetupHabits(
      [for (final h in await app.winterArc.setupHabits()) h.id].reversed
          .toList(),
    );
    await app.reminders.update(
      (p) => p.copyWith(
        dailyEnabled: true,
        dailyTime: const ReminderTime(7, 30),
        reflectionEnabled: true,
      ),
    );
    app.clock.current = DateTime(2026, 10, 6, 23, 59, 30);
    final scheduledBefore = app.scheduler.pending;
    expect(scheduledBefore, isEmpty, reason: 'no Arc reminder for a setup');

    final all = await snapshotAll(app.db);
    for (final table in [
      'winter_arc_sessions',
      'habits',
      'habit_revisions',
      'daily_habit_progress_entries',
      'day_modes',
      'xp_transactions',
      'achievement_unlocks',
      'daily_reflections',
      'reminder_preferences',
    ]) {
      expect(all[table], isNotEmpty, reason: 'populated: $table');
    }

    // The "saved" snackbar sits over the bottom of the screen until it
    // times out; a user would wait for it too.
    Future<void> letSnackBarGo() async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    }

    Future<void> unchanged(String step) async {
      expect(await snapshotAll(app.db), all, reason: step);
      expect(app.scheduler.pending, isEmpty, reason: step);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(app.db),
          clockProvider.overrideWithValue(app.clock),
          ambientMotionProvider.overrideWithValue(false),
          reminderSchedulerProvider.overrideWithValue(app.scheduler),
          focusGuardPlatformProvider.overrideWithValue(
            FakeFocusGuardPlatform(access: UsageAccess.notGranted),
          ),
        ],
        retry: (_, _) => null,
        child: const NextRepApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    await unchanged('launch into the hub');

    await tapShown(tester, find.text('Review Setup'));
    expect(find.byType(ReviewSetupScreen), findsOneWidget);
    await unchanged('open Review Setup');
    await showIn(tester, find.text('Save for Later'));
    await showIn(tester, find.text('Review Setup'));
    await unchanged('scroll Review Setup');

    await tapShown(tester, find.text('Continue to Start'));
    expect(find.byType(ConfirmStartScreen), findsOneWidget);
    await unchanged('open Confirm & Start');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ReviewSetupScreen), findsOneWidget);
    await unchanged('Back from Confirm & Start');

    await tapShown(tester, find.text('Continue to Start'));
    await tapShown(tester, find.text('Save for Later'));
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    await unchanged('Save for Later from Confirm & Start');
    await letSnackBarGo();
    await tapShown(tester, find.text('Review Setup'));
    await tapShown(tester, find.text('Save for Later'));
    await unchanged('Save for Later from Review Setup');
    await letSnackBarGo();

    await tapShown(tester, find.text('Continue Editing'));
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    await unchanged('open Habit Setup');
    await tapShown(tester, find.text('Save for Later'));
    expect(find.byType(SavedSetupScreen), findsOneWidget);
    await unchanged('Save for Later from Habit Setup');
    await letSnackBarGo();

    for (final link in [
      'Reminders',
      'Data & Backup',
      'Focus Guard',
      'About NextRep',
    ]) {
      await tapShown(tester, find.text(link));
      expect(find.byType(SavedSetupScreen), findsNothing, reason: link);
      await unchanged('open $link');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SavedSetupScreen), findsOneWidget, reason: link);
      await unchanged('back from $link');
    }

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
    await tester.pumpAndSettle();
    await unchanged('resume on the hub');

    // Review and Confirm open across midnight: re-read, nothing written.
    await tapShown(tester, find.text('Start Challenge'));
    await tapShown(tester, find.text('Continue to Start'));
    app.clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Today, Wed 7 Oct 2026'), findsOneWidget);
    await unchanged('midnight on Confirm & Start');
    expect(
      (await app.sessions.listSessions()).where(
        (s) => s.status == WinterArcStatus.active,
      ),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
