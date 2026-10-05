import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/database/app_database.dart';
import 'core/errors/app_failure.dart';
import 'core/errors/error_reporter.dart';
import 'data/local_notification_scheduler.dart';
import 'domain/reminder/reminder_scheduler.dart';
import 'shared/widgets/release_error_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    // In release, presentError would print the exception text to the
    // system log; the report below is enough.
    if (!kReleaseMode) FlutterError.presentError(details);
    ErrorReporter.report(
      UnexpectedFailure(
        'Flutter framework error',
        cause: details.exception,
        stackTrace: details.stack,
      ),
      context: 'flutter',
    );
  };
  // A widget that fails to build shows a calm, empty panel in release (not
  // Flutter's grey error box with exception text); the screen around it
  // keeps working.
  if (kReleaseMode) ErrorWidget.builder = (_) => const ReleaseErrorPanel();
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorReporter.report(toAppFailure(error, stackTrace), context: 'platform');
    return true;
  };

  // Local reminders. If the notification plugin can't start, the app runs
  // without reminders rather than not at all.
  final taps = StreamController<String?>.broadcast();
  ReminderScheduler scheduler = const DisabledReminderScheduler();
  String? launchPayload;
  try {
    final local = LocalNotificationScheduler();
    launchPayload = await local.initialize(onTap: taps.add);
    scheduler = local;
  } catch (error, stackTrace) {
    ErrorReporter.report(toAppFailure(error, stackTrace), context: 'reminders');
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(AppDatabase.open()),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderLaunchPayloadProvider.overrideWithValue(launchPayload),
        reminderTapsProvider.overrideWithValue(taps.stream),
      ],
      // Failures are surfaced to the user with an explicit retry instead of
      // being retried silently in the background.
      retry: (retryCount, error) => null,
      child: const NextRepApp(),
    ),
  );
}
