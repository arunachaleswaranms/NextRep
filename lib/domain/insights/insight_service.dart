import '../../core/time/clock.dart';
import '../progress/arc_history.dart';
import '../progress/progress_repository.dart';
import '../reflection/reflection_repository.dart';
import '../winter_arc/winter_arc_repository.dart';
import '../winter_arc/winter_arc_session.dart';
import 'insight_rules.dart';
import 'insight_snapshot.dart';

/// Loads the facts insights need and hands them to [InsightRules]. Only
/// reads; everything is computed on the device, on demand.
final class InsightService {
  InsightService({
    required this._sessions,
    required this._progress,
    required this._reflections,
    required this._clock,
  });

  final WinterArcRepository _sessions;
  final ProgressRepository _progress;
  final ReflectionRepository _reflections;
  final Clock _clock;

  /// Insights across every started arc, as of today.
  Future<InsightSnapshot> snapshot() async {
    final today = _clock.today();
    return InsightRules.compute([
      for (final session in await _sessions.listSessions())
        if (session.status != WinterArcStatus.setup)
          InsightArc(
            history: ArcHistory(
              session: session,
              records: await _progress.loadArc(session.id),
              today: today,
            ),
            moods: await _reflections.moodsFor(session.id),
          ),
    ]);
  }
}
