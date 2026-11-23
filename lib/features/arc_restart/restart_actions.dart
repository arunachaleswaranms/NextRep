import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_restart.dart';
import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
import '../../domain/winter_arc/arc_restart.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../celebration/celebration_queue.dart';

/// Runs a Restart of arc [sessionId] as the screen showed it and, once it
/// is committed, brings the app in line with the new arc (spec § 6.2,
/// "afterwards, best effort and repeatable on the next launch"):
///
/// 1. queued celebrations are dropped (they belong to the old arc);
/// 2. reminders are re-planned for the new arc;
/// 3. every arc-dependent screen re-reads (refresh, arc lists, the arc
///    resolution that drives the router).
///
/// Nothing in 1–3 writes to either arc, and each is what a launch does
/// anyway, so a process death at any point after the commit is recovered
/// by the next launch. If re-reading the arcs fails, the app reloads from
/// storage as at launch (the `ArcRemoval._next` pattern). A refusal or a
/// storage failure is reported and returned; nothing else happens then,
/// because nothing was written.
///
/// Dependencies are read before the first await, so the follow-up completes
/// even if the screen that started it has closed.
Future<ActionResult<RestartOutcome>> runRestart(
  WidgetRef ref, {
  required int sessionId,
  required LocalDate shownOn,
  required LocalDate shownClosedOn,
}) async {
  final service = ref.read(arcRestartServiceProvider);
  final reminders = ref.read(reminderServiceProvider);
  final refresh = ref.read(arcRefreshProvider.notifier);
  final arcs = ref.read(arcsChangedProvider.notifier);
  final celebrations = ref.read(celebrationQueueProvider.notifier);
  final status = ref.read(arcResolutionProvider.notifier);
  final epoch = ref.read(appEpochProvider.notifier);
  final result = await runAction(
    'restart',
    () => service.restart(
      sessionId: sessionId,
      shownOn: shownOn,
      shownClosedOn: shownClosedOn,
    ),
  );
  if (result is! ActionSuccess<RestartOutcome>) return result;
  celebrations.clear();
  try {
    await reminders.reconcile();
  } catch (error, stackTrace) {
    // Best effort, as everywhere: the next launch, resume or change
    // re-plans them.
    ErrorReporter.report(toAppFailure(error, stackTrace), context: 'reminders');
  }
  refresh.changed();
  arcs.changed();
  try {
    await status.reconcile();
  } catch (error, stackTrace) {
    // The restart is committed; only re-reading failed. Reload the app
    // from storage, as at launch.
    ErrorReporter.report(toAppFailure(error, stackTrace), context: 'arcs');
    epoch.restart();
  }
  return result;
}

/// The arc a "Restart with this setup" entry would restart, or null when
/// Restart isn't offered today (spec § 9.9: the active arc only, running,
/// scheduled to pause or paused; never a completed or ended arc, nor one
/// that is over and about to complete). Re-read after every arc change and
/// at midnight. The clock guard is checked on the Restart screen, which
/// says why it refuses.
final restartEntryProvider = FutureProvider.autoDispose<WinterArcSession?>((
  ref,
) async {
  ref
    ..watch(arcRefreshProvider)
    ..watch(arcsChangedProvider)
    ..watch(dayChangedProvider);
  final session = await ref.watch(winterArcRepositoryProvider).currentSession();
  if (session == null) return null;
  final today = ref.watch(clockProvider).today();
  return ArcRestartRules.blockerOn(session, today) == null ? session : null;
});
