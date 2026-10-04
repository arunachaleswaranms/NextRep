import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../domain/insights/insight_snapshot.dart';
import '../journal/journal_controller.dart';

/// Insights across every started arc, recomputed whenever the stored
/// history changes. Derived on demand, never stored.
final insightsProvider = FutureProvider.autoDispose<InsightSnapshot>((ref) {
  ref
    ..watch(arcResolutionProvider)
    ..watch(arcRefreshProvider)
    ..watch(reflectionsChangedProvider)
    ..watch(arcsChangedProvider);
  return ref.watch(insightServiceProvider).snapshot();
});
