import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/reminder/reminder_preferences.dart';
import '../../domain/reminder/reminder_service.dart';

/// What the reminder settings show.
final class ReminderSettingsView {
  const ReminderSettingsView({
    required this.preferences,
    required this.permissionGranted,
    required this.arcActive,
  });

  final ReminderPreferences preferences;

  /// Whether the OS currently lets the app show notifications.
  final bool permissionGranted;

  /// Reminders only arrive while an arc is running.
  final bool arcActive;
}

final reminderSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      ReminderSettingsController,
      ReminderSettingsView
    >(ReminderSettingsController.new);

/// Reminder preferences. Every change is saved and the pending reminders
/// are reconciled straight away; the state is re-read afterwards.
class ReminderSettingsController extends AsyncNotifier<ReminderSettingsView> {
  final _queue = SerialQueue();

  @override
  Future<ReminderSettingsView> build() async {
    final service = ref.watch(reminderServiceProvider);
    final active = ref.watch(arcResolutionProvider)?.active != null;
    return ReminderSettingsView(
      preferences: await service.preferences(),
      permissionGranted: await _permissionGranted(service),
      arcActive: active,
    );
  }

  /// A failing permission check must not take the whole screen down (the
  /// user could then not turn reminders off): it reads as "not allowed",
  /// which only shows the system-settings notice.
  static Future<bool> _permissionGranted(ReminderService service) async {
    try {
      return await service.permissionGranted();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'reminders',
      );
      return false;
    }
  }

  /// Applies [change] to the stored preferences (not to what is on screen,
  /// which may be a save behind).
  Future<ActionResult<ReminderUpdate>> save(
    ReminderPreferences Function(ReminderPreferences current) change,
  ) {
    final service = ref.read(reminderServiceProvider);
    return _queue.run(() async {
      final result = await runAction('reminders', () => service.update(change));
      if (ref.mounted) ref.invalidateSelf();
      return result;
    });
  }

  /// Re-reads, e.g. after returning from system settings.
  void refresh() => ref.invalidateSelf();
}
