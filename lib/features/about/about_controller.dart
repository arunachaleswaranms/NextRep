import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../domain/update/installed_app.dart';
import '../../domain/update/update_checker.dart';

/// The installed version and build, read once from the platform.
final installedAppProvider = FutureProvider<InstalledApp>(
  (ref) => ref.watch(installedAppSourceProvider).read(),
);

/// Where the manual update check stands. Kept in memory only, and only
/// while About is open: leaving it forgets the result, and opening it
/// again never checks by itself.
sealed class UpdateCheckState {
  const UpdateCheckState();
}

/// Nothing checked since About opened.
final class UpdateCheckIdle extends UpdateCheckState {
  const UpdateCheckIdle();
}

/// The one request is in flight.
final class UpdateCheckRunning extends UpdateCheckState {
  const UpdateCheckRunning();
}

final class UpdateCheckFinished extends UpdateCheckState {
  const UpdateCheckFinished(this.result);

  final UpdateCheckResult result;
}

final updateCheckControllerProvider =
    NotifierProvider.autoDispose<UpdateCheckController, UpdateCheckState>(
      UpdateCheckController.new,
    );

/// The manual update check: [check] is the only code path that contacts
/// GitHub, and only the "Check for updates" button calls it. Building this
/// controller, or the screen, sends nothing.
class UpdateCheckController extends Notifier<UpdateCheckState> {
  @override
  UpdateCheckState build() => const UpdateCheckIdle();

  /// One request to GitHub, unless one is already running (a second tap
  /// does nothing) or update checks aren't offered here. Never retries.
  Future<void> check() async {
    if (state is UpdateCheckRunning) return;
    final feed = ref.read(releaseFeedProvider);
    if (feed == null) return;
    state = const UpdateCheckRunning();
    UpdateCheckResult? result;
    try {
      final installed = await ref.read(installedAppProvider.future);
      final version = installed.releaseVersion;
      if (version != null) result = await UpdateChecker(feed).check(version);
    } catch (error, stackTrace) {
      // A defect, not GitHub's answer (the checker maps those).
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'updates');
      result = const CheckInvalidRelease();
    }
    if (!ref.mounted) return; // About was closed meanwhile
    state = result == null
        ? const UpdateCheckIdle()
        : UpdateCheckFinished(result);
  }
}
