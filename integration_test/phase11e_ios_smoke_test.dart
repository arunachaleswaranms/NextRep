import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/focus_guard/focus_guard_card.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';

import '../test/support/fakes.dart';

/// Phase 11E smoke for iOS, on a simulator: the integrated v1.2 app with
/// the platform wired as `main.dart` wires it on iOS. No Focus Guard
/// platform and no update feed are provided, so Focus Guard is omitted and
/// About offers no check; the version comes from the real `Info.plist`.
/// Notifications use the disabled scheduler so no system prompt can block
/// the run: Hydration Coach shows its "not allowed" path.
///
/// Every `dart:io` HTTP client creation is counted: none may happen.
///
/// Run on the iOS simulator only:
/// `flutter test integration_test/phase11e_ios_smoke_test.dart -d <simulator>`
/// Never on an Android device that holds the official app: a debug
/// `com.nextrep.nextrep` would be installed over it.
final class _NoNetwork extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return super.createHttpClient(context);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: onboarding, Arc, habits, Hydration Coach UI, no Focus '
      'Guard, About without a check, backup screen, no network', (
    tester,
  ) async {
    final network = _NoNetwork();
    HttpOverrides.global = network;
    addTearDown(() => HttpOverrides.global = null);
    final db = memoryDatabase();
    addTearDown(db.close);
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> settleCelebrations() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 16, 9))),
          ambientMotionProvider.overrideWithValue(false),
        ],
        retry: (_, _) => null,
        child: const NextRepApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tap(find.text("Let's Begin"));
    await tap(find.text('Rolling 92-Day Arc'));
    await tap(find.text('Start Winter Arc'));
    expect(find.text('Day 1 of 92'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip('Complete No Junk Food'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(find.byTooltip('Complete No Junk Food'));
    await settleCelebrations();
    await tester.scrollUntilVisible(
      find.byTooltip('Add to Water Intake'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(find.byTooltip('Add to Water Intake'));
    expect(find.text('1 / 8 glasses'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    // The card is there but renders nothing where Focus Guard is
    // unsupported.
    expect(
      find.descendant(
        of: find.byType(FocusGuardCard),
        matching: find.byType(Text),
      ),
      findsNothing,
      reason: 'Android only',
    );
    expect(find.textContaining('Focus Guard'), findsNothing);

    await tester.scrollUntilVisible(
      find.byTooltip('Reminders'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(find.byTooltip('Reminders'));
    expect(find.byType(ReminderSettingsScreen), findsOneWidget);
    final hydration = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Hydration Coach'),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(
      hydration,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(hydration);
    expect(
      find.textContaining("Notifications weren't allowed"),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(hydration).value, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('History'),
      ),
    );
    expect(find.byTooltip('Focus Guard'), findsNothing);
    await tap(find.byTooltip('Data & Backup'));
    expect(find.byType(DataBackupScreen), findsOneWidget);
    expect(find.text('Export Backup'), findsOneWidget);
    expect(find.text('Restore Backup'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap(find.byTooltip('About NextRep'));
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 1.2.0'), findsOneWidget);
    expect(find.text('Build 3'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(network.clients, 0);
    debugPrint(
      'PHASE11E_SMOKE ${Platform.operatingSystem}: Arc, habits, Hydration '
      'Coach UI, no Focus Guard, About 1.2.0 (3) without a check, '
      'backup screen; HTTP clients: ${network.clients}',
    );
  });
}
