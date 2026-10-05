import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';
import 'package:nextrep/features/insights/insights_screen.dart';
import 'package:nextrep/features/journal/journal_screen.dart';
import 'package:nextrep/features/journey/widgets/journey_marker.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../test/support/arcs.dart';
import '../test/support/fakes.dart';
import '../test/support/ui.dart';

/// Phase 7 release smoke, on a device with a real SQLite file and an
/// injected clock (5 Oct 2026, never the device clock): a fresh install
/// through to a restored backup and a cold reload.
///
/// Fresh app → Rolling → setup (a custom habit, Sleep Before Target on)
/// → Start → log habits → Journey → reflection → Insights → export (in-
/// memory file adapter) → change data → restore → reload from the file.
///
/// The seasonal late-join path, the bedtime picker and backup format 1
/// are covered on device by phase6_smoke_test.dart.
///
/// `flutter test integration_test -d <device> --no-uninstall`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app(AppDatabase db, FakeClock clock, FakeBackupFiles files) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          ambientMotionProvider.overrideWithValue(false),
          backupFilesProvider.overrideWithValue(files),
        ],
        retry: (_, _) => null,
        child: const NextRepApp(),
      );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await clearCelebrations(tester);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(
    WidgetTester tester,
    Finder finder, {
    bool last = false,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: last
          ? find.byType(Scrollable).last
          : find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  testWidgets('fresh install to restored backup and a cold reload', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it7_');
    final file = File('${dir.path}/nextrep.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    final clock = FakeClock(DateTime(2026, 10, 5, 9));
    final files = FakeBackupFiles();

    // 1. A fresh install opens on onboarding, with nothing stored.
    await tester.pumpWidget(app(db, clock, files));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Private by design'), findsOneWidget);
    expect(await TestApp(db, clock).sessions.listSessions(), isEmpty);

    // 2. Rolling.
    await tap(tester, find.text("Let's Begin"));
    await tap(tester, find.text('Rolling 92-Day Arc'));
    expect(find.byType(HabitSetupScreen), findsOneWidget);

    // 3. A custom count habit.
    await scrollTo(tester, find.text('Add Habit'));
    await tap(tester, find.text('Add Habit'));
    await scrollTo(tester, find.text('Create your own'), last: true);
    await tap(tester, find.text('Create your own'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Pages');
    await tap(tester, find.widgetWithText(ChoiceChip, 'Count'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Unit (e.g. pages, glasses)'),
      'pages',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add habit'));
    await tap(tester, find.text('Add habit'));
    expect(find.text('Pages added'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 4. Sleep Before Target, off by default, turned on.
    final sleepTile = find.widgetWithText(
      HabitToggleTile,
      'Sleep Before Target',
    );
    await scrollTo(tester, sleepTile);
    await tap(
      tester,
      find.descendant(of: sleepTile, matching: find.byType(Switch)),
    );

    // 5. Start: Today, Day 1.
    await tap(tester, find.text('Start Winter Arc'));
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);

    // 6. Log habits: a done / not done habit, a count step and last
    // night's bedtime (the picker itself is covered by the Phase 6 smoke).
    await scrollTo(tester, find.byTooltip('Complete No Junk Food'));
    await tap(tester, find.byTooltip('Complete No Junk Food'));
    expect(find.text('No Junk Food complete · +15 XP'), findsOneWidget);
    await scrollTo(tester, find.byTooltip('Add to Pages'));
    await tap(tester, find.byTooltip('Add to Pages'));
    final services = TestApp(db, clock);
    await services.tracking.perform(
      habitId: 'sleep_before',
      action: HabitAction.setTime,
      date: clock.today(),
      time: NightTime(23, 5),
    );
    final today = await services.tracking.today();
    final pages = today.entries.singleWhere((e) => e.habit.title == 'Pages');
    expect(pages.progress.currentValue, 1);
    expect(today.totalXp, 30); // No Junk Food + Sleep Before Target

    // 7. Journey: today's day says where it stands.
    await openTab(tester, 'Journey');
    expect(find.byType(JourneyMarker), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp(r'^Day 1\. Today\. \d+ percent complete')),
      findsOneWidget,
    );

    // 8. A reflection.
    await openTab(tester, 'Journal');
    expect(find.byType(JournalScreen), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Mood: Good'));
    await tester.ensureVisible(find.text('Save Reflection'));
    await tap(tester, find.text('Save Reflection'));
    final arc = (await services.sessions.currentSession())!;
    expect(
      (await services.reflections.journal()).todayEntry?.mood?.name,
      'good',
      reason: 'saved for ${arc.id}',
    );

    // 9. Insights.
    await openTab(tester, 'History');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Insights'));
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Days climbed: 1'), findsOneWidget);
    await tap(tester, find.byType(BackButton));

    // 10. Export a backup (format 2) through the file adapter.
    await tap(tester, find.byTooltip('Data & Backup'));
    expect(
      find.text(
        'A backup includes your reflections and is not encrypted. The '
        'backup includes a checksum so accidental corruption can be '
        'detected.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.text('Export Backup'));
    await tap(tester, button('Choose Location'));
    expect(find.text('Backup saved.'), findsOneWidget);
    final (name, bytes) = files.saved.single;
    expect(name, endsWith('.nextrep'));
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    expect(json['formatVersion'], BackupFormat.formatVersion);
    final backup = BackupValidator.validate(BackupCodec.decode(bytes));
    expect(backup.summary.reflectionCount, 1);
    final exported = await dumpOf(db, renumberSessions: true);

    // 11. Change the data, then restore the backup.
    await completeHabit(services, 'workout');
    expect(await dumpOf(db, renumberSessions: true), isNot(exported));
    files.toPick = bytes;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Restore Backup'));
    await tap(tester, button('Restore'));
    await tap(tester, button('Replace Data'));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    final restored = await dumpOf(db, renumberSessions: true);
    for (final table in exported.keys.where((t) => t != 'reminders')) {
      expect(restored[table], exported[table], reason: table);
    }

    // 12. Cold reload from the same file: the restored state persisted.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db, clock, files));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    final reloaded = TestApp(db, clock);
    final current = (await reloaded.sessions.currentSession())!;
    expect(current.kind, ArcKind.rolling92);
    expect(current.status, WinterArcStatus.active);
    final habits = await reloaded.habits.habitsForSession(current.id);
    expect(
      habits.singleWhere((h) => h.id == 'sleep_before').type,
      HabitType.timeBefore,
    );
    expect(habits.where((h) => h.title == 'Pages'), hasLength(1));
    final day = await reloaded.tracking.today();
    expect(day.totalXp, 30, reason: 'the workout after the export is gone');
    expect(
      (await reloaded.reflections.journal()).todayEntry?.mood?.name,
      'good',
    );
    expect(
      (await reloaded.reminderStore.load()).dailyEnabled,
      isFalse,
      reason: 'reminders come back off after a restore',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
