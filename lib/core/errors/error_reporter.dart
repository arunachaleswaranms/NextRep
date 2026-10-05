import 'dart:developer' as developer;

import 'app_failure.dart';

/// Single place where failures are recorded.
///
/// Local only, by design: there is no crash or telemetry service. Reports go
/// to `dart:developer`'s log, which is visible in debug and profile builds
/// (DevTools, `flutter logs`) and is a no-op in release builds, so a
/// release build writes nothing about failures anywhere. Messages carry
/// operation names and ids only, never reflection text or backup contents
/// (see `guardPrivatePersistence`).
abstract final class ErrorReporter {
  static void report(AppFailure failure, {String context = 'app'}) {
    developer.log(
      failure.message,
      name: 'nextrep.$context',
      error: failure.cause ?? failure,
      stackTrace: failure.stackTrace,
      level: failure is DomainFailure ? 800 : 1000,
    );
  }
}
