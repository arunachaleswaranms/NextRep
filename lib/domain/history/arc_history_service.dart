import '../../core/time/clock.dart';
import '../achievement/achievement_catalog.dart';
import '../achievement/achievement_repository.dart';
import '../progress/arc_history.dart';
import '../progress/arc_summary.dart';
import '../progress/progress_repository.dart';
import '../reflection/reflection_repository.dart';
import '../winter_arc/current_arc_service.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';

/// One arc of the user's Arc History, with its results.
///
/// Not to be confused with [ArcHistory], the derived day-by-day history of
/// a single arc that these numbers are computed from.
final class ArcHistoryCard {
  const ArcHistoryCard({
    required this.session,
    required this.summary,
    required this.reflectionCount,
  });

  final WinterArcSession session;

  /// Totals as of today; final once the arc is completed.
  final ArcSummary summary;
  final int reflectionCount;
}

/// The user's arcs, past and present.
///
/// Listing only reads session rows; each arc's numbers are loaded on demand
/// with [card], so a list shows quickly however many arcs there are and
/// only the cards on screen do any work.
final class ArcHistoryService {
  ArcHistoryService({
    required this._sessions,
    required this._progress,
    required this._achievements,
    required this._reflections,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final ProgressRepository _progress;
  final AchievementRepository _achievements;
  final ReflectionRepository _reflections;
  final Clock _clock;

  /// Every started arc (active or completed), newest first. A session in
  /// setup isn't part of history yet.
  Future<List<WinterArcSession>> sessions() async => [
    for (final s in await _sessions.listSessions())
      if (s.status != WinterArcStatus.setup) s,
  ];

  /// The results of the started arc [sessionId], derived from its own
  /// stored history only.
  Future<ArcHistoryCard> card(int sessionId) async {
    final session = await CurrentArcService(_sessions)
        .requireStarted(sessionId);
    final history = ArcHistory(
      session: session,
      records: await _progress.loadArc(session.id),
      today: _clock.today(),
    );
    final unlocks = await _achievements.unlocks(session.id);
    return ArcHistoryCard(
      session: session,
      summary: ArcSummary.fromHistory(
        history,
        achievementsUnlocked: unlocks.length,
        achievementsTotal: AchievementCatalog.all.length,
      ),
      reflectionCount: await _reflections.countFor(session.id),
    );
  }
}
