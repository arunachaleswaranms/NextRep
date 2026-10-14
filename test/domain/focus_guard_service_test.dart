import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_meter.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/focus_guard/today_usage.dart';

import '../support/fakes.dart';

/// Synthetic package names only; never anyone's real app list.
const _video = 'org.example.video';
const _chat = 'org.example.chat';
const _game = 'org.example.game';

final class _Harness {
  _Harness({UsageAccess access = UsageAccess.granted}) {
    platform.access = access;
  }

  final db = memoryDatabase();
  final clock = FakeClock(DateTime(2026, 10, 14, 18));
  final platform = FakeFocusGuardPlatform();
  final background = FakeFocusGuardBackgroundScheduler();
  final notifications = FakeReminderScheduler(granted: true);

  late final repo = DriftFocusGuardSettingsRepository(db);
  late final service = FocusGuardService(
    settings: repo,
    platform: platform,
    background: background,
    notifications: notifications,
    clock: clock,
  );

  /// The app after a restart: same database, nothing in memory.
  FocusGuardService restarted() => FocusGuardService(
    settings: DriftFocusGuardSettingsRepository(db),
    platform: platform,
    background: background,
    notifications: notifications,
    clock: clock,
  );
}

_Harness _harness({UsageAccess access = UsageAccess.granted}) {
  final h = _Harness(access: access);
  addTearDown(h.db.close);
  return h;
}

void main() {
  group('A. configuration', () {
    test(
      'off by default, 60 minutes, nothing selected; no Arc needed',
      () async {
        final h = _harness();
        final status = await h.service.status();
        expect(status.settings.enabled, isFalse);
        expect(status.settings.dailyBudgetMinutes, 60);
        expect(status.settings.selectedPackages, isEmpty);
        expect(status.settings.lastNudgedOn, isNull);
        expect(status.monitoring, isFalse);
      },
    );

    test('budget: 1 to 1440 minutes; anything else saves nothing', () async {
      final h = _harness();
      await h.service.setDailyBudget(1);
      await h.service.setDailyBudget(1440);
      expect((await h.repo.load()).dailyBudgetMinutes, 1440);
      for (final bad in [0, -5, 1441, 100000]) {
        await expectLater(
          h.service.setDailyBudget(bad),
          throwsA(
            isA<DomainFailure>().having(
              (f) => f.rule,
              'rule',
              DomainRule.invalidFocusGuardBudget,
            ),
          ),
        );
      }
      expect((await h.repo.load()).dailyBudgetMinutes, 1440);
    });

    test('several apps, in order, duplicates dropped', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video, _chat, _video, _game, _chat]);
      expect((await h.repo.load()).selectedPackages, [_video, _chat, _game]);
    });

    test('malformed names and more than 100 apps are refused', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      for (final bad in [
        ['not a package'],
        ['.org.example'],
        ['org'],
        [_chat, ''],
        [for (var i = 0; i <= 100; i++) 'org.example.app$i'],
      ]) {
        await expectLater(
          h.service.setSelectedApps(bad),
          throwsA(
            isA<DomainFailure>().having(
              (f) => f.rule,
              'rule',
              DomainRule.invalidFocusGuardApps,
            ),
          ),
        );
      }
      expect((await h.repo.load()).selectedPackages, [_video]);
      await h.service.setSelectedApps([
        for (var i = 0; i < 100; i++) 'org.example.app$i',
      ]);
      expect((await h.repo.load()).selectedPackages, hasLength(100));
    });

    test('enable, disable, re-enable; apps and budget kept; survives a '
        'restart', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video, _chat]);
      await h.service.setDailyBudget(45);
      expect(await h.service.setEnabled(true), FocusGuardToggle.on);
      expect((await h.restarted().status()).settings.enabled, isTrue);
      expect(await h.service.setEnabled(false), FocusGuardToggle.off);
      final off = (await h.restarted().status()).settings;
      expect(off.enabled, isFalse);
      expect(off.selectedPackages, [_video, _chat]);
      expect(off.dailyBudgetMinutes, 45);
      expect(await h.service.setEnabled(true), FocusGuardToggle.on);
    });

    test('apps and budget can be saved while off; nothing turns it on but '
        'setEnabled', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.setDailyBudget(30);
      await h.service.reconcile();
      expect((await h.repo.load()).enabled, isFalse);
      expect(h.background.scheduled, isFalse);
    });

    test('configuration changes keep the day\'s nudge record', () async {
      final h = _harness();
      await h.repo.save(
        FocusGuardSettings(
          enabled: true,
          dailyBudgetMinutes: 60,
          selectedPackages: const [_video],
          lastNudgedOn: LocalDate(2026, 10, 14),
        ),
        at: h.clock.now(),
      );
      await h.service.setDailyBudget(90);
      await h.service.setSelectedApps([_video, _chat]);
      await h.service.setEnabled(false);
      await h.service.setEnabled(true);
      expect((await h.repo.load()).lastNudgedOn, LocalDate(2026, 10, 14));
    });
  });

  group('B. permissions', () {
    test('unsupported platform: hidden, never on, nothing scheduled', () async {
      final h = _harness(access: UsageAccess.unsupported);
      await h.service.setSelectedApps([_video]);
      final status = await h.service.status();
      expect(status.supported, isFalse);
      expect(status.nudgesAllowed, isFalse);
      expect(await h.service.setEnabled(true), FocusGuardToggle.unsupported);
      expect((await h.repo.load()).enabled, isFalse);
      expect(h.background.scheduled, isFalse);
      expect(h.notifications.permissionRequests, 0);
    });

    test('without Usage Access it does not turn on', () async {
      final h = _harness(access: UsageAccess.notGranted);
      await h.service.setSelectedApps([_video]);
      expect(
        await h.service.setEnabled(true),
        FocusGuardToggle.needsUsageAccess,
      );
      expect((await h.repo.load()).enabled, isFalse);
      expect(h.platform.settingsOpened, 0);
    });

    test('without apps it does not turn on', () async {
      final h = _harness();
      expect(await h.service.setEnabled(true), FocusGuardToggle.needsApps);
      expect((await h.repo.load()).enabled, isFalse);
    });

    test('a failing access check counts as not granted', () async {
      final h = _harness();
      h.platform.failAccessCheck = true;
      await h.service.setSelectedApps([_video]);
      expect((await h.service.status()).access, UsageAccess.notGranted);
      expect(
        await h.service.setEnabled(true),
        FocusGuardToggle.needsUsageAccess,
      );
    });

    test('notifications and Usage Access are separate: denied notifications '
        'still turn it on, measuring without nudges', () async {
      final h = _harness();
      h.platform.nudges = false;
      h.notifications
        ..granted = false
        ..grant = false;
      await h.service.setSelectedApps([_video]);
      expect(
        await h.service.setEnabled(true),
        FocusGuardToggle.onWithoutNudges,
      );
      expect(h.notifications.permissionRequests, 1);
      expect((await h.repo.load()).enabled, isTrue);
      expect(h.background.scheduled, isTrue);
      final status = await h.service.status();
      expect(status.access, UsageAccess.granted);
      expect(status.nudgesAllowed, isFalse);
    });

    test('permission is asked for only when turning on, and only if not '
        'already granted', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.status();
      await h.service.today();
      await h.service.reconcile();
      expect(h.notifications.permissionRequests, 0);
      expect(await h.service.setEnabled(true), FocusGuardToggle.on);
      expect(h.notifications.permissionRequests, 0);
      // Granted for the app, but the Focus Guard channel is blocked: no
      // prompt (Android wouldn't show one), it's on without nudges.
      h.platform.nudges = false;
      await h.service.setEnabled(false);
      expect(
        await h.service.setEnabled(true),
        FocusGuardToggle.onWithoutNudges,
      );
      expect(h.notifications.permissionRequests, 0);
    });

    test(
      'nothing opens Usage Access settings except the user action',
      () async {
        final h = _harness(access: UsageAccess.notGranted);
        await h.service.setSelectedApps([_video]);
        await h.service.status();
        await h.service.today();
        await h.service.reconcile();
        await h.service.setEnabled(true);
        expect(h.platform.settingsOpened, 0);
        await h.service.openUsageAccessSettings();
        expect(h.platform.settingsOpened, 1);
      },
    );
  });

  group('C. app picker', () {
    test('launcher apps only, without NextRep, one per package, sorted, '
        'blank labels fall back', () async {
      final h = _harness();
      h.platform.apps = const [
        LaunchableAppCandidate(packageName: _video, label: 'Video'),
        LaunchableAppCandidate(packageName: nextRepPackage, label: 'NextRep'),
        LaunchableAppCandidate(packageName: _chat, label: 'chat'),
        LaunchableAppCandidate(packageName: _chat, label: 'Chat (2)'),
        LaunchableAppCandidate(packageName: _game, label: '  '),
        LaunchableAppCandidate(packageName: 'bad name', label: 'Broken'),
      ];
      expect(await h.service.pickableApps(), const [
        LaunchableAppCandidate(packageName: _chat, label: 'chat'),
        LaunchableAppCandidate(packageName: _game, label: _game),
        LaunchableAppCandidate(packageName: _video, label: 'Video'),
      ]);
    });

    test('no launchable apps: an empty list', () async {
      final h = _harness();
      expect(await h.service.pickableApps(), isEmpty);
    });
  });

  group('D. today\'s usage', () {
    Future<_Harness> on({List<String> apps = const [_video, _chat]}) async {
      final h = _harness();
      await h.service.setSelectedApps(apps);
      await h.service.setEnabled(true);
      return h;
    }

    test('combined across the selected apps only, from local midnight to '
        'now', () async {
      final h = await on();
      h.platform.usage = const {
        _video: Duration(minutes: 20),
        _chat: Duration(minutes: 25),
        _game: Duration(minutes: 300),
      };
      final today = await h.service.today();
      expect(
        today.usage,
        UsageMeasured(
          day: LocalDate(2026, 10, 14),
          total: const Duration(minutes: 45),
        ),
      );
      final query = h.platform.queries.single;
      expect(query.packages, {_video, _chat});
      expect(query.from, DateTime(2026, 10, 14));
      expect(query.to, h.clock.now());
    });

    test('zero usage is a real zero only with access', () async {
      final h = await on();
      expect(
        (await h.service.today()).usage,
        UsageMeasured(day: LocalDate(2026, 10, 14), total: Duration.zero),
      );
      h.platform.access = UsageAccess.notGranted;
      expect(
        (await h.service.today()).usage,
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
    });

    test('revoked during the query: unavailable, never zero', () async {
      final h = await on();
      h.platform.usage = const {_video: Duration(minutes: 30)};
      h.platform.duringQuery = () => h.platform.access = UsageAccess.notGranted;
      expect(
        (await h.service.today()).usage,
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
    });

    test('a failed query: unavailable, not an older value', () async {
      final h = await on();
      h.platform.usage = const {_video: Duration(minutes: 30)};
      expect((await h.service.today()).usage, isA<UsageMeasured>());
      h.platform.failQuery = true;
      expect(
        (await h.service.today()).usage,
        const UsageUnavailable(UsageUnavailableReason.failed),
      );
    });

    test('off or without apps: nothing is measured', () async {
      final h = _harness();
      expect((await h.service.today()).usage, isNull);
      await h.service.setSelectedApps([_video]);
      expect((await h.service.today()).usage, isNull);
      expect(h.platform.queries, isEmpty);
    });

    test('an uninstalled app simply has no usage', () async {
      final h = await on(apps: [_video, 'org.example.removed']);
      h.platform.usage = const {_video: Duration(minutes: 12)};
      expect(
        (await h.service.today()).usage,
        UsageMeasured(
          day: LocalDate(2026, 10, 14),
          total: const Duration(minutes: 12),
        ),
      );
    });

    test('local midnight starts a new day without anything reset', () async {
      final h = await on();
      h.clock.current = DateTime(2026, 10, 15, 0, 5);
      await h.service.today();
      expect(h.platform.queries.last.from, DateTime(2026, 10, 15));
      expect(
        ((await h.service.today()).usage! as UsageMeasured).day,
        LocalDate(2026, 10, 15),
      );
    });
  });

  group('E. background work', () {
    test('runs only while on, with apps, a budget and Usage Access', () async {
      final h = _harness();
      await h.service.reconcile();
      expect(h.background.scheduled, isFalse);
      await h.service.setSelectedApps([_video]);
      expect(h.background.scheduled, isFalse);
      await h.service.setEnabled(true);
      expect(h.background.scheduled, isTrue);
    });

    test('repeated reconciliation keeps one job (KEEP is the native side\'s '
        'job; the domain only ensures)', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.setEnabled(true);
      final cancels = h.background.cancelCalls;
      for (var i = 0; i < 5; i++) {
        await h.service.reconcile();
      }
      expect(h.background.scheduled, isTrue);
      expect(h.background.cancelCalls, cancels);
    });

    test('disable cancels; re-enable schedules again', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.setEnabled(true);
      await h.service.setEnabled(false);
      expect(h.background.scheduled, isFalse);
      await h.service.setEnabled(true);
      expect(h.background.scheduled, isTrue);
    });

    test('revoked Usage Access cancels on the next reconcile; re-granted '
        'restores it, still on', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.setEnabled(true);
      h.platform.access = UsageAccess.notGranted;
      expect(await h.service.reconcile(), isFalse);
      expect(h.background.scheduled, isFalse);
      expect((await h.repo.load()).enabled, isTrue);
      h.platform.access = UsageAccess.granted;
      expect(await h.service.reconcile(), isTrue);
      expect(h.background.scheduled, isTrue);
    });

    test('removing every app stops the job', () async {
      final h = _harness();
      await h.service.setSelectedApps([_video]);
      await h.service.setEnabled(true);
      await h.service.setSelectedApps([]);
      expect(h.background.scheduled, isFalse);
    });
  });

  group('meter', () {
    FocusGuardMeter meter(Duration used, [int budget = 60]) =>
        FocusGuardMeter(used: used, budgetMinutes: budget);

    test('0 minutes: shield strong, all remaining', () {
      final m = meter(Duration.zero);
      expect(m.shield, FocusGuardShield.strong);
      expect((m.usedMinutes, m.remainingMinutes), (0, 60));
      expect(m.fraction, 0);
    });

    test('38 / 60: 22 remaining, shield strong', () {
      final m = meter(const Duration(minutes: 38));
      expect((m.usedMinutes, m.remainingMinutes), (38, 22));
      expect(m.shield, FocusGuardShield.strong);
    });

    test('near the limit from 80 % of the budget, by exact durations', () {
      expect(
        meter(const Duration(minutes: 48) - const Duration(microseconds: 1))
            .shield,
        FocusGuardShield.strong,
      );
      expect(
        meter(const Duration(minutes: 48)).shield,
        FocusGuardShield.nearLimit,
      );
      expect(
        meter(const Duration(minutes: 59, seconds: 59)).shield,
        FocusGuardShield.nearLimit,
      );
    });

    test('rounding never reaches the budget early or shows 0 remaining', () {
      final m = meter(
        const Duration(minutes: 59, seconds: 59, milliseconds: 999),
      );
      expect(m.reached, isFalse);
      expect((m.usedMinutes, m.remainingMinutes), (59, 1));
    });

    test('exactly the budget and over it: reached', () {
      for (final used in [
        const Duration(minutes: 60),
        const Duration(minutes: 75),
        const Duration(hours: 5),
      ]) {
        final m = meter(used);
        expect(m.reached, isTrue);
        expect(m.shield, FocusGuardShield.reached);
        expect(m.remainingMinutes, 0);
        expect(m.fraction, 1);
      }
      expect(meter(const Duration(minutes: 75)).usedMinutes, 75);
    });

    test('a one-minute budget', () {
      expect(
        meter(const Duration(seconds: 47), 1).shield,
        FocusGuardShield.strong,
      );
      expect(
        meter(const Duration(seconds: 48), 1).shield,
        FocusGuardShield.nearLimit,
      );
      expect(
        meter(const Duration(seconds: 60), 1).shield,
        FocusGuardShield.reached,
      );
    });
  });
}
