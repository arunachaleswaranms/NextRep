import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';
import '../support/seasonal_backup.dart';

typedef Json = Map<String, dynamic>;

/// Genuine older files: Phase 5's encoder (format 1) and v1.1's (format 2).
Uint8List _v1Fixture() =>
    File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync();
Uint8List _v2Fixture() =>
    File('test/fixtures/v1_1_backup_v2.nextrep').readAsBytesSync();

Json _json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Json;

Uint8List _mutate(Uint8List bytes, void Function(Json json) change) {
  final json = _json(bytes);
  change(json);
  final body = {...json}..remove('checksum');
  json['checksum'] = {
    'algorithm': 'sha256',
    'value': BackupCodec.checksumOf(body),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Json _data(Json json) => json['data'] as Json;

ValidatedBackup _read(Uint8List bytes) =>
    BackupValidator.validate(BackupCodec.decode(bytes));

Matcher _rejectedAs(BackupProblem problem) =>
    throwsA(isA<BackupFailure>().having((f) => f.problem, 'problem', problem));

/// Synthetic package names; never anyone's real app list.
const _apps = ['org.example.video', 'org.example.chat', 'org.example.game'];

TestApp _empty(DateTime now) {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(now),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  return app;
}

/// Turns Hydration Coach on (Gentle, 06:30 – 21:00) and gives [app] a
/// Focus Guard configuration that is on and has nudged today.
Future<void> _configureV12(TestApp app) async {
  await app.reminders.update(
    (p) => p.copyWith(
      hydrationEnabled: true,
      hydrationMode: HydrationMode.gentle,
      hydrationWindow: HydrationWindow(
        const ReminderTime(6, 30),
        const ReminderTime(21, 0),
      ),
    ),
  );
  await DriftFocusGuardSettingsRepository(app.db).save(
    FocusGuardSettings(
      enabled: true,
      dailyBudgetMinutes: 45,
      selectedPackages: _apps,
      lastNudgedOn: app.clock.today(),
    ),
    at: app.clock.now(),
  );
}

/// [seasonalSource] configured by [_configureV12].
Future<TestApp> _v12Source() async {
  final app = await seasonalSource();
  addTearDown(app.db.close);
  await _configureV12(app);
  return app;
}

void main() {
  late Uint8List v3;

  setUpAll(() async {
    final app = await seasonalSource();
    await _configureV12(app);
    v3 = (await app.backup.export()).bytes;
    await app.db.close();
  });

  group('writing format 3', () {
    test('the app writes format 3 and reads 1, 2 and 3', () {
      expect(BackupFormat.formatVersion, 3);
      expect(BackupFormat.readableVersions, {1, 2, 3});
      expect(_json(v3)['formatVersion'], 3);
    });

    test('hydration: hours and style, never whether it is on', () {
      final reminders = _data(_json(v3))['reminders'] as Json;
      expect(reminders, {
        'dailyTime': '07:15',
        'reflectionTime': '22:30',
        'hydrationStart': '06:30',
        'hydrationEnd': '21:00',
        'hydrationMode': 'gentle',
      });
    });

    test('Focus Guard: budget and package names, never whether it is on, '
        'its last nudge or any usage', () {
      final focusGuard = _data(_json(v3))['focusGuard'] as Json;
      expect(focusGuard, {'dailyBudgetMinutes': 45, 'selectedApps': _apps});
      final text = utf8.decode(v3);
      expect(text, isNot(contains('lastNudged')));
      expect(text, isNot(contains('usage')));
      expect(text, isNot(contains('hydrationEnabled')));
    });

    test('nothing configured: both are null', () async {
      final app = _empty(DateTime(2026, 10, 4, 9));
      final json = _json((await app.backup.export()).bytes);
      expect(_data(json)['reminders'], isNull);
      expect(_data(json)['focusGuard'], isNull);
      expect(_data(json).keys, {'arcs', 'reminders', 'focusGuard'});
    });

    test('it decodes to what was written, deterministically', () {
      final backup = _read(v3);
      final reminders = backup.data.reminders!;
      expect(reminders.hydrationMode, HydrationMode.gentle);
      expect(
        reminders.hydrationWindow,
        HydrationWindow(const ReminderTime(6, 30), const ReminderTime(21, 0)),
      );
      expect(backup.data.focusGuard!.dailyBudgetMinutes, 45);
      expect(backup.data.focusGuard!.selectedPackages, _apps);
      expect(BackupCodec.encode(BackupCodec.decode(v3)), v3);
    });
  });

  group('reading format 3', () {
    void rejects(void Function(Json json) change, {String? reason}) => expect(
      () => _read(_mutate(v3, change)),
      _rejectedAs(BackupProblem.invalidData),
      reason: reason,
    );
    Json reminders(Json json) => _data(json)['reminders'] as Json;
    Json focusGuard(Json json) => _data(json)['focusGuard'] as Json;

    test('an invalid Hydration Coach window', () {
      for (final (start, end) in [
        ('21:00', '06:30'), // overnight
        ('08:00', '15:59'), // under 8 hours
        ('05:00', '23:01'), // over 18 hours
        ('08:00', '08:00'),
        ('8:00', '20:00'),
        ('08:00', '24:00'),
      ]) {
        rejects((json) {
          reminders(json)
            ..['hydrationStart'] = start
            ..['hydrationEnd'] = end;
        }, reason: '$start–$end');
      }
    });

    test('an unknown mode, a missing or an extra field', () {
      rejects((json) => reminders(json)['hydrationMode'] = 'Balanced');
      rejects((json) => reminders(json)['hydrationMode'] = null);
      rejects((json) => reminders(json).remove('hydrationEnd'));
      rejects((json) => reminders(json)['hydrationEnabled'] = true);
      rejects((json) => _data(json).remove('focusGuard'));
    });

    test('Focus Guard keeps to its rules', () {
      rejects((json) => focusGuard(json)['enabled'] = false);
      rejects((json) => focusGuard(json)['lastNudgedOn'] = '2026-10-16');
      rejects((json) => focusGuard(json)['dailyBudgetMinutes'] = 0);
      rejects((json) => focusGuard(json)['dailyBudgetMinutes'] = 1441);
      rejects((json) => focusGuard(json)['selectedApps'] = ['not a package']);
      rejects(
        (json) => focusGuard(json)['selectedApps'] = [
          'org.example.a',
          'org.example.a',
        ],
      );
      rejects((json) => focusGuard(json)['selectedApps'] = [42]);
      rejects((json) => focusGuard(json)['selectedApps'] = ['']);
      rejects(
        (json) => focusGuard(json)['selectedApps'] = [
          for (var i = 0; i <= FocusGuardRules.maxSelectedApps; i++)
            'org.example.app$i',
        ],
      );
      expect(
        _read(
          _mutate(v3, (json) => focusGuard(json)['selectedApps'] = <String>[]),
        ).data.focusGuard!.selectedPackages,
        isEmpty,
      );
    });

    test(
      'formats 1 and 2 stay frozen: no hydration fields, no Focus Guard',
      () {
        for (final fixture in [_v1Fixture(), _v2Fixture()]) {
          final rejectsOld = [
            (Json json) =>
                (_data(json)['reminders'] as Json)['hydrationMode'] = 'gentle',
            (Json json) => _data(json)['focusGuard'] = null,
          ];
          for (final change in rejectsOld) {
            expect(
              () => _read(_mutate(fixture, change)),
              _rejectedAs(BackupProblem.invalidData),
            );
          }
        }
      },
    );

    test('a newer format is refused before anything is read', () {
      final future = _mutate(v3, (json) => json['formatVersion'] = 4);
      expect(
        () => _read(future),
        _rejectedAs(BackupProblem.unsupportedVersion),
      );
    });
  });

  group('restoring', () {
    test('a format-3 backup: every reminder and Focus Guard off, settings '
        'kept, nothing scheduled, nothing asked', () async {
      final target = _empty(DateTime(2026, 10, 16, 21));
      final scheduler = target.scheduler;
      final outcome = await target.backup.restore(
        await target.backup.inspect(v3),
      );
      expect(outcome.remindersCleared, isTrue);
      expect(scheduler.pending, isEmpty);
      expect(scheduler.permissionRequests, 0);

      final prefs = await target.reminderStore.load();
      expect(prefs.dailyEnabled, isFalse);
      expect(prefs.reflectionEnabled, isFalse);
      expect(prefs.hydrationEnabled, isFalse);
      expect(prefs.dailyTime, const ReminderTime(7, 15));
      expect(prefs.hydrationMode, HydrationMode.gentle);
      expect(
        prefs.hydrationWindow,
        HydrationWindow(const ReminderTime(6, 30), const ReminderTime(21, 0)),
      );

      final focusGuard = await DriftFocusGuardSettingsRepository(target.db)
          .load();
      expect(focusGuard.enabled, isFalse);
      expect(focusGuard.lastNudgedOn, isNull);
      expect(focusGuard.dailyBudgetMinutes, 45);
      expect(focusGuard.selectedPackages, _apps);

      await target.reminders.reconcile();
      expect(scheduler.pending, isEmpty, reason: 'still nothing to plan');
    });

    test('a format-3 round trip gives back the same data', () async {
      final target = _empty(DateTime(2026, 10, 16, 21));
      await target.backup.restore(await target.backup.inspect(v3));
      final again = (await target.backup.export()).bytes;
      expect(_data(_json(again)), _data(_json(v3)));
    });

    test(
      'a restore replaces Focus Guard and hydration settings entirely',
      () async {
        final target = await _v12Source();
        // A backup with neither reminder settings nor Focus Guard.
        final empty = _empty(DateTime(2026, 10, 16, 21));
        final bytes = (await empty.backup.export()).bytes;
        await target.backup.restore(await target.backup.inspect(bytes));
        expect(
          await target.db.select(target.db.focusGuardPrefs).get(),
          isEmpty,
        );
        expect(
          await target.db.select(target.db.focusGuardSelectedApps).get(),
          isEmpty,
        );
        expect(await target.reminderStore.load(), ReminderPreferences.defaults);
      },
    );

    for (final (name, fixture, daily) in [
      ('format-1 (Phase 5)', _v1Fixture, null),
      ('format-2 (v1.1)', _v2Fixture, const ReminderTime(7, 15)),
    ]) {
      test('a $name backup restores into schema v6 with Hydration Coach off '
          'at its defaults and no Focus Guard', () async {
        final target = await _v12Source();
        await target.backup.restore(await target.backup.inspect(fixture()));
        expect(target.scheduler.pending, isEmpty);
        final prefs = await target.reminderStore.load();
        expect(prefs.anyEnabled, isFalse);
        if (daily != null) expect(prefs.dailyTime, daily);
        expect(prefs.hydrationWindow, HydrationWindow.defaults);
        expect(prefs.hydrationMode, HydrationMode.balanced);
        final focusGuard = await DriftFocusGuardSettingsRepository(target.db)
            .load();
        expect(focusGuard.enabled, isFalse);
        expect(focusGuard.selectedPackages, isEmpty);
        final sessions = await target.sessions.listSessions();
        expect(sessions, hasLength(2));
        expect(
          sessions.where((s) => s.status == WinterArcStatus.completed),
          hasLength(1),
        );
      });
    }

    test('the format-2 fixture keeps its seasonal arc and join day', () async {
      final target = _empty(DateTime(2026, 10, 16, 21));
      await target.backup.restore(await target.backup.inspect(_v2Fixture()));
      final today = await target.tracking.today();
      expect(today.session.kind, ArcKind.seasonalWinter);
      expect(today.session.participationStartDate, LocalDate(2026, 10, 15));
    });
  });
}
