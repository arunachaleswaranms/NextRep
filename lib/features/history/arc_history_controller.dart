import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../domain/history/arc_history_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../achievements/achievements_controller.dart';
import '../journal/journal_controller.dart';

/// Every started arc, newest first. Only session rows are read here; each
/// card loads its own numbers ([arcHistoryCardProvider]).
final arcHistoryProvider = FutureProvider.autoDispose<List<WinterArcSession>>((
  ref,
) {
  // A close-out or a new arc changes the list.
  ref.watch(arcResolutionProvider);
  return ref.watch(arcHistoryServiceProvider).sessions();
});

/// The results of arc [sessionId] for its card. Loaded only while the card
/// is on screen. The active arc's card re-reads when it changes.
final arcHistoryCardProvider = FutureProvider.autoDispose
    .family<ArcHistoryCard, int>((ref, sessionId) {
      if (ref.watch(arcResolutionProvider)?.active?.id == sessionId) {
        ref.watch(arcRefreshProvider);
        ref.watch(reflectionsChangedProvider);
        // Unlocks are stored by a follow-up reconcile, after the action's
        // own refresh, so they need their own trigger.
        ref.watch(achievementsChangedProvider);
      }
      return ref.watch(arcHistoryServiceProvider).card(sessionId);
    });
