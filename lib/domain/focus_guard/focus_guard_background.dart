import 'focus_guard_platform.dart';

/// The operating system's deferrable background work, seen from the domain.
///
/// On Android this is a periodic WorkManager job, about every 15 minutes at
/// best: the OS may run it later to save battery, and doesn't run it at all
/// after the user force-stops the app until the app is opened again.
abstract interface class FocusGuardBackgroundScheduler {
  /// Makes sure the periodic check exists. Idempotent: an existing check
  /// keeps its timing.
  Future<void> ensureScheduled();

  /// Removes the periodic check, if any.
  Future<void> cancel();
}

/// Never schedules anything: the default where no platform implementation
/// is wired in (iOS, widget and integration tests).
final class DisabledFocusGuardBackgroundScheduler
    implements FocusGuardBackgroundScheduler {
  const DisabledFocusGuardBackgroundScheduler();

  @override
  Future<void> ensureScheduled() async {}

  @override
  Future<void> cancel() async {}
}

/// When the periodic check should exist at all.
abstract final class FocusGuardBackground {
  /// Only while the user has turned Focus Guard on, chosen at least one app
  /// and set a budget, and Usage Access is granted. Anything else, including
  /// the state right after a restore, means no background work.
  static bool shouldRun({
    required bool enabled,
    required UsageAccess access,
    required int selectedApps,
    required int dailyBudgetMinutes,
  }) =>
      enabled &&
      access == UsageAccess.granted &&
      selectedApps > 0 &&
      dailyBudgetMinutes > 0;

  /// Schedules or cancels the periodic check to match [shouldRun], and
  /// returns whether it is now scheduled. Safe to call at launch, on resume
  /// and after any change.
  static Future<bool> reconcile(
    FocusGuardBackgroundScheduler scheduler, {
    required bool enabled,
    required UsageAccess access,
    required int selectedApps,
    required int dailyBudgetMinutes,
  }) async {
    final run = shouldRun(
      enabled: enabled,
      access: access,
      selectedApps: selectedApps,
      dailyBudgetMinutes: dailyBudgetMinutes,
    );
    if (run) {
      await scheduler.ensureScheduled();
    } else {
      await scheduler.cancel();
    }
    return run;
  }
}
