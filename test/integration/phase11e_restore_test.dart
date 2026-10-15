import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app_info.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/reminder/reminder_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/focus_guard_worker.dart';

/// Phase 11E: the cross-feature restore scenario, at the service level, on
/// a real SQLite file. Every subsystem that a restore touches is on at the
/// same time: an active Arc with Water logged, a completed Arc in History,
/// XP, achievements, a reflection, the daily and evening reminders,
/// Hydration Coach, and Focus Guard (two apps, a budget, today's nudge
/// already claimed by the native check). Synthetic package names only.
const _video = 'org.example.video';
const _chat = 'org.example.chat';
const _game = 'org.example.game';

/// Counts every `dart:io` HTTP client created while it is installed. The
/// manual update check is the only code that may create one, and only on
/// the user's tap; nothing in these scenarios may.
final class _NoNetwork extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('network access during a restore scenario');
  }
}

/// One device: the real services over one database file, with Android's
/// notification, Usage Access and WorkManager facilities faked.
final class _Device {
  _Device(this.file, this.clock, {FakeReminderScheduler? scheduler})
    : scheduler = scheduler ?? FakeReminderScheduler(granted: true) {
    _open();
  }

  final File file;
  final FakeClock clock;
  final FakeReminderScheduler scheduler;
  final platform = FakeFocusGuardPlatform(access: UsageAccess.granted);
  final background = FakeFocusGuardBackgroundScheduler();
  late AppDatabase db;
  late TestApp app;
  late FocusGuardService focusGuard;
  late BackupService backup;

  void _open() {
    db = AppDatabase(
      NativeDatabase(file, setup: AppDatabase.configureConnection),
    );
    app = TestApp(db, clock, scheduler: scheduler);
    focusGuard = FocusGuardService(
      settings: DriftFocusGuardSettingsRepository(db),
      platform: platform,
      background: background,
      notifications: scheduler,
      clock: clock,
    );
    // As wired in dependencies.dart: the restore also cancels Focus
    // Guard's background check.
    backup = BackupService(
      store: app.backupStore,
      scheduler: scheduler,
      focusGuard: background,
      clock: clock,
      appVersion: appVersion,
    );
  }

  /// Closes the database and opens the same file again with fresh
  /// services, as a process restart would, then runs what the app runs at
  /// launch.
  Future<void> relaunch() async {
    await db.close();
    _open();
    await app.lifecycle.reconcile();
    await app.reminders.reconcile();
    await focusGuard.reconcile();
    await app.achievements.reconcile();
  }

  Future<FocusGuardSettings> focusGuardSettings() =>
      DriftFocusGuardSettingsRepository(db).load();

  Future<void> logWater(int glasses) async {
    for (var i = 0; i < glasses; i++) {
      await app.tracking.perform(
        habitId: 'water',
        action: HabitAction.increment,
        date: clock.today(),
      );
    }
  }
}

/// SQLite's own consistency checks on the file.
Future<void> _expectHealthy(AppDatabase db) async {
  final integrity = await db.customSelect('PRAGMA integrity_check').get();
  expect(integrity.single.data.values.single, 'ok');
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  final version = await db.customSelect('PRAGMA user_version').get();
  expect(version.single.data.values.single, 6, reason: 'schema v6, no v7');
}

/// Everything but the reminder row (a restore stores reminders off on
/// purpose; that row is checked on its own).
Future<Map<String, List<String>>> _userData(AppDatabase db) async =>
    (await dumpOf(db, renumberSessions: true))..remove('reminders');

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nextrep_11e_restore_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// The scenario's initial state on [device]. Arc 1 ran from 1 Jul and
  /// closed on 1 Oct 2026; Arc 2 reuses its habits and starts that day.
  /// Leaves the clock on Arc 2's Day 1 at 13:00.
  Future<WinterArcSession> seedEverythingOn(_Device device) async {
    final app = device.app;
    await runFirstArc(app);
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    final arc = await app.winterArc.startWinterArc();
    device.clock.current = DateTime(2026, 10, 1, 13);

    await device.logWater(3);
    await completeHabit(app, 'workout');
    await app.reflections.save(
      sessionId: arc.id,
      date: device.clock.today(),
      draft: const ReflectionDraft(mood: Mood.excellent, win: 'Arc 2 begins'),
    );
    await app.achievements.reconcile();

    expect(
      await app.reminders.update(
        (p) => p.copyWith(
          dailyEnabled: true,
          reflectionEnabled: true,
          hydrationEnabled: true,
          hydrationMode: HydrationMode.supportive,
        ),
      ),
      ReminderUpdate.saved,
    );

    await device.focusGuard.setSelectedApps(const [_video, _chat]);
    await device.focusGuard.setDailyBudget(45);
    expect(await device.focusGuard.setEnabled(true), FocusGuardToggle.on);
    // The native check reached the budget earlier today and nudged.
    expect(
      await workerClaim(
        device.db,
        device.clock.today(),
        budget: 45,
        packages: const [_video, _chat],
      ),
      isTrue,
    );
    return arc;
  }

  test('export, change, restore: every Arc, habit, XP, achievement and '
      'reflection returns; reminders, Hydration Coach and Focus Guard end '
      'up off with their settings kept; nothing is scheduled or sent; the '
      'app relaunches cleanly', () async {
    final network = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      final device = _Device(
        File('${dir.path}/nextrep.sqlite'),
        FakeClock(DateTime(2026, 7, 1)),
      );
      addTearDown(() => device.db.close());
      await seedEverythingOn(device);

      // The initial state really has everything on at once.
      final pendingBefore = device.scheduler.pending;
      expect({
        for (final r in pendingBefore) r.kind,
      }, ReminderKind.values.toSet());
      expect(device.background.scheduled, isTrue);
      expect(
        (await device.focusGuardSettings()).lastNudgedOn,
        LocalDate(2026, 10, 1),
      );
      expect(await device.app.sessions.listSessions(), hasLength(2));
      final original = await _userData(device.db);
      expect(original['reflections'], hasLength(2));
      expect(original['achievements'], isNotEmpty);
      expect(original['xp'], isNotEmpty);

      // Export a format-3 backup.
      final export = await device.backup.export();
      final json = jsonDecode(utf8.decode(export.bytes)) as Map;
      expect(json['formatVersion'], BackupFormat.formatVersion);
      expect(BackupFormat.formatVersion, 3);
      final focusGuardJson = (json['data'] as Map)['focusGuard'] as Map;
      expect(focusGuardJson, {
        'dailyBudgetMinutes': 45,
        'selectedApps': [_video, _chat],
      }, reason: 'never the enabled state, the nudge date or usage');

      // Change and add data in every area, then restore the backup.
      device.clock.advance(const Duration(hours: 2));
      await device.logWater(4);
      await completeAll(device.app);
      await device.app.reflections.save(
        sessionId: (await device.app.sessions.currentSession())!.id,
        date: device.clock.today(),
        draft: const ReflectionDraft(mood: Mood.okay, win: 'Changed'),
      );
      await device.app.achievements.reconcile();
      await device.app.reminders.update(
        (p) => p.copyWith(hydrationMode: HydrationMode.gentle),
      );
      await device.focusGuard.setSelectedApps(const [_game]);
      await device.focusGuard.setDailyBudget(90);
      expect(await _userData(device.db), isNot(original));
      final cancelsBefore = device.background.cancelCalls;

      final outcome = await device.backup.restore(
        await device.backup.inspect(export.bytes),
      );
      expect(outcome.remindersCleared, isTrue);

      // All user data is back, exactly.
      expect(await _userData(device.db), original);
      final arcs = await device.app.sessions.listSessions();
      expect(arcs.map((a) => a.status), [
        WinterArcStatus.active,
        WinterArcStatus.completed,
      ]);
      final journal = await device.app.reflections.journal();
      expect(journal.todayEntry?.win, 'Arc 2 begins');
      final waterToday = (await device.app.tracking.today()).entries.firstWhere(
        (e) => e.habit.id == 'water',
      );
      expect(waterToday.progress.currentValue, 3);

      // Reminders, Hydration Coach: off, settings kept, nothing pending.
      final prefs = await device.app.reminderStore.load();
      expect(prefs.dailyEnabled, isFalse);
      expect(prefs.reflectionEnabled, isFalse);
      expect(prefs.hydrationEnabled, isFalse);
      expect(prefs.hydrationMode, HydrationMode.supportive);
      expect(device.scheduler.pending, isEmpty);

      // Focus Guard: off, apps and budget kept, no nudge on record, the
      // background check cancelled, and the native check can't claim.
      final focusGuard = await device.focusGuardSettings();
      expect(focusGuard.enabled, isFalse);
      expect(focusGuard.selectedPackages, [_video, _chat]);
      expect(focusGuard.dailyBudgetMinutes, 45);
      expect(focusGuard.lastNudgedOn, isNull);
      expect(device.background.scheduled, isFalse);
      expect(device.background.cancelCalls, cancelsBefore + 1);
      expect(
        await workerClaim(
          device.db,
          device.clock.today(),
          budget: 45,
          packages: const [_video, _chat],
        ),
        isFalse,
        reason: 'a check running after the restore posts nothing',
      );
      expect(device.platform.settingsOpened, 0);
      final requestsBefore = device.scheduler.permissionRequests;

      // Relaunch on the restored file: nothing turns itself back on.
      final scheduledBefore = device.background.scheduleCalls;
      await device.relaunch();
      await _expectHealthy(device.db);
      expect(await _userData(device.db), original);
      expect(device.scheduler.pending, isEmpty);
      expect(device.background.scheduled, isFalse);
      expect(device.background.scheduleCalls, scheduledBefore);
      expect((await device.focusGuardSettings()).enabled, isFalse);
      expect(device.scheduler.permissionRequests, requestsBefore);
      expect(device.platform.settingsOpened, 0);

      // The documented exception: re-enabled by the user after a full
      // restore, Focus Guard may nudge once more that same local day.
      expect(await device.focusGuard.setEnabled(true), FocusGuardToggle.on);
      expect(device.background.scheduled, isTrue);
      Future<bool> claim() => workerClaim(
        device.db,
        device.clock.today(),
        budget: 45,
        packages: const [_video, _chat],
      );
      expect(await claim(), isTrue);
      expect(await claim(), isFalse, reason: 'still once a day after that');

      // Hydration Coach plans again only once the user turns it back on.
      await device.app.reminders.update(
        (p) => p.copyWith(hydrationEnabled: true),
      );
      expect(device.scheduler.pending.map((r) => r.kind).toSet(), {
        ReminderKind.hydration,
      });
    }, network);
    expect(network.clients, 0, reason: 'no HTTP client was ever created');
  });

  test('the same restore contract holds for format 1, 2 and 3 backups over '
      'a device with everything on', () async {
    final source = _Device(
      File('${dir.path}/source.sqlite'),
      FakeClock(DateTime(2026, 7, 1)),
    );
    addTearDown(() => source.db.close());
    await seedEverythingOn(source);
    final format3 = (await source.backup.export()).bytes;

    for (final (label, bytes) in [
      (
        'format 1',
        Uint8List.fromList(
          File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync(),
        ),
      ),
      (
        'format 2',
        Uint8List.fromList(
          File('test/fixtures/v1_1_backup_v2.nextrep').readAsBytesSync(),
        ),
      ),
      ('format 3', format3),
    ]) {
      final device = _Device(
        File('${dir.path}/target_${label.replaceAll(' ', '')}.sqlite'),
        FakeClock(DateTime(2026, 7, 1)),
      );
      await seedEverythingOn(device);
      final backup = await device.backup.inspect(bytes);
      await device.backup.restore(backup);
      await device.relaunch();

      final prefs = await device.app.reminderStore.load();
      expect(prefs.anyEnabled, isFalse, reason: label);
      expect(prefs.hydrationEnabled, isFalse, reason: label);
      expect(device.scheduler.pending, isEmpty, reason: label);
      final focusGuard = await device.focusGuardSettings();
      expect(focusGuard.enabled, isFalse, reason: label);
      expect(focusGuard.lastNudgedOn, isNull, reason: label);
      expect(device.background.scheduled, isFalse, reason: label);
      // Formats 1 and 2 carry no Focus Guard section: its settings are the
      // defaults. Format 3 brings the apps and budget back.
      if (label == 'format 3') {
        expect(focusGuard.selectedPackages, [_video, _chat]);
        expect(focusGuard.dailyBudgetMinutes, 45);
      } else {
        expect(focusGuard.selectedPackages, isEmpty, reason: label);
        expect(
          focusGuard.dailyBudgetMinutes,
          FocusGuardRules.defaultDailyBudgetMinutes,
          reason: label,
        );
      }
      expect(
        await device.app.sessions.listSessions(),
        hasLength(backup.summary.arcCount),
        reason: label,
      );
      await _expectHealthy(device.db);
      await device.db.close();
    }
  });

  test('a restore that meets another connection holding the write lock '
      'fails as a whole: nothing is half replaced, nothing is cancelled; it '
      'succeeds once the lock is gone', () async {
    final file = File('${dir.path}/nextrep.sqlite');
    final device = _Device(file, FakeClock(DateTime(2026, 7, 1)));
    addTearDown(() => device.db.close());
    await seedEverythingOn(device);
    final bytes = (await device.backup.export()).bytes;

    // Later the same day: more Water, and new Focus Guard settings.
    device.clock.advance(const Duration(hours: 1));
    await device.logWater(2);
    await device.focusGuard.setDailyBudget(30);
    final before = await dumpOf(device.db, renumberSessions: true);
    final pendingBefore = device.scheduler.pending;
    final focusGuardBefore = await _focusGuardRow(device.db);

    // Another connection to the same file (as the `:focus_guard` process
    // would be) holds the write lock and doesn't let go.
    final native = sqlite.sqlite3.open(file.path);
    addTearDown(native.close);
    native
      ..execute('PRAGMA busy_timeout = 0')
      ..execute('BEGIN IMMEDIATE')
      ..execute(
        'UPDATE focus_guard_preferences SET updated_at = updated_at '
        'WHERE id = 1',
      );

    final validated = await device.backup.inspect(bytes);
    await expectLater(device.backup.restore(validated), throwsA(anything));

    // Plain reads (no transaction) still work while the lock is held.
    expect(await dumpOf(device.db, renumberSessions: true), before);
    expect(await _focusGuardRow(device.db), focusGuardBefore);
    expect(focusGuardBefore['enabled'], 1);
    expect(focusGuardBefore['daily_budget_minutes'], 30);
    expect(device.scheduler.pending, pendingBefore, reason: 'not cancelled');
    expect(device.background.scheduled, isTrue, reason: 'not cancelled');

    native.execute('COMMIT');
    await device.backup.restore(validated);
    expect((await device.focusGuardSettings()).enabled, isFalse);
    expect((await device.focusGuardSettings()).dailyBudgetMinutes, 45);
    expect(device.scheduler.pending, isEmpty);
    expect(device.background.scheduled, isFalse);
    await _expectHealthy(device.db);

    // Exactly one database file: no copy was left next to it.
    expect(
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.endsWith('.sqlite')),
      ['nextrep.sqlite'],
    );
  });
}

/// Focus Guard's stored row, read without a transaction.
Future<Map<String, Object?>> _focusGuardRow(AppDatabase db) async =>
    (await db
            .customSelect(
              'SELECT enabled, daily_budget_minutes, last_nudged_on '
              'FROM focus_guard_preferences WHERE id = 1',
            )
            .get())
        .single
        .data;
