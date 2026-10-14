import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_background.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';

import '../support/fakes.dart';
import '../support/seasonal_backup.dart';

/// Phase 11C: Focus Guard's rows as both Drift and the native background
/// check (`android/.../focusguard/FocusGuardStore.kt`) use them.
const _kotlinDir = 'android/app/src/main/kotlin/com/nextrep/nextrep/focusguard';
const _apps = ['org.example.video', 'org.example.chat'];

String _kotlin(String file) => File('$_kotlinDir/$file').readAsStringSync();

/// The worker's claim statement, taken from the Kotlin source so this test
/// runs exactly what ships, with its package placeholders expanded.
String _claimSql(int packages) {
  final source = _kotlin('FocusGuardStore.kt');
  final match = RegExp(
    r'"""\s*(UPDATE focus_guard_preferences SET last_nudged_on = \?.*?)"""',
    dotAll: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'claim SQL not found in Kotlin source');
  return match!
      .group(1)!
      .replaceAll(r'$placeholders', List.filled(packages, '?').join(','));
}

/// Runs the worker's claim against [db]. Returns whether it claimed.
Future<bool> _workerClaim(
  AppDatabase db,
  String today, {
  int budget = 60,
  List<String> packages = _apps,
}) async {
  final changed = await db.customUpdate(
    _claimSql(packages.length),
    variables: [
      Variable.withString(today),
      Variable.withInt(budget),
      Variable.withString(today),
      Variable.withString(LocalDate.parse(today).addDays(1).toIsoString()),
      Variable.withInt(packages.length),
      for (final p in packages) Variable.withString(p),
    ],
    updates: {db.focusGuardPrefs},
  );
  return changed == 1;
}

AppDatabase _db() {
  final db = memoryDatabase();
  addTearDown(db.close);
  return db;
}

Future<void> _saveOn(AppDatabase db, {int budget = 60, LocalDate? nudged}) =>
    DriftFocusGuardSettingsRepository(db).save(
      FocusGuardSettings(
        enabled: true,
        dailyBudgetMinutes: budget,
        selectedPackages: _apps,
        lastNudgedOn: nudged,
      ),
      at: DateTime.utc(2026, 10, 14, 8),
    );

void main() {
  group('the native check reads the same database as Drift', () {
    test('file, schema version and limits match the Kotlin side', () {
      final database = _kotlin('FocusGuardDatabase.kt');
      final store = _kotlin('FocusGuardStore.kt');
      // path_provider's documents directory is Context.getDir("flutter").
      expect(
        database,
        contains('"app_flutter/${AppDatabase.fileName}.sqlite"'),
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(store, contains('SCHEMA_VERSION = ${db.schemaVersion}L'));
      expect(
        store,
        contains(
          'MIN_BUDGET_MINUTES = ${FocusGuardRules.minDailyBudgetMinutes}L',
        ),
      );
      expect(
        store,
        contains(
          'MAX_BUDGET_MINUTES = ${FocusGuardRules.maxDailyBudgetMinutes}L',
        ),
      );
    });

    test('the representation the Kotlin store parses', () async {
      final db = _db();
      await _saveOn(db, budget: 45, nudged: LocalDate(2026, 10, 5));
      final row = await db
          .customSelect(
            'SELECT typeof(enabled) AS te, enabled, typeof(daily_budget_minutes) '
            'AS tb, typeof(last_nudged_on) AS tl, last_nudged_on, '
            'typeof(updated_at) AS tu FROM focus_guard_preferences',
          )
          .getSingle();
      expect(row.data, {
        'te': 'integer',
        'enabled': 1,
        'tb': 'integer',
        'tl': 'text',
        'last_nudged_on': '2026-10-05',
        'tu': 'integer',
      });
      expect((await db.customSelect('PRAGMA user_version').getSingle()).data, {
        'user_version': 6,
      });
    });

    test('the connection waits for another process\'s lock', () async {
      final db = AppDatabase(
        NativeDatabase.memory(setup: AppDatabase.configureConnection),
      );
      addTearDown(db.close);
      final row = await db.customSelect('PRAGMA busy_timeout').getSingle();
      expect(row.data.values.single, AppDatabase.busyTimeout.inMilliseconds);
    });
  });

  group('one nudge a day, against Drift\'s schema', () {
    test('the claim succeeds once per local date', () async {
      final db = _db();
      await _saveOn(db);
      expect(await _workerClaim(db, '2026-10-14'), isTrue);
      expect(await _workerClaim(db, '2026-10-14'), isFalse);
      expect(await _workerClaim(db, '2026-10-15'), isTrue);
    });

    test('a foreground save from settings loaded before the nudge keeps '
        'the worker\'s date', () async {
      final db = _db();
      final repo = DriftFocusGuardSettingsRepository(db);
      await _saveOn(db);
      final stale = await repo.load(); // the UI reads its settings
      expect(stale.lastNudgedOn, isNull);
      expect(await _workerClaim(db, '2026-10-14'), isTrue); // worker nudges
      await repo.save(
        stale.copyWith(dailyBudgetMinutes: 90), // the UI saves its copy
        at: DateTime.utc(2026, 10, 14, 18),
      );
      final now = await repo.load();
      expect(now.dailyBudgetMinutes, 90);
      expect(now.lastNudgedOn, LocalDate(2026, 10, 14));
      expect(await _workerClaim(db, '2026-10-14', budget: 90), isFalse);
    });

    test('off and on again the same day keeps the date', () async {
      final db = _db();
      final repo = DriftFocusGuardSettingsRepository(db);
      await _saveOn(db);
      await _workerClaim(db, '2026-10-14');
      final settings = await repo.load();
      await repo.save(
        settings.copyWith(enabled: false),
        at: DateTime.utc(2026),
      );
      await repo.save(settings.copyWith(enabled: true), at: DateTime.utc(2026));
      expect((await repo.load()).lastNudgedOn, LocalDate(2026, 10, 14));
      expect(await _workerClaim(db, '2026-10-14'), isFalse);
    });

    test('no claim while off, or after the apps changed', () async {
      final db = _db();
      final repo = DriftFocusGuardSettingsRepository(db);
      await _saveOn(db);
      await repo.save(
        (await repo.load()).copyWith(enabled: false),
        at: DateTime.utc(2026),
      );
      expect(await _workerClaim(db, '2026-10-14'), isFalse);
      await repo.save(
        (await repo.load()).copyWith(
          enabled: true,
          selectedPackages: [_apps.first],
        ),
        at: DateTime.utc(2026),
      );
      expect(await _workerClaim(db, '2026-10-14'), isFalse);
      expect(
        await _workerClaim(db, '2026-10-14', packages: [_apps.first]),
        isTrue,
      );
    });

    test('an existing row created by the first save takes its date', () async {
      final db = _db();
      await _saveOn(db, nudged: LocalDate(2026, 10, 13));
      expect(
        (await DriftFocusGuardSettingsRepository(db).load()).lastNudgedOn,
        LocalDate(2026, 10, 13),
      );
    });
  });

  group('restore', () {
    /// A device where Focus Guard is on, monitoring, and nudged today.
    Future<
      ({
        TestApp app,
        FakeFocusGuardBackgroundScheduler background,
        BackupService backup,
      })
    >
    monitoring() async {
      final app = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 10, 14, 18)),
        scheduler: FakeReminderScheduler(granted: true),
      );
      addTearDown(app.db.close);
      final background = FakeFocusGuardBackgroundScheduler();
      final service = FocusGuardService(
        settings: DriftFocusGuardSettingsRepository(app.db),
        platform: FakeFocusGuardPlatform(access: UsageAccess.granted),
        background: background,
        notifications: app.scheduler,
        clock: app.clock,
      );
      await service.setSelectedApps(_apps);
      await service.setEnabled(true);
      await _workerClaim(app.db, '2026-10-14');
      expect(background.scheduled, isTrue);
      final backup = BackupService(
        store: app.backupStore,
        scheduler: app.scheduler,
        focusGuard: background,
        clock: app.clock,
        appVersion: '1.1.0',
      );
      return (app: app, background: background, backup: backup);
    }

    Future<void> expectOff(
      ({
        TestApp app,
        FakeFocusGuardBackgroundScheduler background,
        BackupService backup,
      })
      device, {
      required List<String> apps,
      required int budget,
    }) async {
      final settings = await DriftFocusGuardSettingsRepository(device.app.db)
          .load();
      expect(settings.enabled, isFalse);
      expect(settings.lastNudgedOn, isNull);
      expect(settings.selectedPackages, apps);
      expect(settings.dailyBudgetMinutes, budget);
      expect(device.background.scheduled, isFalse);
      // A check that was already running finds nothing to claim.
      expect(await _workerClaim(device.app.db, '2026-10-14'), isFalse);
      // And the app's own reconciliation after the restart keeps it off.
      final service = FocusGuardService(
        settings: DriftFocusGuardSettingsRepository(device.app.db),
        platform: FakeFocusGuardPlatform(access: UsageAccess.granted),
        background: device.background,
        notifications: device.app.scheduler,
        clock: device.app.clock,
      );
      expect(await service.reconcile(), isFalse);
      expect(device.background.scheduled, isFalse);
    }

    test('format 3 with Focus Guard: configuration back, off, no nudge on '
        'record, the job cancelled', () async {
      final source = await seasonalSource();
      addTearDown(source.db.close);
      await DriftFocusGuardSettingsRepository(source.db).save(
        const FocusGuardSettings(
          enabled: true,
          dailyBudgetMinutes: 45,
          selectedPackages: ['org.example.game', 'org.example.chat'],
        ),
        at: source.clock.now(),
      );
      final bytes = (await source.backup.export()).bytes;
      final device = await monitoring();
      final permissionRequests = device.app.scheduler.permissionRequests;
      await device.backup.restore(
        BackupValidator.validate(BackupCodec.decode(bytes)),
      );
      await expectOff(
        device,
        apps: ['org.example.game', 'org.example.chat'],
        budget: 45,
      );
      expect(device.app.scheduler.permissionRequests, permissionRequests);
    });

    for (final (name, path) in [
      ('format 1', 'test/fixtures/phase5_backup_v1.nextrep'),
      ('format 2', 'test/fixtures/v1_1_backup_v2.nextrep'),
    ]) {
      test('$name (no Focus Guard section): defaults, off, the job '
          'cancelled', () async {
        final device = await monitoring();
        final bytes = Uint8List.fromList(File(path).readAsBytesSync());
        await device.backup.restore(
          BackupValidator.validate(BackupCodec.decode(bytes)),
        );
        await expectOff(device, apps: const [], budget: 60);
      });
    }

    test(
      'a failing cancel still restores, and leaves nothing to claim',
      () async {
        final device = await monitoring();
        final bytes = (await device.backup.export()).bytes;
        final failing = BackupService(
          store: device.app.backupStore,
          scheduler: device.app.scheduler,
          focusGuard: _FailingScheduler(),
          clock: device.app.clock,
          appVersion: '1.1.0',
        );
        await failing.restore(
          BackupValidator.validate(BackupCodec.decode(bytes)),
        );
        expect(
          (await DriftFocusGuardSettingsRepository(
            device.app.db,
          ).load()).enabled,
          isFalse,
        );
        expect(await _workerClaim(device.app.db, '2026-10-14'), isFalse);
      },
    );

    test('the documented exception: after a full restore, a user who turns '
        'Focus Guard on again may get a new nudge that local day', () async {
      final device = await monitoring();
      expect(
        (await DriftFocusGuardSettingsRepository(
          device.app.db,
        ).load()).lastNudgedOn,
        LocalDate(2026, 10, 14),
      );
      final bytes = (await device.backup.export()).bytes;
      await device.backup.restore(
        BackupValidator.validate(BackupCodec.decode(bytes)),
      );
      // The format-3 restore contract: off, no nudge on record, apps and
      // budget kept.
      final restored = await DriftFocusGuardSettingsRepository(device.app.db)
          .load();
      expect(restored.enabled, isFalse);
      expect(restored.lastNudgedOn, isNull);
      expect(restored.selectedPackages, _apps);
      expect(restored.dailyBudgetMinutes, 60);
      // Nothing can nudge until the user turns it on again.
      expect(await _workerClaim(device.app.db, '2026-10-14'), isFalse);
      final service = FocusGuardService(
        settings: DriftFocusGuardSettingsRepository(device.app.db),
        platform: FakeFocusGuardPlatform(access: UsageAccess.granted),
        background: device.background,
        notifications: device.app.scheduler,
        clock: device.app.clock,
      );
      await service.setEnabled(true);
      // Then that day's nudge is available again, once.
      expect(await _workerClaim(device.app.db, '2026-10-14'), isTrue);
      expect(await _workerClaim(device.app.db, '2026-10-14'), isFalse);
    });

    test(
      'a backup never carries the enabled state, the nudge or usage',
      () async {
        final device = await monitoring();
        final text = String.fromCharCodes((await device.backup.export()).bytes);
        expect(text, isNot(contains('enabled": true')));
        expect(text, isNot(contains('lastNudged')));
        expect(text, isNot(contains('2026-10-14"')));
        expect(text, isNot(contains('usage')));
      },
    );
  });
}

final class _FailingScheduler implements FocusGuardBackgroundScheduler {
  @override
  Future<void> ensureScheduled() async {}

  @override
  Future<void> cancel() async => throw StateError('cancel failed');
}
