import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/data/drift_reminder_preferences_repository.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/focus_guard/focus_guard_app_picker_screen.dart';
import 'package:nextrep/features/focus_guard/focus_guard_card.dart';
import 'package:nextrep/features/focus_guard/focus_guard_settings_screen.dart';
import 'package:nextrep/features/reminders/reminder_settings_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';
import '../support/updates.dart';

/// Phase 11E: one realistic session through the real UI, with every v1.2
/// feature used together: a fresh install, a Rolling Arc, habits, XP, a
/// reflection, Hydration Coach, Focus Guard, About and its manual update
/// check, background and resume, a backup, a restore, and a relaunch on the
/// same database file.
///
/// Android's facilities are fakes (synthetic apps `org.example.*`, no
/// real usage); GitHub is a counting fake answering with a synthetic
/// v1.2.0; nothing reaches the network.
const _video = 'org.example.video';
const _chat = 'org.example.chat';

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the screen's main list until [finder] is built and visible.
Future<void> _seek(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
);

Future<void> _back(WidgetTester tester) async {
  await clearCelebrations(tester);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// The XP total Today shows, e.g. "15 XP".
String _xpShown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .firstWhere((text) => RegExp(r'^\d+ XP$').hasMatch(text));

Finder _switchOf(String title) => find.descendant(
  of: find.widgetWithText(SwitchListTile, title),
  matching: find.byType(Switch),
);

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

void main() {
  testWidgets('a realistic day with every feature: Arc, habits, XP, Journal, '
      'Hydration Coach, Focus Guard, About and one update check, background '
      'and resume, backup, restore and relaunch', (tester) async {
    await _setPhoneSize(tester);
    final dir = Directory.systemTemp.createTempSync('nextrep_11e_journey_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/nextrep.sqlite');
    AppDatabase open() => AppDatabase(
      NativeDatabase(file, setup: AppDatabase.configureConnection),
    );

    final clock = FakeClock(DateTime(2026, 10, 1, 7));
    final scheduler = FakeReminderScheduler(granted: false, grant: true);
    final platform = FakeFocusGuardPlatform(
      apps: const [
        LaunchableAppCandidate(packageName: _video, label: 'Video Stream'),
        LaunchableAppCandidate(packageName: _chat, label: 'Chat Hub'),
        LaunchableAppCandidate(packageName: 'com.nextrep.nextrep', label: 'X'),
      ],
    );
    final background = FakeFocusGuardBackgroundScheduler();
    final github = FakeGitHubClient(); // the latest release is v1.2.0
    final links = FakeExternalLinks();
    final files = FakeBackupFiles();
    Widget appOn(AppDatabase db) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        ambientMotionProvider.overrideWithValue(false),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        focusGuardPlatformProvider.overrideWithValue(platform),
        focusGuardSchedulerProvider.overrideWithValue(background),
        releaseFeedProvider.overrideWithValue(
          GitHubReleaseFeed(client: () => github),
        ),
        installedAppSourceProvider.overrideWithValue(FakeInstalledAppSource()),
        externalLinksProvider.overrideWithValue(links),
        backupFilesProvider.overrideWithValue(files),
      ],
      retry: (_, _) => null,
      child: const NextRepApp(),
    );

    // 1–4. A fresh install: onboarding, a Rolling Arc with the starter
    // habits (the built-in Water habit among them).
    var db = open();
    await tester.pumpWidget(appOn(db));
    await tester.pumpAndSettle();
    expect(find.text("Let's Begin"), findsOneWidget);
    await _tap(tester, find.text("Let's Begin"));
    await _tap(tester, find.text('Rolling 92-Day Arc'));
    expect(find.text('Choose your habits'), findsOneWidget);
    await _tap(tester, find.text('Start Winter Arc'));
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(scheduler.permissionRequests, 0, reason: 'never at startup');
    expect(platform.settingsOpened, 0);

    // 5–6. Complete habits, earn XP.
    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await _tap(tester, find.byTooltip('Complete No Junk Food'));
    expect(find.text('15 XP'), findsOneWidget);
    await reveal(tester, find.byTooltip('Add to Water Intake'));
    await _tap(tester, find.byTooltip('Add to Water Intake'));
    expect(find.text('1 / 8 glasses'), findsOneWidget);

    // 7. A reflection.
    await _openTab(tester, 'Journal');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Mood: Good'));
    await tester.enterText(
      find.widgetWithText(TextField, 'One win today'),
      'Started the Arc',
    );
    await _tap(tester, find.text('Save Reflection'));
    expect(find.text('Started the Arc'), findsOneWidget);

    // 8–10. Reminders → Hydration Coach, Supportive (the permission is
    // asked for here, on the user's tap, and granted).
    await _tap(tester, find.byTooltip('Reminders'));
    expect(find.byType(ReminderSettingsScreen), findsOneWidget);
    await _seek(tester, _switchOf('Hydration Coach'));
    await _tap(tester, _switchOf('Hydration Coach'));
    expect(scheduler.permissionRequests, 1);
    await _seek(tester, find.text('Supportive'));
    await _tap(tester, find.text('Supportive'));
    final hydrationKinds = {for (final r in scheduler.pending) r.kind};
    expect(hydrationKinds, {ReminderKind.hydration});
    await _back(tester);
    await _openTab(tester, 'Today');

    // 11–15. Focus Guard from the Today card: Usage Access (granted in
    // "system settings"), two apps, a budget, then on.
    await reveal(tester, find.byType(FocusGuardCard));
    await _tap(tester, find.byType(FocusGuardCard));
    expect(find.byType(FocusGuardSettingsScreen), findsOneWidget);
    await _seek(tester, find.text('Allow Usage Access'));
    await _tap(tester, find.text('Allow Usage Access'));
    expect(platform.settingsOpened, 1);
    platform.access = UsageAccess.granted;
    await _backgroundAndResume(tester);
    await _seek(tester, find.text('Choose apps'));
    await _tap(tester, find.text('Choose apps'));
    expect(find.byType(FocusGuardAppPickerScreen), findsOneWidget);
    expect(find.text('X'), findsNothing, reason: 'NextRep itself is left out');
    await _tap(tester, find.text('Video Stream'));
    await _tap(tester, find.text('Chat Hub'));
    await _tap(tester, find.text('Save'));
    await _seek(tester, find.text('Combined daily budget'));
    await _tap(tester, find.text('Combined daily budget'));
    await _tap(tester, find.text('30 min'));
    await _tap(tester, find.text('Save'));
    await tester.scrollUntilVisible(
      _switchOf('Focus Guard'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    await _tap(tester, _switchOf('Focus Guard'));
    expect(find.text('On. Checking in the background.'), findsOneWidget);
    expect(background.scheduled, isTrue);
    expect(scheduler.permissionRequests, 1, reason: 'already granted');
    final focusGuard = await DriftFocusGuardSettingsRepository(db).load();
    expect(focusGuard.selectedPackages, [_video, _chat]);
    expect(focusGuard.dailyBudgetMinutes, 30);

    // Neither feature changed the other's settings.
    final prefs = await DriftReminderPreferencesRepository(db).load();
    expect(prefs.hydrationEnabled, isTrue);
    expect(prefs.hydrationMode, HydrationMode.supportive);
    expect(prefs.dailyEnabled, isFalse);

    // 16–19. Back on Today: log Water (Hydration Coach re-plans), and the
    // Focus Guard card measures today.
    await _back(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    platform.usage = const {
      _video: Duration(minutes: 12),
      _chat: Duration(minutes: 6),
    };
    clock.current = DateTime(2026, 10, 1, 10);
    await _backgroundAndResume(tester);
    final beforeWater = [for (final r in scheduler.pending) (r.id, r.at)];
    await reveal(tester, find.byTooltip('Add to Water Intake'));
    for (var i = 0; i < 4; i++) {
      await _tap(tester, find.byTooltip('Add to Water Intake'));
    }
    expect(find.text('5 / 8 glasses'), findsOneWidget);
    // 5 glasses at 10:00 meet today's 12:03 (4) and 14:18 (5) checkpoints
    // (Supportive, 08:00 – 20:00, target 8): only those two go.
    final afterWater = [for (final r in scheduler.pending) (r.id, r.at)];
    expect(afterWater.length, beforeWater.length - 2);
    expect([for (final r in scheduler.pending) r.id].where((id) => id < 310), [
      303,
      304,
    ]);
    await reveal(tester, find.byType(FocusGuardCard));
    expect(
      find.descendant(
        of: find.byType(FocusGuardCard),
        matching: find.text('18 / 30 min'),
      ),
      findsOneWidget,
    );
    final arcRows = await snapshotOf(db, 1);
    final xp = _xpShown(tester);
    expect(xp, isNot('0 XP'));

    // 20–24. About: the installed version, no request until the tap, then
    // exactly one; the synthetic v1.2.0 opens only the official page.
    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('About NextRep'));
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 1.1.0'), findsOneWidget);
    expect(find.text('Build 2'), findsOneWidget);
    expect(github.requests, isEmpty);
    await _tap(tester, find.text('Check for updates'));
    expect(github.requests, hasLength(1));
    expect(find.text('NextRep v1.2.0 is available.'), findsOneWidget);
    await _tap(tester, _button('View official release'));
    expect(
      links.opened.single.toString(),
      'https://github.com/arunachaleswaranms/NextRep/releases/tag/v1.2.0',
    );

    // 25–26. Back to Today: the Arc is exactly as it was.
    await _back(tester);
    await _openTab(tester, 'Today');
    expect(_xpShown(tester), xp);
    expect(await snapshotOf(db, 1), arcRows);

    // 27–28. Background and resume: the plan and the check stay as they
    // were, and nothing reaches the network.
    final pending = [for (final r in scheduler.pending) (r.id, r.at)];
    await _backgroundAndResume(tester);
    expect([for (final r in scheduler.pending) (r.id, r.at)], pending);
    expect(background.scheduled, isTrue);
    expect(github.requests, hasLength(1));

    // 29. Export a backup.
    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('Data & Backup'));
    expect(find.byType(DataBackupScreen), findsOneWidget);
    await _tap(tester, find.text('Export Backup'));
    await _tap(tester, _button('Choose Location'));
    final (name, bytes) = files.saved.single;
    expect(name, 'nextrep-backup-2026-10-01.nextrep');
    final document = BackupCodec.decode(bytes);
    expect(document.data.focusGuard?.selectedPackages, [_video, _chat]);

    // 30–32. Restore it: the data comes back, the opt-in features are off.
    final userData = await dumpOf(db, renumberSessions: true);
    files.toPick = bytes;
    await tester.pump(const Duration(seconds: 5));
    await _tap(tester, find.text('Restore Backup'));
    await _tap(tester, _button('Restore'));
    await _tap(tester, _button('Replace Data'));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(_xpShown(tester), xp);
    final restoredPrefs = await DriftReminderPreferencesRepository(db).load();
    expect(restoredPrefs.hydrationEnabled, isFalse);
    expect(restoredPrefs.hydrationMode, HydrationMode.supportive);
    expect(scheduler.pending, isEmpty);
    final restoredGuard = await DriftFocusGuardSettingsRepository(db).load();
    expect(restoredGuard.enabled, isFalse);
    expect(restoredGuard.selectedPackages, [_video, _chat]);
    expect(restoredGuard.dailyBudgetMinutes, 30);
    expect(background.scheduled, isFalse);
    final restored = await dumpOf(db, renumberSessions: true);
    for (final table in userData.keys.where((t) => t != 'reminders')) {
      expect(restored[table], userData[table], reason: table);
    }

    // 33–34. Relaunch on the same file: still restored, still off, About
    // still idle with the installed version.
    await _shutDown(tester);
    await db.close();
    db = open();
    addTearDown(db.close);
    await tester.pumpWidget(appOn(db));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(_xpShown(tester), xp);
    await reveal(tester, find.byType(FocusGuardCard));
    expect(
      find.descendant(
        of: find.byType(FocusGuardCard),
        matching: find.text('Stay aware of time spent in selected apps.'),
      ),
      findsOneWidget,
    );
    expect(scheduler.pending, isEmpty);
    expect(background.scheduled, isFalse);
    await _openTab(tester, 'Journal');
    expect(find.text('Started the Arc'), findsOneWidget);
    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('About NextRep'));
    expect(find.text('Version 1.1.0'), findsOneWidget);
    expect(find.text('Only checks GitHub when you tap.'), findsOneWidget);

    expect(github.requests, hasLength(1), reason: 'only the one tap');
    expect(scheduler.permissionRequests, 1);
    expect(platform.settingsOpened, 1);
    await _shutDown(tester);
  });
}
