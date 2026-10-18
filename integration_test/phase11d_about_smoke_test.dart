import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';

import '../test/support/fakes.dart';

/// Phase 11D smoke, on a device or simulator: About opened from a fresh
/// install shows the version and build the platform reports for the
/// installed app (the real package_info_plus source, not a fake).
///
/// No update feed is provided, as on iOS in `main.dart`, so nothing here
/// can reach the network: About explains that releases are Android only.
/// The Android check itself is qualified on the emulator (docs/PHASE_11D.md).
///
/// `flutter test integration_test/phase11d_about_smoke_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('About from onboarding: installed metadata, no update check '
      'without a feed', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 15, 9))),
          ambientMotionProvider.overrideWithValue(false),
        ],
        retry: (_, _) => null,
        child: const NextRepApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('About NextRep'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 1.2.0'), findsOneWidget);
    expect(find.text('Build 3'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
    expect(
      find.text(
        'NextRep releases are published for Android only, so this device '
        "doesn't check for updates.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    debugPrint(
      'PHASE11D_ABOUT ${Platform.operatingSystem}: Version 1.2.0, Build 3, '
      'no update check offered',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
