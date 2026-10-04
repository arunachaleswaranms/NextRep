import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/achievement/achievement.dart';
import '../celebration/celebration_queue.dart';

/// Bumped when new unlocks are stored, so the board re-reads.
final achievementsChangedProvider = NotifierProvider<_Counter, int>(
  _Counter.new,
);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// The catalog with the home arc's unlocks. Null before an arc has started
/// or while a new one is in setup.
final achievementBoardProvider = FutureProvider.autoDispose<AchievementBoard?>((
  ref,
) {
  ref.watch(achievementsChangedProvider);
  return ref.watch(achievementServiceProvider).board();
});

/// The catalog with the unlocks of the started arc [sessionId], for Arc
/// History. Read-only: nothing is reconciled or celebrated.
final arcAchievementBoardProvider = FutureProvider.autoDispose
    .family<AchievementBoard, int>(
      (ref, sessionId) =>
          ref.watch(achievementServiceProvider).boardFor(sessionId),
    );

final achievementSyncProvider = Provider<AchievementSync>(AchievementSync.new);

/// Runs achievement reconciliation for the UI: stores newly earned unlocks,
/// queues their celebration, and refreshes the board.
///
/// Best effort by design. Achievements are secondary, derived state: a
/// failure is reported and swallowed, never surfaced as a failed habit
/// action, and the next run (Today refresh, launch, Journey refresh) heals
/// it. Runs are serialised; an unlock is celebrated only by the run that
/// stored it.
final class AchievementSync {
  AchievementSync(this._ref);

  final Ref _ref;
  final _queue = SerialQueue();

  Future<List<AchievementUnlock>> run() => _queue.run(() async {
    try {
      final unlocked = await _ref.read(achievementServiceProvider).reconcile();
      if (unlocked.isNotEmpty) {
        _ref.read(achievementsChangedProvider.notifier).bump();
        _ref
            .read(celebrationQueueProvider.notifier)
            .add(AchievementCelebration(unlocked));
      }
      return unlocked;
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'achievements',
      );
      return const <AchievementUnlock>[];
    }
  });
}
