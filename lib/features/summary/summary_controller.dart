import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../domain/progress/arc_summary.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../achievements/achievements_controller.dart';

/// The summary of one arc, with the arc it describes.
final class SummaryView {
  const SummaryView({required this.session, required this.summary});

  final WinterArcSession session;
  final ArcSummary summary;
}

/// Derives the summary of arc [sessionId] from its stored history only.
///
/// When that arc is the app's home (it just completed and nothing new is
/// set up), achievements are reconciled first so the Summit unlock earned by
/// finishing is counted. Any other arc is history and only read.
final summaryControllerProvider = FutureProvider.autoDispose
    .family<SummaryView, int>((ref, sessionId) async {
      final tracking = ref.watch(habitTrackingServiceProvider);
      final achievements = ref.watch(achievementServiceProvider);
      if (ref.read(arcResolutionProvider)?.home?.id == sessionId) {
        await ref.read(achievementSyncProvider).run();
      }
      final history = await tracking.historyFor(sessionId);
      final board = await achievements.boardFor(sessionId);
      return SummaryView(
        session: history.session,
        summary: ArcSummary.fromHistory(
          history,
          achievementsUnlocked: board.unlockedCount,
          achievementsTotal: board.total,
        ),
      );
    });
