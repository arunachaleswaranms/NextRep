import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_background.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/launchable_apps.dart';
import 'package:nextrep/domain/focus_guard/today_usage.dart';

import '../support/fakes.dart';

const _a = 'com.example.alpha';
const _b = 'com.example.bravo';
const _c = 'com.example.charlie';

LaunchableAppCandidate _app(String packageName, String label) =>
    LaunchableAppCandidate(packageName: packageName, label: label);

void main() {
  group('LocalDayWindow', () {
    test('runs from local midnight of the same calendar day to now', () {
      final window = LocalDayWindow.endingAt(DateTime(2026, 11, 3, 14, 25));
      expect(window.day, LocalDate(2026, 11, 3));
      expect(window.start, DateTime(2026, 11, 3));
      expect(window.end, DateTime(2026, 11, 3, 14, 25));
      expect(window.length, const Duration(hours: 14, minutes: 25));
      expect(window.start.isUtc, isFalse);
    });

    test('is empty at midnight and almost a full day just before it', () {
      expect(
        LocalDayWindow.endingAt(DateTime(2026, 11, 3)).length,
        Duration.zero,
      );
      final late = LocalDayWindow.endingAt(DateTime(2026, 11, 3, 23, 59, 59));
      expect(late.day, LocalDate(2026, 11, 3));
      expect(late.length, const Duration(hours: 23, minutes: 59, seconds: 59));
    });

    test('a new day starts a new window', () {
      final before = LocalDayWindow.endingAt(DateTime(2026, 12, 31, 23, 59));
      final after = LocalDayWindow.endingAt(DateTime(2027, 1, 1, 0, 1));
      expect(after.day, before.day.addDays(1));
      expect(after.start, DateTime(2027, 1, 1));
      expect(after.length, const Duration(minutes: 1));
    });

    test('keeps the zone of now', () {
      final window = LocalDayWindow.endingAt(DateTime.utc(2026, 11, 3, 6));
      expect(window.start, DateTime.utc(2026, 11, 3));
      expect(window.start.isUtc, isTrue);
    });
  });

  group('TodayUsageReader', () {
    late FakeClock clock;
    late FakeFocusGuardPlatform platform;
    late TodayUsageReader reader;

    setUp(() {
      clock = FakeClock(DateTime(2026, 11, 3, 15));
      platform = FakeFocusGuardPlatform(
        access: UsageAccess.granted,
        usage: {
          _a: const Duration(minutes: 20),
          _b: const Duration(minutes: 18),
          _c: const Duration(minutes: 40),
        },
      );
      reader = TodayUsageReader(platform: platform, clock: clock);
    });

    test('adds up only the selected apps, for today so far', () async {
      expect(
        await reader.read({_a, _b}),
        UsageMeasured(
          day: LocalDate(2026, 11, 3),
          total: const Duration(minutes: 38),
        ),
      );
      final query = platform.queries.single;
      expect(query.packages, {_a, _b});
      expect(query.from, DateTime(2026, 11, 3));
      expect(query.to, DateTime(2026, 11, 3, 15));
    });

    test('a selected app without usage today counts as zero', () async {
      platform.usage = const {};
      expect(
        await reader.read({_a}),
        UsageMeasured(day: LocalDate(2026, 11, 3), total: Duration.zero),
      );
    });

    test('without Usage Access: unavailable, and nothing is queried', () async {
      platform.access = UsageAccess.notGranted;
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
      expect(platform.queries, isEmpty);
    });

    test(
      'on an unsupported platform: unavailable, and nothing is queried',
      () async {
        final unsupported = TodayUsageReader(
          platform: const UnsupportedFocusGuardPlatform(),
          clock: clock,
        );
        expect(
          await unsupported.read({_a}),
          const UsageUnavailable(UsageUnavailableReason.unsupported),
        );
      },
    );

    test('revoking access makes the next read unavailable, not the last '
        'total', () async {
      expect(await reader.read({_a}), isA<UsageMeasured>());
      platform.access = UsageAccess.notGranted;
      clock.advance(const Duration(minutes: 15));
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
      // Granted again: measured afresh.
      platform.access = UsageAccess.granted;
      expect(
        await reader.read({_a}),
        UsageMeasured(
          day: LocalDate(2026, 11, 3),
          total: const Duration(minutes: 20),
        ),
      );
    });

    test('access revoked while the query runs: its empty answer is not '
        'reported as zero', () async {
      platform.duringQuery = () => platform.access = UsageAccess.notGranted;
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
    });

    test('a failing query is unavailable, never zero', () async {
      platform.failQuery = true;
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.failed),
      );
      platform.duringQuery = () => platform.access = UsageAccess.notGranted;
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
    });

    test('a failing access check counts as no access', () async {
      platform.failAccessCheck = true;
      expect(
        await reader.read({_a}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
      expect(platform.queries, isEmpty);
    });

    test(
      'no selected apps, or midnight exactly: zero without a query',
      () async {
        expect(
          await reader.read(const {}),
          UsageMeasured(day: LocalDate(2026, 11, 3), total: Duration.zero),
        );
        clock.current = DateTime(2026, 11, 4);
        expect(
          await reader.read({_a}),
          UsageMeasured(day: LocalDate(2026, 11, 4), total: Duration.zero),
        );
        expect(platform.queries, isEmpty);
      },
    );

    test('still checks access when nothing is selected', () async {
      platform.access = UsageAccess.notGranted;
      expect(
        await reader.read(const {}),
        const UsageUnavailable(UsageUnavailableReason.accessRequired),
      );
    });

    test('the total restarts at local midnight', () async {
      clock.current = DateTime(2026, 11, 3, 23, 59);
      expect(await reader.read({_a}), isA<UsageMeasured>());
      clock.current = DateTime(2026, 11, 4, 0, 10);
      platform.usage = {_a: const Duration(minutes: 3)};
      expect(
        await reader.read({_a}),
        UsageMeasured(
          day: LocalDate(2026, 11, 4),
          total: const Duration(minutes: 3),
        ),
      );
      expect(platform.queries.last.from, DateTime(2026, 11, 4));
    });

    test('combine ignores unselected and negative values and never exceeds '
        'the window', () {
      const window = Duration(hours: 1);
      expect(
        TodayUsageReader.combine(
          {
            _a: const Duration(minutes: 10),
            _b: const Duration(minutes: -5),
            _c: const Duration(minutes: 30),
          },
          {_a, _b},
          window,
        ),
        const Duration(minutes: 10),
      );
      // One app over the window, and split-screen apps adding up past it.
      expect(
        TodayUsageReader.combine({_a: const Duration(hours: 2)}, {_a}, window),
        window,
      );
      expect(
        TodayUsageReader.combine(
          {_a: const Duration(minutes: 40), _b: const Duration(minutes: 40)},
          {_a, _b},
          window,
        ),
        window,
      );
    });
  });

  group('LaunchableApps.forPicker', () {
    test('one entry per package, sorted by label, without NextRep', () {
      final apps = LaunchableApps.forPicker([
        _app(_c, 'charlie'),
        _app('com.nextrep.nextrep', 'NextRep'),
        _app(_a, 'Alpha'),
        _app(_a, 'Alpha Settings'),
        _app(_b, 'Bravo'),
      ], ownPackage: 'com.nextrep.nextrep');
      expect(apps, [_app(_a, 'Alpha'), _app(_b, 'Bravo'), _app(_c, 'charlie')]);
    });

    test('drops malformed package names and trims', () {
      final apps = LaunchableApps.forPicker([
        _app('', 'Empty'),
        _app('nodots', 'No dots'),
        _app('com..double', 'Double dot'),
        _app('1com.example', 'Digit first'),
        _app('com.example.ok ', ' OK '),
      ], ownPackage: 'com.nextrep.nextrep');
      expect(apps, [_app('com.example.ok', 'OK')]);
    });

    test('a blank label falls back to the package name, and a later real '
        'label replaces it', () {
      expect(
        LaunchableApps.forPicker([
          _app(_a, '  '),
        ], ownPackage: 'com.nextrep.nextrep'),
        [_app(_a, _a)],
      );
      expect(
        LaunchableApps.forPicker([
          _app(_a, ''),
          _app(_a, 'Alpha'),
          _app(_a, ''),
        ], ownPackage: 'com.nextrep.nextrep'),
        [_app(_a, 'Alpha')],
      );
    });

    test('equal labels sort by package name; empty input is empty', () {
      expect(
        LaunchableApps.forPicker([
          _app(_b, 'Same'),
          _app(_a, 'same'),
        ], ownPackage: 'com.nextrep.nextrep').map((a) => a.packageName),
        [_a, _b],
      );
      expect(
        LaunchableApps.forPicker(const [], ownPackage: 'com.nextrep.nextrep'),
        isEmpty,
      );
    });

    test('the unsupported platform offers no apps', () async {
      expect(
        await const UnsupportedFocusGuardPlatform().launchableApps(),
        isEmpty,
      );
    });
  });

  group('FocusGuardBackground', () {
    test('runs only when enabled, granted, with apps and a budget', () {
      bool run({
        bool enabled = true,
        UsageAccess access = UsageAccess.granted,
        int apps = 2,
        int budget = 60,
      }) => FocusGuardBackground.shouldRun(
        enabled: enabled,
        access: access,
        selectedApps: apps,
        dailyBudgetMinutes: budget,
      );
      expect(run(), isTrue);
      expect(run(enabled: false), isFalse);
      expect(run(access: UsageAccess.notGranted), isFalse);
      expect(run(access: UsageAccess.unsupported), isFalse);
      expect(run(apps: 0), isFalse);
      expect(run(budget: 0), isFalse);
    });

    test('reconcile schedules, keeps, and cancels on revocation', () async {
      final scheduler = FakeFocusGuardBackgroundScheduler();
      Future<bool> reconcile(UsageAccess access, {bool enabled = true}) =>
          FocusGuardBackground.reconcile(
            scheduler,
            enabled: enabled,
            access: access,
            selectedApps: 1,
            dailyBudgetMinutes: 60,
          );

      expect(await reconcile(UsageAccess.granted), isTrue);
      expect(await reconcile(UsageAccess.granted), isTrue);
      expect(scheduler.scheduled, isTrue);
      expect(scheduler.scheduleCalls, 2);

      expect(await reconcile(UsageAccess.notGranted), isFalse);
      expect(scheduler.scheduled, isFalse);

      expect(await reconcile(UsageAccess.granted), isTrue);
      expect(await reconcile(UsageAccess.granted, enabled: false), isFalse);
      expect(scheduler.scheduled, isFalse);
    });

    test('the disabled scheduler accepts calls and does nothing', () async {
      const scheduler = DisabledFocusGuardBackgroundScheduler();
      expect(
        await FocusGuardBackground.reconcile(
          scheduler,
          enabled: true,
          access: UsageAccess.unsupported,
          selectedApps: 1,
          dailyBudgetMinutes: 60,
        ),
        isFalse,
      );
      await scheduler.ensureScheduled();
    });
  });

  group('UnsupportedFocusGuardPlatform', () {
    test('reports unsupported and returns no usage', () async {
      const platform = UnsupportedFocusGuardPlatform();
      expect(await platform.usageAccess(), UsageAccess.unsupported);
      await platform.openUsageAccessSettings();
      expect(
        await platform.foregroundTime(
          {_a},
          from: DateTime(2026, 11, 3),
          to: DateTime(2026, 11, 3, 1),
        ),
        isEmpty,
      );
    });
  });
}
