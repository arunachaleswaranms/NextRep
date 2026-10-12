import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_restart.dart';
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
    .family<AchievementBoard, int>((ref, sessionId) {
      // A catalog backfill can store unlocks for any arc.
      ref.watch(achievementsChangedProvider);
      return ref.watch(achievementServiceProvider).boardFor(sessionId);
    });

/// Rebuilt after a restore, so a restored arc's history is backfilled too.
final achievementSyncProvider = Provider<AchievementSync>((ref) {
  ref.watch(appEpochProvider);
  return AchievementSync(ref);
});

/// Runs achievement reconciliation for the UI: stores newly earned unlocks,
/// removes today's unlocks that are no longer earned, queues a celebration
/// for the new ones only, and refreshes the board.
///
/// An unlock removed by an earlier run and earned again for the same date
/// (undo, then redo) is stored again but not celebrated a second time.
///
/// The first successful run of an app session (and after a restore) is a
/// catalog backfill over every started arc: achievements a newer catalog
/// added are derived from history already lived. Only the home arc's new
/// unlocks are celebrated, together in one card; a completed arc's are
/// stored silently. Later runs reconcile the home arc only. Skipping the
/// backfill would only delay it: it is idempotent, and [run] heals the home
/// arc every time anyway.
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

  var _backfilled = false;

  Future<List<AchievementUnlock>> run() => _queue.run(() async {
    try {
      final service = _ref.read(achievementServiceProvider);
      final UnlockChanges changes;
      var stored = false;
      if (_backfilled) {
        changes = await service.sync();
      } else {
        final backfill = await service.backfillCatalog();
        _backfilled = true;
        changes = backfill.home;
        stored = backfill.historical.isNotEmpty;
      }
      if (!changes.isEmpty || stored) {
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
