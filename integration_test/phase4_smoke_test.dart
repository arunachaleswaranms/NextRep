import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/features/habit_setup/habit_setup_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../test/support/arcs.dart';
import '../test/support/fakes.dart';
import '../test/support/ui.dart';

/// Phase 4 on a real device with the system clock and a real SQLite file:
/// a completed Arc 1, a reused Arc 2, a reflection that survives a
/// relaunch, and Arc 1 still intact in Arc History.
///
/// `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app(AppDatabase db) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // Looping snow / aurora would keep pumpAndSettle from settling.
      ambientMotionProvider.overrideWithValue(false),
    ],
    retry: (_, _) => null,
    child: const NextRepApp(),
  );

  Future<void> openTab(WidgetTester tester, String label) async {
    await clearCelebrations(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
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

  /// Pumps until [finder] shows, for work that runs on real I/O after the
  /// last frame (e.g. the achievement reconcile after a save).
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a second arc, a reflection that persists, and Arc 1 in '
      'history', (tester) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it4_');
    final file = File('${dir.path}/nextrep.sqlite');

    // Arc 1: run through the real services with a clock in the past, so on
    // the device's real date it is over and completed.
    var db = AppDatabase(NativeDatabase(file));
    final now = DateTime.now();
    final seeder = TestApp(db, FakeClock(now));
    await runFirstArc(
      seeder,
      start: DateTime(now.year, now.month, now.day - 120),
    );

    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('WINTER ARC COMPLETE'), findsOneWidget);
    expect(find.bySemanticsLabel('Total XP: 135'), findsOneWidget);

    // Start New Arc → Reuse Last Setup → Setup → Start.
    await tapVisible(tester, find.text('Start New Arc'));
    await tester.tap(find.text('Rolling 92-Day Arc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reuse last setup'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitSetupScreen), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('0 XP'), findsOneWidget);

    // Tonight's reflection.
    await openTab(tester, 'Journal');
    await tester.tap(find.bySemanticsLabel('Mood: Good'));
    await tester.enterText(
      find.widgetWithText(TextField, 'One win today'),
      'Started Arc 2',
    );
    await tapVisible(tester, find.text('Save Reflection'));
    await pumpUntilFound(tester, find.text('Edit'));
    expect(find.text('Started Arc 2'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    await pumpUntilFound(tester, find.text('Looking Inward'));
    expect(find.text('Looking Inward'), findsOneWidget); // unlock card
    await clearCelebrations(tester);

    // Relaunch: the reflection is still there.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    await openTab(tester, 'Journal');
    expect(find.text('Started Arc 2'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    // History: Arc 1 is still exactly as it was.
    await openTab(tester, 'History');
    expect(find.text('ACTIVE'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('COMPLETED'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('COMPLETED'));
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Total XP: 135'), findsOneWidget);
    expect(find.bySemanticsLabel('Achievements: 6 / 15'), findsOneWidget);
    expect(find.text('Start New Arc'), findsNothing);
    await tapVisible(tester, find.text('View Journal'));
    expect(find.text('Showed up'), findsOneWidget);
    expect(find.text('Started Arc 2'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
