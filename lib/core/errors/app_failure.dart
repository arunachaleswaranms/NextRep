/// Base type for every failure the app expects and knows how to present.
///
/// Repositories convert low-level exceptions into [PersistenceFailure];
/// domain services raise [DomainFailure] when a rule rejects an action.
/// Anything else escaping to the UI layer is wrapped as [UnexpectedFailure].
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause, this.stackTrace});

  /// Developer-facing description of what failed.
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Reading or writing local storage failed.
final class PersistenceFailure extends AppFailure {
  const PersistenceFailure(super.message, {super.cause, super.stackTrace});
}

/// Rules the domain enforces. Each maps to a distinct user-facing message.
enum DomainRule {
  noSession,
  sessionNotInSetup,
  noActiveSession,
  arcNotRunningToday,
  noHabitsSelected,
  habitNotFound,
  habitDisabled,
  actionNotSupportedForHabitType,
  staleDay,
}

/// A domain rule rejected the requested action. Nothing was persisted.
final class DomainFailure extends AppFailure {
  const DomainFailure(this.rule, String message) : super(message);

  final DomainRule rule;
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.cause, super.stackTrace});
}

/// Normalises any thrown object into an [AppFailure].
AppFailure toAppFailure(Object error, StackTrace stackTrace) => switch (error) {
  AppFailure() => error,
  _ => UnexpectedFailure(
    'Unexpected error',
    cause: error,
    stackTrace: stackTrace,
  ),
};
