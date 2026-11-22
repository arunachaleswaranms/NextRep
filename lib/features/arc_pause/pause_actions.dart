import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/clock.dart';
import '../../domain/winter_arc/arc_pause.dart';
import '../../domain/winter_arc/arc_pause_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

/// Runs a Freeze, Cancel pause or Resume [body] and, once it is stored,
/// re-plans the reminders straight away (spec § 5.2 F9: nothing pending
/// for a paused date, re-planned after resume) and has every screen re-read
/// the arc. A failure is reported and returned; nothing else happens then,
/// because nothing was written.
///
/// Dependencies are read before the first await, so the action completes
/// even if the sheet or screen that started it has closed.
Future<ActionResult<WinterArcSession>> runPauseAction(
  WidgetRef ref,
  String context,
  Future<WinterArcSession> Function(ArcPauseService service) body,
) async {
  final service = ref.read(arcPauseServiceProvider);
  final reminders = ref.read(reminderServiceProvider);
  final refresh = ref.read(arcRefreshProvider.notifier);
  final result = await runAction(context, () => body(service));
  if (result is ActionSuccess<WinterArcSession>) {
    try {
      await reminders.reconcile();
    } catch (error, stackTrace) {
      // Best effort, as everywhere: the next launch, resume or change
      // re-plans them.
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'reminders',
      );
    }
    refresh.changed();
  }
  return result;
}

/// The arc a "Pause Arc" entry outside Today (the Habits screen) would
/// pause, or null when Freeze isn't offered today (spec § 9.6: active
/// Rolling Arcs only; hidden on Day 92, while a pause is scheduled and
/// while paused). Re-read after every arc change and at midnight.
final pauseEntryProvider = FutureProvider.autoDispose<int?>((ref) async {
  ref
    ..watch(arcRefreshProvider)
    ..watch(dayChangedProvider);
  final session = await ref.watch(winterArcRepositoryProvider).currentSession();
  if (session == null) return null;
  final today = ref.watch(clockProvider).today();
  return ArcPauseRules.blockerOn(session, today) == null ? session.id : null;
});
