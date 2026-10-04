import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencies.dart';
import '../../domain/achievement/achievement_catalog.dart';
import '../../domain/progress/arc_summary.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../achievements/achievements_controller.dart';

/// The End-of-Arc summary with the arc it describes.
final class SummaryView {
  const SummaryView({required this.session, required this.summary});

  final WinterArcSession session;
  final ArcSummary summary;
}

/// Derives the summary from stored history. Achievements are reconciled
/// first, so the Summit unlock earned by finishing is counted.
final summaryControllerProvider = FutureProvider.autoDispose<SummaryView>((
  ref,
) async {
  final tracking = ref.watch(habitTrackingServiceProvider);
  final achievements = ref.watch(achievementServiceProvider);
  await ref.read(achievementSyncProvider).run();
  final history = await tracking.history();
  final board = await achievements.board();
  return SummaryView(
    session: history.session,
    summary: ArcSummary.fromHistory(
      history,
      achievementsUnlocked: board?.unlockedCount ?? 0,
      achievementsTotal: board?.total ?? AchievementCatalog.all.length,
    ),
  );
});
