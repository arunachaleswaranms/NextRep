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
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/insights/insights_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';
import 'package:nextrep/features/today/widgets/time_before_tile.dart';

import '../test/support/arcs.dart';
import '../test/support/fakes.dart';
import '../test/support/ui.dart';

/// Phase 6 on a device, with a real SQLite file and an injected clock (20
/// Oct 2026, never the device clock): set up the Seasonal Winter Arc, add
/// Sleep Before Target from the templates and a custom count habit, join
/// late on Day 20, log a bedtime, restart, export a format-2 backup
/// (in-memory file adapter), change the data, restore, and check the arc
/// kind, the join date, the habits and Insights.
///
/// `flutter test integration_test -d <device> --no-uninstall`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> pickTime(WidgetTester tester, int hour, int minute) async {
    await tap(tester, find.byIcon(Icons.keyboard_outlined));
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), hour.toString().padLeft(2, '0'));
    await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
    await tap(tester, find.text('OK'));
  }

  testWidgets('seasonal late join, habit evolution and backup v2', (
    tester,
  ) async {
    binding.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(binding.platformDispatcher.clearAlwaysUse24HourTestValue);
    final dir = Directory.systemTemp.createTempSync('nextrep_it6_');
    final file = File('${dir.path}/nextrep.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    final clock = FakeClock(DateTime(2026, 10, 20, 9));
    final files = FakeBackupFiles();

    await tester.pumpWidget(app(db, clock, files));
    await tester.pumpAndSettle();

    // 1. Seasonal setup, in season.
    await tap(tester, find.text("Let's Begin"));
    expect(find.text('In season · 2026'), findsOneWidget);
    await tap(tester, find.text('Seasonal Winter Arc'));
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    expect(find.text('Seasonal · 1 Oct – 31 Dec 2026'), findsOneWidget);

    // 2. Sleep Before Target from the templates (replacing the starter).
    await scrollTo(tester, find.byTooltip('Options for Sleep Before Target'));
    await tap(tester, find.byTooltip('Options for Sleep Before Target'));
    await tap(tester, find.text('Remove'));
    await scrollTo(tester, find.text('Add Habit'));
    await tap(tester, find.text('Add Habit'));
    final template = find.bySemanticsLabel(
      RegExp(r'^Sleep Before Target template'),
    );
    await scrollTo(tester, template, last: true);
    await tap(tester, template);
    expect(find.text('Sleep Before Target added'), findsOneWidget);

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

    // 4–5. Join late: Day 20 of the season, not Day 1. (The snack bar is
    // let go first; it sits over the button.)
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Join Seasonal Winter Arc'));
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 20 of 92'), findsOneWidget);

    // 6. The Journey: days before joining are neutral.
    await openTab(tester, 'Journey');
    final day19 = find.bySemanticsLabel(
      'Day 19. Before you joined this Seasonal Winter Arc.',
    );
    await tester.scrollUntilVisible(
      day19,
      -150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(day19, findsOneWidget);
    await openTab(tester, 'Today');

    // 7–8. Log last night's bedtime: 23:10 meets the 23:30 goal.
    await scrollTo(tester, find.byType(TimeBeforeHabitTile));
    await tap(tester, find.byType(TimeBeforeHabitTile));
    await pickTime(tester, 23, 10);
    expect(find.text('Last night · 23:10'), findsOneWidget);
    final services = TestApp(db, clock);
    expect((await services.tracking.today()).totalXp, 15);

    // 9–10. Restart on the same file: everything persisted.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db, clock, files));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 20 of 92'), findsOneWidget);
    await scrollTo(tester, find.byType(TimeBeforeHabitTile));
    expect(find.text('Last night · 23:10'), findsOneWidget);

    // 11. Export a format-2 backup.
    await openTab(tester, 'History');
    await tap(tester, find.byTooltip('Data & Backup'));
    await tap(tester, find.text('Export Backup'));
    await tap(tester, button('Choose Location'));
    final Uint8List bytes = files.saved.single.$2;
    final backup = BackupValidator.validate(BackupCodec.decode(bytes));
    expect(backup.data.arcs.single.session.kind, ArcKind.seasonalWinter);
    final exported = await dumpOf(db, renumberSessions: true);

    // Change the data after the export.
    final seeder = TestApp(db, clock);
    final pages = (await seeder.tracking.today()).entries.singleWhere(
      (e) => e.habit.title == 'Pages',
    );
    await completeHabit(seeder, pages.habit.id);
    expect(await dumpOf(db, renumberSessions: true), isNot(exported));

    // 12. Restore it.
    files.toPick = bytes;
    await tap(tester, find.text('Restore Backup'));
    await tap(tester, button('Restore'));
    await tap(tester, button('Replace Data'));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    final restored = await dumpOf(db, renumberSessions: true);
    for (final table in exported.keys.where((t) => t != 'reminders')) {
      expect(restored[table], exported[table], reason: table);
    }

    // 13–14. Kind, join date and the evolved habits survive.
    final arc = (await seeder.sessions.currentSession())!;
    expect(arc.kind, ArcKind.seasonalWinter);
    expect(arc.participationStartDate, LocalDate(2026, 10, 20));
    expect(arc.startDate, LocalDate(2026, 10, 1));
    final habits = await seeder.habits.habitsForSession(arc.id);
    final sleep = habits.singleWhere((h) => h.id == 'sleep_before');
    expect(sleep.type, HabitType.timeBefore);
    final custom = habits.singleWhere((h) => h.title == 'Pages');
    expect(SetupHabitRules.isCustomId(custom.id), isTrue);
    expect(custom.unit, 'pages');
    expect(find.text('Day 20 of 92'), findsOneWidget);

    // 15–16. Insights count only the participated day.
    await openTab(tester, 'History');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Insights'));
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Arcs: 0 done · Day 20 now'), findsOneWidget);
    expect(find.bySemanticsLabel('Days climbed: 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
