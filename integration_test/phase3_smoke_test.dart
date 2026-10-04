import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/features/achievements/widgets/trophy_button.dart';
import 'package:nextrep/features/celebration/celebration_cards.dart';

import '../test/support/ui.dart';

/// Phase 3 on a real device with the system clock and a real SQLite file:
/// achievements unlock once and persist, Journey v2 renders the whole arc,
/// and everything survives a relaunch.
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

  Future<void> tapTimes(WidgetTester tester, Finder finder, int times) async {
    await reveal(tester, finder);
    for (var i = 0; i < times; i++) {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('achievements unlock once, persist, and Journey v2 renders', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it3_');
    final file = File('${dir.path}/nextrep.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's Begin"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rolling 92-Day Arc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.text('0/15'), findsOneWidget);

    // First Rep.
    await tapTimes(tester, find.byTooltip('Complete No Junk Food'), 1);
    expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
    expect(find.text('First Rep'), findsOneWidget);

    // Perfect Day, then Clean Sweep.
    await tapTimes(tester, find.byTooltip('Add to Workout'), 6);
    await tapTimes(tester, find.byTooltip('Add to Water Intake'), 8);
    await tapTimes(tester, find.byTooltip('Add to Learning / Skills'), 4);
    expect(find.text('+30 XP bonus'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Clean Sweep'), findsOneWidget);
    await clearCelebrations(tester);
    expect(find.text('2/15'), findsOneWidget);
    expect(find.text('90 XP'), findsOneWidget);

    // Journey v2: today is perfect, every day is on the path.
    await openTab(tester, 'Journey');
    expect(find.bySemanticsLabel('Day 1, Perfect, today'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Day 1, Perfect, today'));
    await tester.pumpAndSettle();
    expect(find.text('Normal Day'), findsOneWidget);
    expect(find.text('90 XP'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Day 92, Upcoming'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SUMMIT'), findsOneWidget);

    // Achievements screen.
    await tester.tap(find.byType(TrophyButton));
    await tester.pumpAndSettle();
    expect(find.text('2 of 15 unlocked'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Relaunch: unlocks persist and nothing is celebrated again.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('90 XP'), findsOneWidget);
    expect(find.text('2/15'), findsOneWidget);
    expect(find.byType(CelebrationCard), findsNothing);
    expect(await db.select(db.achievementUnlocks).get(), hasLength(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
