import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app_info.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/data/local_notification_scheduler.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/reminder/reminder_service.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';
import '../support/focus_guard_worker.dart';

/// Phase 11E: every notification family configured at once (daily
/// reminder, evening reflection, Hydration Coach and Focus Guard), through
/// the real plugin-backed [LocalNotificationScheduler]. Android's side of
/// flutter_local_notifications is replaced by [_AndroidNotifications],
/// which keeps what Android would: alarms pending in the plugin's cache,
/// and notifications already shown in the shade, keyed like
/// NotificationManager by (tag, id).
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');
const _video = 'org.example.video';
const _chat = 'org.example.chat';

typedef _Shown = ({String? tag, int id});

final class _AndroidNotifications {
  _AndroidNotifications() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  bool granted = true;

  /// Alarms waiting to fire, by id, with what they were scheduled with.
  final pending = <int, Map<Object?, Object?>>{};

  /// What the shade shows.
  final shown = <_Shown>{};

  /// Every method the app called, in order.
  final calls = <String>[];
  final scheduledIds = <int>[];
  final cancelledIds = <int>[];

  void reset() {
    calls.clear();
    scheduledIds.clear();
    cancelledIds.clear();
  }

  /// The alarm for [id] fires: the plugin shows it and drops it from its
  /// cache of scheduled notifications.
  void deliver(int id) {
    expect(pending.remove(id), isNotNull, reason: 'id $id was not pending');
    shown.add((tag: null, id: id));
  }

  /// The native Focus Guard check posts its nudge (FocusGuardNotifier.kt).
  void postFocusGuardNudge() => shown.add(_focusGuardNudge);

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'initialize':
        return true;
      case 'getNotificationAppLaunchDetails':
        return null;
      case 'areNotificationsEnabled':
        return granted;
      case 'requestNotificationsPermission':
        return granted;
      case 'zonedSchedule':
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        scheduledIds.add(id);
        pending[id] = args;
        return null;
      case 'cancel':
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id']! as int;
        cancelledIds.add(id);
        pending.remove(id);
        // Android's cancel also removes a shown notification with that id
        // and tag (ScheduledNotificationReceiver / NotificationManager).
        shown.remove((tag: args['tag'] as String?, id: id));
        return null;
      case 'cancelAllPendingNotifications':
        pending.clear();
        return null;
      case 'cancelAll':
        // NotificationManager.cancelAll(): everything the app shows, the
        // Focus Guard nudge included.
        pending.clear();
        shown.clear();
        return null;
      case 'pendingNotificationRequests':
        return [
          for (final MapEntry(:key, :value) in pending.entries)
            {
              'id': key,
              'title': value['title'],
              'body': value['body'],
              'payload': value['payload'],
            },
        ];
    }
    throw MissingPluginException(call.method);
  }

  /// The Android channel each pending notification was scheduled on.
  Map<int, String> get channels => {
    for (final MapEntry(:key, :value) in pending.entries)
      key:
          (value['platformSpecifics']! as Map<Object?, Object?>)['channelId']!
              as String,
  };
}

/// Focus Guard's nudge as FocusGuardNotifier.kt posts it.
final _focusGuardNudge = (tag: _kotlinConst('NOTIFICATION_TAG'), id: 1);

String _kotlinConst(String name) {
  final match = RegExp('const val $name = "([^"]*)"')
      .firstMatch(focusGuardKotlin('FocusGuardNotifier.kt'));
  return match!.group(1)!;
}

int _kotlinIntConst(String name) => int.parse(
  RegExp('const val $name = (\\d+)')
      .firstMatch(focusGuardKotlin('FocusGuardNotifier.kt'))!
      .group(1)!,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AndroidNotifications android;
  late FakeClock clock;
  late TestApp app;
  late LocalNotificationScheduler scheduler;
  late ReminderService reminders;
  late FocusGuardService focusGuard;
  late FakeFocusGuardBackgroundScheduler background;
  late BackupService backup;

  /// A fresh "process": a new plugin-backed scheduler (it remembers only in
  /// memory what it scheduled) and services over the same database.
  Future<void> startProcess() async {
    scheduler = LocalNotificationScheduler(FlutterLocalNotificationsPlugin());
    await scheduler.initialize(onTap: (_) {});
    reminders = ReminderService(
      sessions: app.sessions,
      progress: app.progress,
      preferences: app.reminderStore,
      scheduler: scheduler,
      clock: clock,
    );
    focusGuard = FocusGuardService(
      settings: DriftFocusGuardSettingsRepository(app.db),
      platform: FakeFocusGuardPlatform(access: UsageAccess.granted),
      background: background,
      notifications: scheduler,
      clock: clock,
    );
    backup = BackupService(
      store: app.backupStore,
      scheduler: scheduler,
      focusGuard: background,
      clock: clock,
      appVersion: appVersion,
    );
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    android = _AndroidNotifications();

    // The plugin refuses to schedule in the past by the real clock, so the
    // scenario's "today" is tomorrow at 07:00: every reminder planned from
    // it lies in the real future, whatever time the suite runs.
    final now = DateTime.now();
    clock = FakeClock(DateTime(now.year, now.month, now.day + 1, 7));
    final db = memoryDatabase();
    addTearDown(db.close);
    app = TestApp(db, clock);
    background = FakeFocusGuardBackgroundScheduler();
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
    await startProcess();

    // Everything on: both reminders, Hydration Coach at its maximum, and
    // Focus Guard with two apps.
    expect(
      await reminders.update(
        (p) => p.copyWith(
          dailyEnabled: true,
          reflectionEnabled: true,
          hydrationEnabled: true,
          hydrationMode: HydrationMode.supportive,
        ),
      ),
      ReminderUpdate.saved,
    );
    await focusGuard.setSelectedApps(const [_video, _chat]);
    expect(await focusGuard.setEnabled(true), FocusGuardToggle.on);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> logWater() => app.tracking.perform(
    habitId: 'water',
    action: HabitAction.increment,
    date: clock.today(),
  );

  test('every family at once: four separate channels, ids that never '
      'collide, at most 63 pending', () {
    final channels = android.channels;
    expect(channels.length, lessThanOrEqualTo(ReminderPlanner.maxPending));
    final byChannel = <String, List<int>>{};
    for (final MapEntry(:key, :value) in channels.entries) {
      (byChannel[value] ??= []).add(key);
    }
    expect(byChannel.keys.toSet(), {
      'daily_reminder',
      'reflection_reminder',
      'hydration_coach',
    });
    expect(
      byChannel['daily_reminder'],
      everyElement(inInclusiveRange(100, 113)),
    );
    expect(
      byChannel['reflection_reminder'],
      everyElement(inInclusiveRange(200, 213)),
    );
    expect(
      byChannel['hydration_coach'],
      everyElement(inInclusiveRange(300, 364)),
    );
    // Supportive with the starter Water target of 8: five nudges on each
    // of the seven days.
    expect(byChannel['hydration_coach'], hasLength(7 * 5));

    // Focus Guard posts natively, on its own channel, under a tag: Android
    // keys notifications by (tag, id), so its id 1 can't meet the plugin's
    // untagged ids, and none of the plugin's channels is its channel.
    expect(_kotlinConst('CHANNEL_ID'), 'focus_guard');
    expect(_focusGuardNudge.tag, 'focus_guard');
    expect(_kotlinIntConst('NOTIFICATION_ID'), 1);
    expect(byChannel.keys, isNot(contains(_kotlinConst('CHANNEL_ID'))));
    for (final args in android.pending.values) {
      expect(args.containsKey('tag'), isFalse);
    }

    // Each family's tap payload is its own.
    final payloads = {
      for (final args in android.pending.values) args['payload'] as String,
    };
    expect(payloads, {'today', 'journal', 'hydration'});
    expect(payloads, isNot(contains(focusGuardTapPayload)));
    expect(ReminderKind.fromPayload(focusGuardTapPayload), isNull);
  });

  test('no reconciliation, restore or new process removes a notification '
      'already shown, of any family', () async {
    // A hydration nudge and today's daily reminder were delivered, and the
    // native check posted the Focus Guard nudge.
    final firstHydration = android.pending.keys.where((id) => id >= 300).first;
    android
      ..deliver(100)
      ..deliver(firstHydration)
      ..postFocusGuardNudge();
    final shown = {...android.shown};
    expect(shown, hasLength(3));

    clock.advance(const Duration(hours: 4));
    await logWater();
    await reminders.reconcile();
    await app.tracking.activateMinimumDay(date: clock.today());
    await reminders.reconcile();
    await app.tracking.returnToFullTargets(date: clock.today());
    await reminders.reconcile();
    await focusGuard.setDailyBudget(30);
    await focusGuard.setEnabled(false);
    await focusGuard.setEnabled(true);
    await reminders.update((p) => p.copyWith(hydrationEnabled: false));
    await reminders.update((p) => p.copyWith(hydrationEnabled: true));
    await startProcess(); // a relaunch: the first schedule replaces all
    await reminders.reconcile();
    expect(android.shown, shown);

    // Everything off (an empty plan), then a restore.
    await reminders.update(
      (p) => p.copyWith(
        dailyEnabled: false,
        reflectionEnabled: false,
        hydrationEnabled: false,
      ),
    );
    expect(android.pending, isEmpty);
    await backup.restore(await backup.inspect((await backup.export()).bytes));
    await reminders.reconcile();
    expect(android.pending, isEmpty);
    expect(android.shown, shown);
    expect(
      android.calls,
      isNot(contains('cancelAll')),
      reason: 'cancelAll would clear the Focus Guard nudge too',
    );
  });

  test('reconciling again changes nothing; a new process re-plans the same '
      'set without duplicates', () async {
    final before = Map.of(android.pending);
    android.reset();
    await reminders.reconcile();
    await focusGuard.reconcile();
    expect(android.scheduledIds, isEmpty);
    expect(android.cancelledIds, isEmpty);

    await startProcess();
    await reminders.reconcile();
    expect(android.pending.keys.toSet(), before.keys.toSet());
    for (final MapEntry(:key, :value) in before.entries) {
      expect(android.pending[key], value, reason: 'id $key');
    }
    // The same ids replace each other: never more than one alarm per id.
    expect(android.pending.length, before.length);
  });

  test('a Water log, Minimum Day or Focus Guard change touches only what it '
      'should', () async {
    final daily = {
      for (final id in android.pending.keys)
        if (id < 300) id: android.pending[id],
    };

    // Water: only hydration nudges are rescheduled or cancelled.
    android.reset();
    await logWater();
    await logWater();
    await logWater();
    await reminders.reconcile();
    expect(android.cancelledIds, isNotEmpty, reason: 'ahead of pace now');
    expect([
      ...android.scheduledIds,
      ...android.cancelledIds,
    ], everyElement(inInclusiveRange(300, 364)));
    expect({
      for (final id in android.pending.keys)
        if (id < 300) id: android.pending[id],
    }, daily);

    // Minimum Day: today's remaining nudges go (3 of 3 is complete), the
    // other days and the daily and evening reminders stay.
    android.reset();
    await app.tracking.activateMinimumDay(date: clock.today());
    await reminders.reconcile();
    expect(android.pending.keys.where((id) => id >= 300 && id < 310), isEmpty);
    expect(android.pending.keys.where((id) => id >= 310), hasLength(6 * 5));
    expect(android.cancelledIds, everyElement(inInclusiveRange(300, 309)));

    // Focus Guard's settings never touch the reminder plugin, and the
    // reminders never touch Focus Guard's background check.
    android.reset();
    final checks = (background.scheduleCalls, background.cancelCalls);
    await focusGuard.setDailyBudget(20);
    await focusGuard.setEnabled(false);
    await focusGuard.setEnabled(true);
    expect(android.scheduledIds, isEmpty);
    expect(android.cancelledIds, isEmpty);
    final prefs = await reminders.preferences();
    expect(prefs.hydrationEnabled, isTrue);
    expect(prefs.hydrationMode, HydrationMode.supportive);

    final afterFocusGuard = (background.scheduleCalls, background.cancelCalls);
    await reminders.update((p) => p.copyWith(hydrationEnabled: false));
    await reminders.update((p) => p.copyWith(dailyEnabled: false));
    expect((background.scheduleCalls, background.cancelCalls), afterFocusGuard);
    expect(afterFocusGuard, isNot(checks));
    final stored = await DriftFocusGuardSettingsRepository(app.db).load();
    expect(stored.enabled, isTrue);
    expect(stored.dailyBudgetMinutes, 20);
    expect(stored.selectedPackages, [_video, _chat]);
  });

  test('notifications denied: reminders still plan safely and Focus Guard '
      'still turns on; regranting changes nothing else', () async {
    android.granted = false;
    await startProcess();
    expect(await scheduler.permissionGranted(), isFalse);
    // Already-on reminders keep being reconciled; nothing throws.
    await reminders.reconcile();
    expect(android.pending, isNotEmpty);
    await focusGuard.setEnabled(false);
    expect(await focusGuard.setEnabled(true), FocusGuardToggle.on);

    android.granted = true;
    expect(await scheduler.permissionGranted(), isTrue);
    final prefs = await reminders.preferences();
    expect(
      (prefs.dailyEnabled, prefs.reflectionEnabled, prefs.hydrationEnabled),
      (true, true, true),
    );
  });

  test('tap routing: each family opens its own place, in every Arc state, '
      'and no payload is read as another family\'s', () {
    WinterArcSession arc(int id, WinterArcStatus status) => WinterArcSession(
      id: id,
      kind: ArcKind.rolling92,
      participationStartDate: status == WinterArcStatus.setup
          ? null
          : LocalDate(2026, 10, 1),
      startDate: LocalDate(2026, 10, 1),
      endDate: LocalDate(2026, 12, 31),
      status: status,
      createdAt: DateTime(2026, 10, 1),
    );
    final active = ArcResolution(
      current: arc(2, WinterArcStatus.active),
      latestCompleted: arc(1, WinterArcStatus.completed),
    );
    final completed = ArcResolution(
      latestCompleted: arc(1, WinterArcStatus.completed),
    );
    final setup = ArcResolution(current: arc(1, WinterArcStatus.setup));
    const empty = ArcResolution();

    final routes = {
      for (final payload in [
        'today',
        'journal',
        'hydration',
        focusGuardTapPayload,
        null,
        'unknown',
      ])
        payload: [
          for (final state in [active, completed, setup, empty])
            AppRoutes.forReminder(payload, state),
        ],
    };
    // With an active Arc: Journal for the reflection, Today for the rest.
    expect(
      [for (final r in routes.values) r[0]],
      [
        AppRoutes.today,
        AppRoutes.journal,
        AppRoutes.today,
        AppRoutes.today,
        AppRoutes.today,
        AppRoutes.today,
      ],
    );
    // A stale notification, after the Arc ended or before one started,
    // always falls back to the lifecycle home: never a writable screen.
    for (final (i, state) in [completed, setup, empty].indexed) {
      for (final r in routes.values) {
        expect(r[i + 1], AppRoutes.home(state));
      }
    }
    expect(AppRoutes.home(completed), AppRoutes.arc(1));
  });
}
