import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/achievement/achievement.dart';

/// Something worth celebrating, built only from a persisted result (a
/// commit's ledger change, XP before / after, newly stored unlocks), never
/// from UI timing.
sealed class CelebrationEvent {
  const CelebrationEvent();

  /// Lower shows first among events waiting to be shown.
  int get priority;
}

/// Today became a Perfect Day and / or a level was reached.
final class DayCelebration extends CelebrationEvent {
  const DayCelebration({this.perfectStreak, this.level, this.levelXp});

  /// Set when the commit granted today's Perfect Day bonus.
  final int? perfectStreak;

  /// Set when the commit crossed a level boundary.
  final int? level;

  /// Total XP at [level].
  final int? levelXp;

  bool get isEmpty => perfectStreak == null && level == null;

  @override
  int get priority => 0;
}

/// Achievements newly persisted by one reconciliation, shown together as
/// one card so several unlocks never stack overlays.
final class AchievementCelebration extends CelebrationEvent {
  const AchievementCelebration(this.unlocks);

  final List<AchievementUnlock> unlocks;

  @override
  int get priority => 1;
}

final celebrationQueueProvider =
    NotifierProvider<CelebrationQueue, List<CelebrationEvent>>(
      CelebrationQueue.new,
    );

/// Celebrations waiting to be shown, one at a time, head first.
class CelebrationQueue extends Notifier<List<CelebrationEvent>> {
  @override
  List<CelebrationEvent> build() => const [];

  /// Queues [event]. Waiting events are ordered by priority, then arrival;
  /// the one already on screen (the head) is never displaced.
  void add(CelebrationEvent event) {
    if (event is DayCelebration && event.isEmpty) return;
    if (event is AchievementCelebration && event.unlocks.isEmpty) return;
    final current = state;
    if (current.isEmpty) {
      state = [event];
      return;
    }
    final waiting = [...current.skip(1), event];
    // List.sort is not stable; insertion order breaks ties explicitly.
    final indexed = waiting.indexed.toList()
      ..sort((a, b) {
        final byPriority = a.$2.priority.compareTo(b.$2.priority);
        return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
      });
    state = [current.first, for (final (_, e) in indexed) e];
  }

  /// Drops every waiting celebration, e.g. when all data was replaced.
  void clear() => state = const [];

  /// Removes [event] (normally the head) once dismissed.
  void dismiss(CelebrationEvent event) {
    state = [
      for (final e in state)
        if (!identical(e, event)) e,
    ];
  }
}
