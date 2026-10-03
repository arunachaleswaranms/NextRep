import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';

import '../test/support/ui.dart';

/// Phase 2 loop on a real device with the system clock and a real SQLite
/// file: Perfect Day → undo → Minimum Day → Journey → relaunch.
///
/// `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app(AppDatabase db) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
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

  Future<void> settleTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('Perfect Day, Minimum Day and Journey persist on device', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it2_');
    final file = File('${dir.path}/nextrep.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's Begin"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tapTimes(tester, find.byTooltip('Add to Workout'), 6);
    await tapTimes(tester, find.byTooltip('Add to Water Intake'), 8);
    await tapTimes(tester, find.byTooltip('Add to Learning / Skills'), 4);
    await tapTimes(tester, find.byTooltip('Complete No Junk Food'), 1);
    expect(find.text('+30 XP bonus'), findsOneWidget);
    await settleTimers(tester);

    await tapTimes(tester, find.byTooltip('Undo No Junk Food'), 1);
    await settleTimers(tester);
    expect(find.text('PERFECT DAY'), findsNothing);

    await reveal(tester, find.text('Having a rough day?'));
    await tester.tap(find.text('Having a rough day?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Switch to Minimum Day'));
    await tester.tap(find.text('Switch to Minimum Day'));
    await tester.pumpAndSettle();
    await settleTimers(tester);
    expect(find.text('MINIMUM DAY'), findsOneWidget);
    expect(find.text('8 / 3 glasses'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Journey'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('JOURNEY'), findsOneWidget);
    expect(find.bySemanticsLabel('Day 1, Today, today'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settleTimers(tester);
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('MINIMUM DAY'), findsOneWidget);
    expect(find.text('8 / 3 glasses'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settleTimers(tester);
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
