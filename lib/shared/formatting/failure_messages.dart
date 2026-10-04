import '../../core/errors/app_failure.dart';

/// User-facing copy for a failure. Developer detail stays in the logs.
String userMessageFor(AppFailure failure) => switch (failure) {
  PersistenceFailure() =>
    "Couldn't save or load your progress. Please try again.",
  UnexpectedFailure() => 'Something went wrong. Please try again.',
  DomainFailure(:final rule) => switch (rule) {
    DomainRule.noHabitsSelected => 'Pick at least one habit to begin.',
    DomainRule.staleDay => "It's a new day — Today has been refreshed.",
    DomainRule.arcNotRunningToday => 'Your Winter Arc is not running today.',
    DomainRule.habitDisabled => 'That habit is turned off.',
    DomainRule.invalidHabitEdit => 'Check the habit name and goals.',
    DomainRule.lastEnabledHabit => 'Keep at least one habit turned on.',
    DomainRule.dayAlreadyPerfect =>
      'Today is already a Perfect Day — no need to scale it down.',
    DomainRule.arcCompleted =>
      'Your Winter Arc is complete. Its history is read-only.',
    DomainRule.noNextChallengeDay =>
      'Today is the last day, so goal changes would never apply. '
          'You can still rename habits.',
    DomainRule.noSession ||
    DomainRule.sessionNotInSetup ||
    DomainRule.noActiveSession ||
    DomainRule.habitNotFound ||
    DomainRule.actionNotSupportedForHabitType =>
      "That action isn't available right now.",
  },
};
