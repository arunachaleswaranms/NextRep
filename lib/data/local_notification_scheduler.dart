import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder/reminder_plan.dart';
import '../domain/reminder/reminder_scheduler.dart';

/// [ReminderScheduler] backed by `flutter_local_notifications`: local,
/// on-device notifications only, with no server or push service.
///
/// Reminders are scheduled with Android's inexact "allow while idle" mode,
/// so no exact-alarm permission is needed; the OS may deliver a reminder a
/// few minutes late to save battery, which is fine for a habit nudge.
final class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// What this process last scheduled, by id. Null until the first
  /// complete replacement, and after any failure, so the next [schedule]
  /// starts from a clean slate. Only kept in memory.
  Map<int, PlannedReminder>? _scheduled;

  /// Sets up the plugin and returns the payload of the notification that
  /// launched the app, if the app was cold-started from one. [onTap]
  /// receives the payload of a notification tapped while the app is
  /// running (in the foreground or background).
  Future<String?> initialize({
    required void Function(String? payload) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
        // Permission is asked for when the user turns a reminder on, never
        // at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch == null || !launch.didNotificationLaunchApp) return null;
    return launch.notificationResponse?.payload;
  }

  @override
  Future<bool> permissionGranted() async {
    if (_android case final android?) {
      return await android.areNotificationsEnabled() ?? false;
    }
    if (_ios case final ios?) {
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (_android case final android?) {
      // Android 13+ shows the runtime prompt (the OS stops showing it after
      // repeated denials); older versions grant at install and return true.
      return await android.requestNotificationsPermission() ?? false;
    }
    if (_ios case final ios?) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  /// Makes the pending notifications exactly [reminders].
  ///
  /// The first call in a process replaces everything pending. Later calls
  /// cancel only pending ids that left the plan and (re)schedule only
  /// reminders that are new or changed, so logging Water doesn't reschedule
  /// every daily and reflection reminder. Notifications already shown are
  /// never removed.
  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    final known = _scheduled;
    _scheduled = null;
    if (known == null) {
      await _plugin.cancelAllPendingNotifications();
      for (final reminder in reminders) {
        await _zonedSchedule(reminder);
      }
    } else {
      final changes = ReminderChanges.between(
        pending: {
          for (final request in await _plugin.pendingNotificationRequests())
            request.id,
        },
        known: known,
        next: reminders,
      );
      for (final id in changes.cancel) {
        await _plugin.cancel(id: id);
      }
      for (final reminder in changes.schedule) {
        await _zonedSchedule(reminder);
      }
    }
    _scheduled = {for (final reminder in reminders) reminder.id: reminder};
  }

  Future<void> _zonedSchedule(PlannedReminder reminder) =>
      _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        // The instant was computed from the local wall clock; UTC carries
        // it exactly without needing the device's time-zone name.
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
        notificationDetails: _details(reminder.kind),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.payload,
      );

  @override
  Future<void> cancelAll() async {
    _scheduled = null;
    await _plugin.cancelAllPendingNotifications();
    _scheduled = const {};
  }

  static NotificationDetails _details(ReminderKind kind) => NotificationDetails(
    // One channel per kind, so either can be silenced in system settings.
    android: switch (kind) {
      ReminderKind.daily => const AndroidNotificationDetails(
        'daily_reminder',
        'Daily reminder',
        channelDescription: 'A daily nudge while a Winter Arc is running.',
        category: AndroidNotificationCategory.reminder,
      ),
      ReminderKind.reflection => const AndroidNotificationDetails(
        'reflection_reminder',
        'Evening reflection',
        channelDescription: 'An evening prompt to reflect on the day.',
        category: AndroidNotificationCategory.reminder,
      ),
      ReminderKind.hydration => const AndroidNotificationDetails(
        'hydration_coach',
        'Hydration Coach',
        channelDescription:
            "A nudge when today's Water is behind pace, during your active "
            'hours.',
        category: AndroidNotificationCategory.reminder,
      ),
    },
    iOS: const DarwinNotificationDetails(),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      defaultTargetPlatform == TargetPlatform.android
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
      : null;
}
