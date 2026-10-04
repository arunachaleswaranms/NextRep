import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_reminder_preferences_repository.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/insights/insights_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../test/support/arcs.dart';
import '../test/support/fakes.dart';
import '../test/support/ui.dart';

/// Phase 5 on a real device with the system clock and a real SQLite file:
/// export a backup (through an in-memory file adapter, not the system
/// picker), change the data, restore the backup, check every arc, the
/// Journal, achievements, reminders and Insights, then delete Arc 1 and
/// check Arc 2 is intact.
///
/// `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app(AppDatabase db, FakeBackupFiles files) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
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

  Future<void> openTab(WidgetTester tester, String label) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('export, restore, insights and deleting an arc', (tester) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it5_');
    final db = AppDatabase(NativeDatabase(File('${dir.path}/nextrep.sqlite')));

    // Arc 1 completed long ago; Arc 2 started today with a reflection.
    final now = DateTime.now();
    final seeder = TestApp(db, FakeClock(now));
    await runFirstArc(
      seeder,
      start: DateTime(now.year, now.month, now.day - 120),
    );
    seeder.clock.current = now;
    await seeder.winterArc.startNewArc(NewArcBaseline.reuseLast);
    final arc2 = await seeder.winterArc.startWinterArc();
    await completeHabit(seeder, 'water');
    await seeder.reflections.save(
      sessionId: arc2.id,
      date: seeder.clock.today(),
      draft: const ReflectionDraft(mood: Mood.excellent, win: 'Arc 2 night'),
    );
    await seeder.achievements.reconcile();
    await DriftReminderPreferencesRepository(db).save(
      const ReminderPreferences(
        dailyEnabled: true,
        dailyTime: ReminderTime(7, 30),
        reflectionEnabled: true,
        reflectionTime: ReminderTime(21, 15),
      ),
      at: now,
    );

    final files = FakeBackupFiles();
    await tester.pumpWidget(app(db, files));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);

    // 1–2. Export through the in-memory adapter; check what it holds.
    await openTab(tester, 'History');
    await tap(tester, find.byTooltip('Data & Backup'));
    await tap(tester, find.text('Export Backup'));
    await tap(tester, button('Choose Location'));
    expect(files.saved, hasLength(1));
    final Uint8List bytes = files.saved.single.$2;
    final summary = BackupValidator.validate(BackupCodec.decode(bytes)).summary;
    expect(summary.arcCount, 2);
    expect(summary.completedArcs, 1);
    expect(summary.reflectionCount, 2);
    expect(summary.achievementCount, greaterThanOrEqualTo(7));
    final exported = await dumpOf(db, renumberSessions: true);

    // Change the data after the export: another habit done today.
    await completeHabit(seeder, 'no_junk_food');
    expect(await dumpOf(db, renumberSessions: true), isNot(exported));

    // 3. Restore the backup over it.
    files.toPick = bytes;
    await tap(tester, find.text('Restore Backup'));
    expect(find.bySemanticsLabel('Arcs: 2'), findsOneWidget);
    await tap(tester, button('Restore'));
    await tap(tester, button('Replace Data'));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);

    // 4–8. Everything is back as exported; reminders are off.
    final restored = await dumpOf(db, renumberSessions: true);
    for (final table in exported.keys.where((t) => t != 'reminders')) {
      expect(restored[table], exported[table], reason: table);
    }
    final prefs = await DriftReminderPreferencesRepository(db).load();
    expect(prefs.anyEnabled, isFalse);
    expect(prefs.dailyTime, const ReminderTime(7, 30));
    expect(prefs.reflectionTime, const ReminderTime(21, 15));

    await openTab(tester, 'Journal');
    expect(find.text('Arc 2 night'), findsOneWidget);

    // 9–10. Insights across both arcs.
    await openTab(tester, 'History');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Insights'));
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Arcs: 1 done · Day 1 now'), findsOneWidget);
    expect(find.bySemanticsLabel('Days climbed: 93'), findsOneWidget);
    expect(find.bySemanticsLabel('Perfect Days: 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 11–13. Arc History: Arc 1 intact, then deleted; Arc 2 untouched.
    expect(find.byType(ArcHistoryScreen), findsOneWidget);
    await scrollTo(tester, find.text('COMPLETED'));
    await tap(tester, find.text('COMPLETED'));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Total XP: 135'), findsOneWidget);
    final restoredArc2 = (await seeder.sessions.currentSession())!;
    expect(restoredArc2.id, greaterThan(arc2.id), reason: 'fresh ids');
    final arc2Rows = await snapshotOf(db, restoredArc2.id);
    await tap(tester, find.byTooltip('Arc options'));
    await tap(tester, find.text('Delete Arc'));
    await tap(tester, button('Delete Arc'));
    expect(find.byType(ArcHistoryScreen), findsOneWidget);
    expect(find.text('COMPLETED'), findsNothing);
    expect(await snapshotOf(db, restoredArc2.id), arc2Rows);
    await openTab(tester, 'Today');
    expect(find.text('Day 1 of 92'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
