import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/error_reporter.dart';
import '../../core/time/local_date.dart';
import '../../core/utils/serial_queue.dart';
import '../../domain/achievement/achievement.dart';
import '../celebration/celebration_queue.dart';

/// Bumped when unlocks are stored or removed, so the board re-reads.
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
/// removes today's unlocks that are no longer earned, queues a celebration
/// for the new ones only, and refreshes the board.
///
/// An unlock removed by an earlier run and earned again for the same date
/// (undo, then redo) is stored again but not celebrated a second time.
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

  /// Unlocks removed by this app session's runs, by key and date.
  final _revoked = <(AchievementKey, LocalDate)>{};

  Future<List<AchievementUnlock>> run() => _queue.run(() async {
    try {
      final changes = await _ref.read(achievementServiceProvider).sync();
      if (!changes.isEmpty) {
        _ref.read(achievementsChangedProvider.notifier).bump();
      }
      _revoked.addAll([for (final u in changes.revoked) (u.key, u.unlockedOn)]);
      final celebrate = [
        for (final u in changes.unlocked)
          if (!_revoked.remove((u.key, u.unlockedOn))) u,
      ];
      if (celebrate.isNotEmpty) {
        _ref
            .read(celebrationQueueProvider.notifier)
            .add(AchievementCelebration(celebrate));
      }
      return changes.unlocked;
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'achievements',
      );
      return const <AchievementUnlock>[];
    }
  });
}
