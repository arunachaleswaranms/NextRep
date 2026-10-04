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
  invalidHabitEdit,
  lastEnabledHabit,
  dayAlreadyPerfect,

  /// The arc is over and read-only.
  arcCompleted,

  /// A configuration change would only apply after the arc's last day.
  noNextChallengeDay,

  /// A new arc can't start while another one is in setup or running.
  arcInProgress,

  /// "Reuse last setup" needs a completed arc to copy from.
  noCompletedArc,

  /// No session has the requested id.
  sessionNotFound,

  /// A reflection needs a mood or some text.
  reflectionEmpty,

  /// A reflection field is longer than its limit.
  reflectionTooLong,

  /// Only today's reflection can be written; earlier ones are read-only.
  reflectionReadOnly,

  /// The date has no reflection yet to write: it's in the future or
  /// outside the arc.
  reflectionNotAvailable,
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
