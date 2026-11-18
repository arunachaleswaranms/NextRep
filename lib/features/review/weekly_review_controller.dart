import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../domain/journey/arc_weeks.dart';
import '../../domain/progress/arc_history.dart';
import '../../domain/review/weekly_review.dart';

/// One coherent snapshot for the Weekly Review: an Arc's history as of one
/// local date, and its 13 weeks on that date. Every week's review is
/// computed from it in memory, so changing weeks reads nothing.
final class WeeklyReviewSource {
  WeeklyReviewSource(this.history)
    : weeks = ArcWeeks.of(history.session, history.today);

  final ArcHistory history;
  final ArcWeeks weeks;

  /// The review of reviewable week [week] (see [ArcWeeks.resolve]).
  WeeklyReview review(int week) =>
      WeeklyReview.fromHistory(history, week, weeks: weeks);
}

/// The Weekly Review's data: with a null session id the home (active) Arc,
/// with an id that Arc, as Arc History shows it. **Read-only**: one session
/// lookup and one `loadArc` per load, through
/// [HabitTrackingService.history] / [HabitTrackingService.historyFor].
///
/// Unlike the Journey's provider it never closes out an Arc, syncs or
/// backfills achievements, schedules reminders or writes anything, so
/// opening or browsing a review leaves every table as it was. It re-reads
/// when the Arc changes ([arcRefreshProvider]) and when the local date
/// changes with the app open ([dayChangedProvider]); the screen also
/// re-reads on resume.
final weeklyReviewSourceProvider = FutureProvider.autoDispose
    .family<WeeklyReviewSource, int?>((ref, sessionId) async {
      ref
        ..watch(arcRefreshProvider)
        ..watch(dayChangedProvider);
      final tracking = ref.watch(habitTrackingServiceProvider);
      final history = sessionId == null
          ? await tracking.history()
          : await tracking.historyFor(sessionId);
      return WeeklyReviewSource(history);
    });
