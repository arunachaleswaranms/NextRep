import '../../core/errors/app_failure.dart';

/// User-facing copy for a failure. Developer detail stays in the logs.
String userMessageFor(AppFailure failure) => switch (failure) {
  PersistenceFailure() =>
    "Couldn't save or load your progress. Please try again.",
  UnexpectedFailure() => 'Something went wrong. Please try again.',
  BackupFailure(:final problem) => switch (problem) {
    BackupProblem.tooLarge =>
      "That file is too large to be a NextRep backup. Nothing was changed.",
    BackupProblem.unreadable || BackupProblem.notNextRep =>
      "That file isn't a NextRep backup. Nothing was changed.",
    BackupProblem.unsupportedVersion =>
      'That backup was made by a newer version of NextRep. Update the app '
          'to restore it. Nothing was changed.',
    BackupProblem.checksumMismatch =>
      'That backup is damaged or was changed after it was exported, so it '
          "can't be restored safely. Nothing was changed.",
    BackupProblem.invalidData =>
      "That backup contains data NextRep can't restore safely. Nothing was "
          'changed.',
  },
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
    DomainRule.arcInProgress =>
      'You already have a Winter Arc in progress. Finish it first.',
    DomainRule.noCompletedArc => 'There is no finished Winter Arc to reuse.',
    DomainRule.reflectionEmpty =>
      'Pick a mood or write a few words before saving.',
    DomainRule.reflectionTooLong => 'Keep each answer to 240 characters.',
    DomainRule.reflectionReadOnly =>
      'Past reflections are kept as they were. Only today can be edited.',
    DomainRule.reflectionNotAvailable => 'Reflections open on the day itself.',
    DomainRule.arcNotDeletable => 'Only a completed Winter Arc can be deleted.',
    DomainRule.seasonNotOpen =>
      'The Seasonal Winter Arc opens for setup on September 1.',
    DomainRule.seasonNotStarted =>
      'The season starts October 1. Your setup is saved until then.',
    DomainRule.seasonEnded =>
      'This season has ended. Cancel this setup to choose a new Arc.',
    DomainRule.habitLimitReached =>
      'An Arc can have up to 12 habits. Remove one to add another.',
    DomainRule.duplicateHabit =>
      'That habit, or one with the same name, is already in your Arc.',
    DomainRule.sessionNotFound ||
    DomainRule.noSession ||
    DomainRule.sessionNotInSetup ||
    DomainRule.noActiveSession ||
    DomainRule.habitNotFound ||
    DomainRule.invalidArc ||
    DomainRule.actionNotSupportedForHabitType =>
      "That action isn't available right now.",
  },
};
