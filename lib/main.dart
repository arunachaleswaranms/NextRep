import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/database/app_database.dart';
import 'core/errors/app_failure.dart';
import 'core/errors/error_reporter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReporter.report(
      UnexpectedFailure(
        'Flutter framework error',
        cause: details.exception,
        stackTrace: details.stack,
      ),
      context: 'flutter',
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorReporter.report(toAppFailure(error, stackTrace), context: 'platform');
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(AppDatabase.open())],
      // Failures are surfaced to the user with an explicit retry instead of
      // being retried silently in the background.
      retry: (retryCount, error) => null,
      child: const NextRepApp(),
    ),
  );
}
