import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../domain/journey/journey_overview.dart';

/// The arc's 92 days, derived from stored history. Read-only; re-read
/// whenever the arc changes elsewhere.
final journeyControllerProvider = FutureProvider.autoDispose<JourneyOverview>((
  ref,
) {
  ref.watch(arcRefreshProvider);
  return ref.watch(habitTrackingServiceProvider).journey();
});
