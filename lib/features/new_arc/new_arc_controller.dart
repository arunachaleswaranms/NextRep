import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';

/// The habits "Reuse last setup" would start with (the last completed
/// arc's final configuration), or null without a completed arc.
final reusableHabitsProvider = FutureProvider.autoDispose<List<Habit>?>(
  (ref) => ref.watch(winterArcServiceProvider).reusableHabits(),
);

final newArcControllerProvider =
    NotifierProvider.autoDispose<NewArcController, NewArcBaseline?>(
      NewArcController.new,
    );

/// Creates the next arc's setup session. State is the choice in flight, so
/// a second tap can't create a second arc while the first is saving (the
/// domain rejects it anyway).
class NewArcController extends Notifier<NewArcBaseline?> {
  @override
  NewArcBaseline? build() => null;

  Future<ActionResult<WinterArcSession>> start(NewArcBaseline baseline) async {
    if (state != null) {
      return const ActionFailure(
        DomainFailure(DomainRule.arcInProgress, 'A new arc is being created'),
      );
    }
    state = baseline;
    final status = ref.read(arcResolutionProvider.notifier);
    final result = await runAction('new_arc', () async {
      final session = await ref
          .read(winterArcServiceProvider)
          .startNewArc(baseline);
      // Publish the new setup arc so the router moves on to Habit Setup.
      await status.reconcile();
      return session;
    });
    if (ref.mounted) state = null;
    return result;
  }
}
