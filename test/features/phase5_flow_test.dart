import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/insights/insights_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';

Widget _app(
  AppDatabase db,
  FakeClock clock, {
  FakeBackupFiles? files,
  FakeReminderScheduler? scheduler,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    backupFilesProvider.overrideWithValue(files ?? FakeBackupFiles()),
    if (scheduler != null)
      reminderSchedulerProvider.overrideWithValue(scheduler),
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

Future<void> _openTab(WidgetTester tester, String label) async {
  await clearCelebrations(tester);
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// Arc 1 completed (see [runFirstArc]); the clock is on 1 Oct 2026.
Future<TestApp> _completedArc({FakeReminderScheduler? scheduler}) async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 7, 1)),
    scheduler: scheduler,
  );
  await runFirstArc(app);
  return app;
}

/// Arc 1 completed and Arc 2 running since 2 Oct, with a reflection.
Future<TestApp> _secondArcRunning({FakeReminderScheduler? scheduler}) async {
  final app = await _completedArc(scheduler: scheduler);
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  app.clock.current = DateTime(2026, 10, 2, 20);
  final arc2 = await app.winterArc.startWinterArc();
  await completeAll(app);
  await app.reflections.save(
    sessionId: arc2.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.excellent, win: 'Secret win'),
  );
  await app.achievements.reconcile();
  return app;
}

Future<void> _openDataBackupFromHistory(WidgetTester tester) async {
  await _openTab(tester, 'History');
  await _tap(tester, find.byTooltip('Data & Backup'));
  expect(find.byType(DataBackupScreen), findsOneWidget);
}

void main() {
  testWidgets('export: privacy warning first, then the system save dialog '
      'gets a .nextrep file', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);
    final files = FakeBackupFiles();

    await tester.pumpWidget(_app(seeded.db, seeded.clock, files: files));
    await tester.pumpAndSettle();
    await _openDataBackupFromHistory(tester);
    expect(find.text('DATA & BACKUP'), findsOneWidget);
    expect(
      find.text(
        'Backups are stored wherever you choose. NextRep does not upload '
        'them.',
      ),
      findsOneWidget,
    );

    await _tap(tester, find.text('Export Backup'));
    expect(
      find.textContaining(
        'This backup contains your private NextRep history and '
        'reflections. Store it somewhere you trust.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('The file is not encrypted'), findsOneWidget);
    // Cancel: nothing is written.
    await _tap(tester, _button('Cancel'));
    expect(files.saved, isEmpty);

    await _tap(tester, find.text('Export Backup'));
    await _tap(tester, _button('Choose Location'));
    expect(files.saved, hasLength(1));
    final (name, bytes) = files.saved.single;
    expect(name, 'nextrep-backup-2026-10-02.nextrep');
    expect(BackupCodec.decode(bytes).data.arcs, hasLength(2));
    expect(find.text('Backup saved.'), findsOneWidget);

    // A cancelled save dialog says nothing.
    files.saveAccepted = false;
    await tester.pump(const Duration(seconds: 5));
    await _tap(tester, find.text('Export Backup'));
    await _tap(tester, _button('Choose Location'));
    expect(files.saved, hasLength(1));
    expect(find.text('Backup saved.'), findsNothing);

    await _shutDown(tester);
  });

  testWidgets('restore: preview (no reflection text), replace confirmation, '
      'then the app reloads on the restored data with reminders off', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final source = await _secondArcRunning();
    addTearDown(source.db.close);
    final bytes = (await source.backup.export()).bytes;

    // This device has one different arc, with reminders on.
    final scheduler = FakeReminderScheduler(granted: true);
    final target = TestApp(
      memoryDatabase(),
      FakeClock(source.clock.now()),
      scheduler: scheduler,
    );
    addTearDown(target.db.close);
    await target.winterArc.beginSetup();
    await target.winterArc.startWinterArc();
    await target.reminders.update(
      (p) => p.copyWith(dailyEnabled: true, reflectionEnabled: true),
    );
    expect(scheduler.pending, isNotEmpty);
    final files = FakeBackupFiles(toPick: bytes);

    await tester.pumpWidget(
      _app(target.db, target.clock, files: files, scheduler: scheduler),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 XP'), findsOneWidget); // this device's arc
    await _openTab(tester, 'Journal'); // build every tab before restoring
    await _openTab(tester, 'Journey');
    await _openTab(tester, 'Today');
    await _openDataBackupFromHistory(tester);
    await _tap(tester, find.text('Restore Backup'));

    // Preview.
    expect(find.text('Restore Backup'), findsNWidgets(2)); // card + dialog
    expect(find.bySemanticsLabel('Arcs: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Completed Arcs: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Reflections: 2'), findsOneWidget);
    expect(find.textContaining('Active Arc'), findsOneWidget);
    expect(
      find.textContaining(
        'This will replace the NextRep data currently stored on this device.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Secret win'), findsNothing);
    expect(find.textContaining('Showed up'), findsNothing);

    // Cancel at the preview changes nothing.
    final before = await dumpOf(target.db);
    await _tap(tester, _button('Cancel'));
    expect(await dumpOf(target.db), before);

    await _tap(tester, find.text('Restore Backup'));
    await _tap(tester, _button('Restore'));
    // A second confirmation, since this device has data.
    expect(find.text('Replace current data?'), findsOneWidget);
    expect(find.textContaining('This device has 1 Arc'), findsOneWidget);
    await _tap(tester, _button('Replace Data'));
    await tester.pumpAndSettle();

    // Reloaded on the restored data: Arc 2 is running again.
    expect(find.byType(DataBackupScreen), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    // Today shows the restored arc, not what was on screen before.
    expect(find.text('75 XP'), findsOneWidget);
    expect(find.text('0 XP'), findsNothing);
    expect(find.textContaining('Backup restored.'), findsOneWidget);
    final prefs = await target.reminderStore.load();
    expect(prefs.anyEnabled, isFalse);
    expect(scheduler.pending, isEmpty);

    await _openTab(tester, 'Journal');
    expect(find.text('Secret win'), findsOneWidget);
    await _openTab(tester, 'History');
    expect(find.text('COMPLETED'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('a damaged backup is refused and nothing changes', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final source = await _secondArcRunning();
    addTearDown(source.db.close);
    final damaged = Uint8List.fromList((await source.backup.export()).bytes);
    damaged[damaged.length - 20] ^= 0x04;
    final before = await dumpOf(source.db);

    await tester.pumpWidget(
      _app(source.db, source.clock, files: FakeBackupFiles(toPick: damaged)),
    );
    await tester.pumpAndSettle();
    await _openDataBackupFromHistory(tester);
    await _tap(tester, find.text('Restore Backup'));
    expect(find.text("Can't use this file"), findsOneWidget);
    expect(find.textContaining('Nothing was changed.'), findsOneWidget);
    await _tap(tester, _button('OK'));
    expect(await dumpOf(source.db), before);

    // Picking nothing does nothing.
    await tester.pumpWidget(
      _app(source.db, source.clock, files: FakeBackupFiles()),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Restore Backup'));
    expect(find.byType(AlertDialog), findsNothing);
    await _shutDown(tester);
  });

  testWidgets('a new device restores from onboarding with one confirmation', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final source = await _completedArc();
    addTearDown(source.db.close);
    final bytes = (await source.backup.export()).bytes;
    final db = memoryDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      _app(db, source.clock, files: FakeBackupFiles(toPick: bytes)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await _tap(tester, find.text('Restore from a backup'));
    await _tap(tester, find.text('Restore Backup'));
    await _tap(tester, _button('Restore'));
    expect(find.text('Replace current data?'), findsNothing);
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('delete a historical arc from its summary: cancel keeps it, '
      'Delete Arc removes it and returns to History', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'History');
    await tester.scrollUntilVisible(
      find.text('COMPLETED'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await _tap(tester, find.text('COMPLETED'));
    expect(find.byType(SummaryScreen), findsOneWidget);

    await _tap(tester, find.byTooltip('Arc options'));
    await _tap(tester, find.text('Delete Arc'));
    expect(find.text('Delete this Winter Arc?'), findsOneWidget);
    expect(find.text('1 Jul – 30 Sep 2026'), findsWidgets);
    expect(find.text('135 XP'), findsOneWidget);
    expect(find.text('1 Perfect Day'), findsOneWidget);
    expect(
      find.text('This cannot be undone unless you have a backup.'),
      findsOneWidget,
    );
    await _tap(tester, _button('Cancel'));
    expect(await seeded.sessions.sessionById(1), isNotNull);

    await _tap(tester, find.byTooltip('Arc options'));
    await _tap(tester, find.text('Delete Arc'));
    await _tap(tester, _button('Delete Arc'));
    expect(await seeded.sessions.sessionById(1), isNull);
    expect(find.byType(ArcHistoryScreen), findsOneWidget);
    expect(find.text('COMPLETED'), findsNothing);
    expect(find.text('ACTIVE'), findsOneWidget);
    // Arc 2 is untouched.
    await _openTab(tester, 'Journal');
    expect(find.text('Secret win'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('deleting the only arc from its home summary returns to '
      'onboarding', (tester) async {
    await _setPhoneSize(tester);
    final seeded = await _completedArc();
    addTearDown(seeded.db.close);

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    await _tap(tester, find.byTooltip('Arc options'));
    await _tap(tester, find.text('Delete Arc'));
    await _tap(tester, _button('Delete Arc'));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(await seeded.sessions.listSessions(), isEmpty);
    await _shutDown(tester);
  });

  testWidgets('cancel setup after a completed arc returns to its summary', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final seeded = await _completedArc();
    addTearDown(seeded.db.close);
    await seeded.winterArc.startNewArc(NewArcBaseline.fresh);
    final arc1 = await snapshotOf(seeded.db, 1);

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    await _tapVisible(tester, find.text('Cancel setup'));
    expect(find.text('Cancel this setup?'), findsOneWidget);
    expect(
      find.text('Your previous completed Arcs will remain safe.'),
      findsOneWidget,
    );
    await _tap(tester, _button('Keep Setup'));
    expect(find.byType(HabitSetupScreen), findsOneWidget);

    await _tapVisible(tester, find.text('Cancel setup'));
    await _tap(tester, _button('Cancel Setup'));
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Start New Arc'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start New Arc'), findsOneWidget);
    expect(await seeded.sessions.currentSession(), isNull);
    expect(await snapshotOf(seeded.db, 1), arc1);
    await _shutDown(tester);
  });

  testWidgets('cancelling a first-ever setup returns to onboarding', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 4, 9));

    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _tap(tester, find.text("Let's Begin"));
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    await _tapVisible(tester, find.text('Cancel setup'));
    expect(find.textContaining('start again'), findsOneWidget);
    await _tap(tester, _button('Cancel Setup'));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('Insights from History: overall, habits and moods', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final seeded = await _secondArcRunning();
    addTearDown(seeded.db.close);

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openTab(tester, 'History');
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Insights'));
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.text('ACROSS YOUR ARCS'), findsOneWidget);
    expect(find.bySemanticsLabel('Arcs: 1 done · Day 1 now'), findsOneWidget);
    expect(find.bySemanticsLabel('Days climbed: 93'), findsOneWidget);
    // Arc 1: Day 1 perfect, Day 3 a full Minimum Day. Arc 2: Day 1 perfect.
    expect(
      find.bySemanticsLabel('Consistency: 3%, 3 of 93 days full'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Perfect Days: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Minimum Days completed: 1'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('HABITS'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Workout was renamed "Strength" in Arc 1 and reused: one lineage.
    await tester.scrollUntilVisible(
      find.text('Strength'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Workout'), findsNothing);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Excellent: 1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.bySemanticsLabel('Good: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Rough: 0'), findsOneWidget);
    expect(find.textContaining('Secret win'), findsNothing);
    await _shutDown(tester);
  });

  testWidgets('Insights before any started arc shows an empty state', (
    tester,
  ) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 4))),
          ambientMotionProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: buildWinterTheme(),
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Insights appear once your first Winter Arc has started.'),
      findsOneWidget,
    );
    await _shutDown(tester);
  });

  testWidgets('Data & Backup and Insights fit at 2x text', (tester) async {
    await _setPhoneSize(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final seeded = await _secondArcRunning(
      scheduler: FakeReminderScheduler(granted: true),
    );
    addTearDown(seeded.db.close);
    await seeded.reminders.update(
      (p) => p.copyWith(dailyTime: const ReminderTime(7, 0)),
    );

    await tester.pumpWidget(_app(seeded.db, seeded.clock));
    await tester.pumpAndSettle();
    await _openDataBackupFromHistory(tester);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Insights'));
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await _shutDown(tester);
  });
}
