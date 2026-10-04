import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../progress/arc_history.dart';
import '../progress/progress_repository.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'achievement.dart';
import 'achievement_catalog.dart';
import 'achievement_repository.dart';
import 'achievement_rules.dart';

/// Achievement use cases.
///
/// Whether an achievement is earned is derived from stored history; the
/// unlock itself (what, when) is persisted. [reconcile] brings the two in
/// line. It is idempotent and self-healing: if a run fails (for example
/// after a habit action that did commit), the next run (Today refresh,
/// launch, Journey refresh) stores whatever is still missing. Achievement
/// work is secondary and never part of a habit action's transaction.
final class AchievementService {
  AchievementService({
    required this._sessions,
    required this._progress,
    required this._achievements,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final ProgressRepository _progress;
  final AchievementRepository _achievements;
  final Clock _clock;
  final _queue = SerialQueue();

  /// Stores every achievement the current history qualifies for that is not
  /// unlocked yet, and returns the newly stored unlocks in catalog order.
  /// Returns nothing when no arc has started.
  Future<List<AchievementUnlock>> reconcile() => _queue.run(() async {
    final session = await _startedSession();
    if (session == null) return const [];
    final history = ArcHistory(
      session: session,
      records: await _progress.loadArc(session.id),
      today: _clock.today(),
    );
    return _achievements.unlockNew(
      session.id,
      AchievementRules.evaluate(history),
      at: _clock.now(),
    );
  });

  /// The catalog with this arc's unlocks, or null when no arc has started.
  Future<AchievementBoard?> board() async {
    final session = await _startedSession();
    if (session == null) return null;
    final unlocks = {
      for (final u in await _achievements.unlocks(session.id)) u.key: u,
    };
    return AchievementBoard(
      startDate: session.startDate,
      entries: [
        for (final definition in AchievementCatalog.all)
          AchievementStatus(
            definition: definition,
            unlock: unlocks[definition.key],
          ),
      ],
    );
  }

  Future<WinterArcSession?> _startedSession() async {
    final session = await _sessions.latestSession();
    if (session == null || session.status == WinterArcStatus.setup) {
      return null;
    }
    return session;
  }
}
