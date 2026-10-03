import 'dart:developer' as developer;

import 'app_failure.dart';

/// Single place where failures are recorded so none are silently dropped.
///
/// Phase 1 logs locally only (no telemetry). A crash/diagnostics sink can be
/// added here later without touching call sites.
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
