import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';

/// Runs the Day 1 flow on a real device with the system clock and a real
/// SQLite file, then relaunches the app on a fresh connection to that file.
///
/// `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget app(AppDatabase db) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    retry: (_, _) => null,
    child: const NextRepApp(),
  );

  testWidgets('Day 1 flow persists across relaunch on device', (tester) async {
    final dir = Directory.systemTemp.createTempSync('nextrep_it_');
    final file = File('${dir.path}/nextrep.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Let's Begin"));
    await tester.pumpAndSettle();
    expect(find.text('Choose your habits'), findsOneWidget);

    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byTooltip('Undo No Junk Food'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
