import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../progress/arc_history.dart';
import '../progress/progress_repository.dart';
import '../reflection/reflection_repository.dart';
import '../winter_arc/current_arc_service.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'achievement.dart';
import 'achievement_catalog.dart';
import 'achievement_repository.dart';
import 'achievement_rules.dart';

/// Achievement use cases.
///
/// Whether an achievement is earned is derived from stored history and
/// reflections; the unlock itself (what, when) is persisted. [reconcile]
/// brings the two in line. It is idempotent and self-healing: if a run fails
/// (for example after a habit action or reflection that did commit), the
/// next run (Today refresh, launch, Journey refresh) stores whatever is
/// still missing. Achievement work is secondary and never part of a habit
/// action's or reflection's transaction.
final class AchievementService {
  AchievementService({
    required WinterArcRepository sessions,
    required this._progress,
    required this._achievements,
    required this._reflections,
    required this._clock,
  }) : _arcs = CurrentArcService(sessions);

  final CurrentArcService _arcs;
  final ProgressRepository _progress;
  final AchievementRepository _achievements;
  final ReflectionRepository _reflections;
  final Clock _clock;
  final _queue = SerialQueue();

  /// Stores every achievement the home arc qualifies for that is not
  /// unlocked yet, and returns the newly stored unlocks in catalog order.
  ///
  /// The home arc is the active arc or, with nothing unfinished, the arc
  /// that just completed (so its Summit is stored). Returns nothing when no
  /// arc has started or a new one is still in setup.
  Future<List<AchievementUnlock>> reconcile() => _queue.run(() async {
    final session = (await _arcs.resolve()).home;
    if (session == null) return const [];
    return _achievements.unlockNew(
      session.id,
      AchievementRules.evaluate(await _contextOf(session)),
      at: _clock.now(),
    );
  });

  /// The catalog with the home arc's unlocks, or null when there is no home
  /// arc.
  Future<AchievementBoard?> board() async {
    final session = (await _arcs.resolve()).home;
    return session == null ? null : _boardOf(session);
  }

  /// The catalog with the unlocks of the started arc [sessionId]. Read-only.
  Future<AchievementBoard> boardFor(int sessionId) async =>
      _boardOf(await _arcs.requireStarted(sessionId));

  Future<AchievementContext> _contextOf(WinterArcSession session) async {
    final history = ArcHistory(
      session: session,
      records: await _progress.loadArc(session.id),
      today: _clock.today(),
    );
    final reflections = await _reflections.reflectionsFor(session.id);
    return AchievementContext(
      history: history,
      reflectionDates: [for (final r in reflections) r.date],
    );
  }

  Future<AchievementBoard> _boardOf(WinterArcSession session) async {
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
}
