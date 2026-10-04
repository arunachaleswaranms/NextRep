import 'reminder_plan.dart';

/// The operating system's local notifications, seen from the domain.
///
/// The app ships a plugin-backed implementation; tests use a fake. Nothing
/// here talks to a server: notifications are scheduled and shown on the
/// device only.
abstract interface class ReminderScheduler {
  /// Whether the app may currently show notifications. Never prompts.
  Future<bool> permissionGranted();

  /// Asks for permission to show notifications where the OS still allows
  /// asking, and returns whether it is granted. Called only when the user
  /// turns a reminder on.
  Future<bool> requestPermission();

  /// Replaces every pending reminder with [reminders].
  Future<void> schedule(List<PlannedReminder> reminders);

  /// Cancels every pending reminder.
  Future<void> cancelAll();
}

/// Never schedules anything and reports no permission. The default where
/// no platform implementation is wired in (widget and integration tests).
final class DisabledReminderScheduler implements ReminderScheduler {
  const DisabledReminderScheduler();

  @override
  Future<bool> permissionGranted() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}
