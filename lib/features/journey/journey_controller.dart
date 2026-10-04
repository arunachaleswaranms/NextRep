import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../domain/journey/journey_overview.dart';
import '../achievements/achievements_controller.dart';

/// The arc's 92 days, derived from stored history. Read-only; re-read
/// whenever the arc changes elsewhere.
///
/// Loading the Journey is an app entry point: it runs the arc close-out
/// check first and reconciles achievements afterwards (best effort).
final journeyControllerProvider = FutureProvider.autoDispose<JourneyOverview>((
  ref,
) async {
  ref.watch(arcRefreshProvider);
  final tracking = ref.watch(habitTrackingServiceProvider);
  final status = ref.read(arcStatusProvider.notifier);
  final achievements = ref.read(achievementSyncProvider);
  await status.reconcile();
  final journey = await tracking.journey();
  await achievements.run();
  return journey;
});
