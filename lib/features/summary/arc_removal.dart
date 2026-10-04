import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_restart.dart';
import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../celebration/celebration_queue.dart';

final arcRemovalProvider = Provider<ArcRemoval>(ArcRemoval.new);

/// Deleting a completed arc and cancelling a setup, for the UI. Each
/// returns where the app should go next, resolved from storage after the
/// deletion, so the router never keeps pointing at a deleted arc.
final class ArcRemoval {
  ArcRemoval(this._ref);

  final Ref _ref;

  /// Deletes the completed arc [sessionId]. The value is the location to
  /// go to: Arc History while an arc runs, otherwise the app's home (the
  /// latest remaining completed arc, or onboarding when none is left).
  Future<ActionResult<String>> deleteCompletedArc(int sessionId) async {
    final service = _ref.read(winterArcServiceProvider);
    final deleted = await runAction(
      'delete_arc',
      () => service.deleteCompletedArc(sessionId),
    );
    return switch (deleted) {
      ActionFailure(:final failure) => ActionFailure(failure),
      ActionSuccess() => ActionSuccess(await _next(toHistory: true)),
    };
  }

  /// Cancels the arc in setup. The value is the location to go to: the
  /// latest completed arc's summary, or onboarding on a first install.
  Future<ActionResult<String>> cancelSetup() async {
    final service = _ref.read(winterArcServiceProvider);
    final cancelled = await runAction('cancel_setup', service.cancelSetup);
    return switch (cancelled) {
      ActionFailure(:final failure) => ActionFailure(failure),
      ActionSuccess() => ActionSuccess(await _next(toHistory: false)),
    };
  }

  Future<String> _next({required bool toHistory}) async {
    _ref.read(arcsChangedProvider.notifier).changed();
    // Anything still queued may celebrate the arc that is gone.
    _ref.read(celebrationQueueProvider.notifier).clear();
    try {
      final resolution = await _ref
          .read(arcResolutionProvider.notifier)
          .reconcile();
      if (toHistory && resolution.active != null) return AppRoutes.history;
      return AppRoutes.home(resolution);
    } catch (error, stackTrace) {
      // The deletion is committed; only re-reading failed. Reload the app
      // from storage, as at launch (with a retry if that fails too).
      ErrorReporter.report(toAppFailure(error, stackTrace), context: 'arcs');
      _ref.read(appEpochProvider.notifier).restart();
      return AppRoutes.onboarding;
    }
  }
}
