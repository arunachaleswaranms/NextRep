import '../../core/time/clock.dart';
import '../../core/time/local_date.dart';
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
/// reflections; the unlock itself (what, when) is persisted. [sync] brings
/// the two in line. It is idempotent and self-healing: if a run fails (for
/// example after a habit action or reflection that did commit), the next
/// run (Today refresh, launch, Journey refresh) catches up. Achievement
/// work is secondary and never part of a habit action's or reflection's
/// transaction.
///
/// Past unlocks are permanent. Today's are provisional: today can still
/// change (an undone completion, a Minimum Day returned to full targets),
/// so an unlock dated today that the history no longer earns is removed,
/// and stored again if it is earned again later that day.
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

  /// Reconciles the home arc's unlocks (see [sync]) and returns the newly
  /// stored ones in catalog order, the ones to celebrate.
  Future<List<AchievementUnlock>> reconcile() async => (await sync()).unlocked;

  /// Stores every achievement the home arc qualifies for that is not
  /// unlocked yet, and removes today's unlocks it no longer qualifies for.
  /// Unlocks dated before today are never removed.
  ///
  /// The home arc is the active arc or, with nothing unfinished, the arc
  /// that just completed (so its Summit is stored). Changes nothing when no
  /// arc has started or a new one is still in setup.
  Future<UnlockChanges> sync() => _queue.run(() async {
    final session = (await _arcs.resolve()).home;
    if (session == null) return const UnlockChanges();
    final today = _clock.today();
    return _achievements.reconcileUnlocks(
      session.id,
      AchievementRules.evaluate(await _contextOf(session, today)),
      today: today,
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

  Future<AchievementContext> _contextOf(
    WinterArcSession session,
    LocalDate today,
  ) async {
    final history = ArcHistory(
      session: session,
      records: await _progress.loadArc(session.id),
      today: today,
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
