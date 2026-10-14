import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/focus_guard/focus_guard_platform.dart';
import '../../domain/focus_guard/focus_guard_service.dart';

/// Bumped after every saved Focus Guard change, so the Today card re-reads.
final focusGuardChangedProvider = NotifierProvider<FocusGuardChanged, int>(
  FocusGuardChanged.new,
);

class FocusGuardChanged extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

/// What the Focus Guard settings show.
final class FocusGuardSettingsView {
  const FocusGuardSettingsView({required this.status, required this.labels});

  final FocusGuardStatus status;

  /// Launcher labels of the installed apps, by package, read live. A
  /// selected package missing here is no longer installed (or no longer
  /// has a launcher entry). Null if the app list couldn't be read.
  final Map<String, String>? labels;
}

final focusGuardSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      FocusGuardSettingsController,
      FocusGuardSettingsView
    >(FocusGuardSettingsController.new);

/// Focus Guard's settings. Every change is saved and the background check
/// reconciled straight away; the state is then re-read.
class FocusGuardSettingsController
    extends AsyncNotifier<FocusGuardSettingsView> {
  final _queue = SerialQueue();

  @override
  Future<FocusGuardSettingsView> build() async {
    final service = ref.watch(focusGuardServiceProvider);
    final status = await service.status();
    return FocusGuardSettingsView(
      status: status,
      labels: status.supported ? await _labels(service) : const {},
    );
  }

  /// A failing app list doesn't take the screen down: selected apps then
  /// show their package names.
  static Future<Map<String, String>?> _labels(FocusGuardService service) async {
    try {
      return {
        for (final app in await service.pickableApps())
          app.packageName: app.label,
      };
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'focus_guard',
      );
      return null;
    }
  }

  Future<ActionResult<FocusGuardToggle>> setEnabled(bool enabled) =>
      _run((service) => service.setEnabled(enabled));

  Future<ActionResult<void>> setDailyBudget(int minutes) =>
      _run((service) => service.setDailyBudget(minutes));

  Future<ActionResult<void>> setSelectedApps(List<String> packages) =>
      _run((service) => service.setSelectedApps(packages));

  /// Opens the system Usage Access page; the state is re-read on return.
  Future<void> openUsageAccessSettings() async {
    try {
      await ref.read(focusGuardServiceProvider).openUsageAccessSettings();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'focus_guard',
      );
    }
  }

  /// Re-reads, e.g. after returning from system settings.
  void refresh() => ref.invalidateSelf();

  Future<ActionResult<T>> _run<T>(
    Future<T> Function(FocusGuardService service) body,
  ) {
    final service = ref.read(focusGuardServiceProvider);
    final changed = ref.read(focusGuardChangedProvider.notifier);
    return _queue.run(() async {
      final result = await runAction('focus_guard', () => body(service));
      changed.changed();
      if (ref.mounted) ref.invalidateSelf();
      return result;
    });
  }
}

/// The app picker's list: launcher apps, read when the picker opens.
final focusGuardPickableAppsProvider =
    FutureProvider.autoDispose<List<LaunchableAppCandidate>>(
      (ref) => ref.watch(focusGuardServiceProvider).pickableApps(),
    );

final focusGuardTodayProvider =
    AsyncNotifierProvider.autoDispose<
      FocusGuardTodayController,
      FocusGuardToday
    >(FocusGuardTodayController.new);

/// The Today card. Re-read when the card appears, when Focus Guard's
/// settings change, at local midnight and on resume (the card asks); never
/// polled. Usage is measured afresh each time and never kept.
class FocusGuardTodayController extends AsyncNotifier<FocusGuardToday> {
  @override
  Future<FocusGuardToday> build() {
    ref.watch(focusGuardChangedProvider);
    ref.watch(dayChangedProvider);
    return ref.watch(focusGuardServiceProvider).today();
  }

  /// Re-reads without showing a loading state in between.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(
      () => ref.read(focusGuardServiceProvider).today(),
    );
    if (next case AsyncError(:final error, :final stackTrace)) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'focus_guard',
      );
    }
    if (ref.mounted) state = next;
  }
}
