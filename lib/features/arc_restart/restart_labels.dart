import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';
import '../../domain/winter_arc/arc_clock_guard.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../arc_pause/pause_labels.dart';

/// Restart and Delete wording (ARC_CONTROL_SPEC §§ 9.9–9.11). Everything
/// the Restart and Delete screens print is here, so the wording can be
/// reviewed in one place (Gate F).

/// Whether [input], trimmed, is exactly [word]: case-sensitive, so
/// "restart" and "RESTAR" never confirm (spec § 6.6).
bool typedWordMatches(String input, String word) => input.trim() == word;

/// "2,430": XP read as a number, with thousands separators.
String xpAmount(int xp) => NumberFormat.decimalPattern('en').format(xp);

/// "1 habit", "7 habits".
String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

abstract final class RestartCopy {
  static const word = 'RESTART';

  /// The entry point, on the Habits screen and the paused Today (§ 9.9).
  static String entry(WinterArcSession session) => session.isSeasonal
      ? 'Start a Rolling Arc with this setup'
      : 'Restart with this setup';

  /// The title before the details are read.
  static const loadingTitle = 'Restart';

  /// The screen's title: the entry point's words.
  static String title(WinterArcSession session) => entry(session);

  /// "A new Rolling 92-Day Arc starts today on Day 1 with your 7 habits,
  /// goals and order."
  static String intro(int habits) =>
      'A new Rolling 92-Day Arc starts today on Day 1 with your '
      '${_count(habits, 'habit', 'habits')}, goals and order.';

  /// Seasonal (§ 9.9): "You will leave the Seasonal Winter Arc on Day 44.
  /// A new Rolling 92-Day Arc starts today on Day 1."
  static String seasonalIntro(int closedDay) =>
      'You will leave the Seasonal Winter Arc on Day $closedDay. A new '
      'Rolling 92-Day Arc starts today on Day 1.';

  /// Seasonal, the reused setup (addition: the seasonal intro has no
  /// habit line of its own).
  static String seasonalHabits(int habits) =>
      'It uses your ${_count(habits, 'habit', 'habits')}, goals and order.';

  /// "Day 1: today, Fri 13 Nov · Day 92: Thu 11 Feb 2027" (addition: the
  /// dates of the new Arc, as on Confirm & Start).
  static String dates(LocalDate today, LocalDate lastDay) =>
      'Day 1: today, ${pauseDate(today, today: today)} · Day 92: '
      '${pauseDate(lastDay, today: today)}';
  static String datesSpoken(LocalDate today, LocalDate lastDay) =>
      'Day 1 is today, ${pauseDateSpoken(today)}. Day 92 is '
      '${pauseDateSpoken(lastDay)}.';

  /// "Your current Arc ends at Day 37 of 92."
  static String endsAt(int day, int total) =>
      'Your current Arc ends at Day $day of $total.';
  static const notCompleted = 'It will not be marked as completed.';
  static const ownProgress =
      'The new Arc starts with 0 XP and its own streaks and achievements.';

  /// Day 92 (spec § 6.4).
  static const lastDay =
      "Today is this Arc's last day. If you wait until tomorrow it will be "
      'completed.';

  /// A pause that Restart removes (additions).
  static const scheduledPauseRemoved =
      'The pause you scheduled is cancelled. Nothing was paused.';
  static const pauseEnds =
      'Your pause ends here. Paused days are never counted.';

  // The old Arc (spec § 6.6).
  static const oldArcHeading = 'Your old Arc';
  static const keep = 'Keep my old Arc in Arc History';
  static const delete = 'Delete my old Arc…';
  static const deleteNote = 'Asks again, separately, after the restart.';

  static const fieldLabel = 'Type RESTART to confirm';
  static String action(WinterArcSession session) =>
      session.isSeasonal ? 'Start Rolling Arc' : 'Restart Arc';

  /// The disabled button's label says why (§ 9.9 accessibility).
  static String actionDisabled(WinterArcSession session) =>
      '${action(session)}. Type RESTART to enable.';
  static const cancel = 'Cancel';
  static const failed = "Couldn't restart. Nothing was changed.";
  static const retry = 'Retry';
  static const dateChanged =
      'The date changed while this was open. These are the new details.';
  static const unavailable =
      "This Arc can't be restarted now. Nothing was changed.";

  /// The clock-guard refusal (spec § 6.7): "Your phone's date (17 Oct) is
  /// earlier than your latest logged day (18 Oct). You can restart from
  /// 18 Oct. Nothing was changed."
  static String clockBehind(ClockGuardBehind guard) {
    final safe = _dayMonth(guard.earliestSafe);
    return "Your phone's date (${_dayMonth(guard.today)}) is earlier than "
        '${_bound(guard.bound)} ($safe). You can restart from $safe. '
        'Nothing was changed.';
  }

  static String clockBehindSpoken(ClockGuardBehind guard) {
    final safe = pauseDateSpoken(guard.earliestSafe);
    return "Your phone's date, ${pauseDateSpoken(guard.today)}, is earlier "
        'than ${_bound(guard.bound)}, $safe. You can restart from $safe. '
        'Nothing was changed.';
  }

  static String _bound(ClockGuardBound bound) => switch (bound) {
    ClockGuardBound.lastActivity => 'your latest logged day',
    ClockGuardBound.lastResume => 'the day your Arc last resumed',
    ClockGuardBound.participationStart => "your Arc's first day",
  };

  static String _dayMonth(LocalDate date) =>
      DateFormat('d MMM').format(date.toLocalDateTime());

  // Success (spec § 9.10).
  static const started = 'Your new Arc has started';

  /// "Day 1 of 92 · Fri 13 Nov 2026"
  static String startedOn(LocalDate today) =>
      'Day 1 of 92 · ${DateFormat('EEE d MMM y').format(today.toLocalDateTime())}';
  static String startedOnSpoken(LocalDate today) =>
      'Day 1 of 92, ${pauseDateSpoken(today)}';
  static const previousInHistory = 'Your previous Arc is in Arc History:';

  /// "Ended early · Day 37 of 92 · 2,430 XP"
  static String previous(int day, int total, int? xp) =>
      'Ended early · Day $day of $total'
      '${xp == null ? '' : ' · ${xpAmount(xp)} XP'}';
  static const goToToday = 'Go to Today';
  static const viewPrevious = 'View previous Arc';
}

abstract final class DeleteArcCopy {
  static const word = 'DELETE';

  static const titleAfterRestart = 'Delete your previous Arc?';

  /// From a finished Arc's summary (addition: that Arc may not be a
  /// "previous" one).
  static const titleFromSummary = 'Delete this Arc?';
  static const afterRestartNote =
      'Your new Arc has started and is safe. This step is separate and '
      'optional.';

  /// "Rolling 92-Day · 7 Oct – 12 Nov 2026"
  static String arcLine(WinterArcSession session, LocalDate today) =>
      '${session.isSeasonal ? 'Seasonal Winter Arc' : 'Rolling 92-Day'} · '
      '${arcDateRange(session, today: today)}';

  /// "Ended early · Day 37 of 92", or "Completed".
  static String status(WinterArcSession session) => switch (session.closedOn) {
    final last? when session.status == WinterArcStatus.ended =>
      'Ended early · Day ${session.dayNumberOf(last)} of '
          '${session.lengthInDays}',
    _ => 'Completed',
  };

  static const removes = 'This permanently removes:';

  /// "37 days of progress and 2,430 XP"; zero is shown as "0".
  static String progress(int days, int xp) =>
      '${_count(days, 'day', 'days')} of progress and ${xpAmount(xp)} XP';
  static String achievements(int n) => _count(n, 'achievement', 'achievements');
  static String reflections(int n) =>
      _count(n, 'Journal reflection', 'Journal reflections');
  static const journey = 'its Journey, weekly reviews and goals';
  static const insights = 'Insights will no longer include it.';
  static const othersKept = 'Other Arcs and your settings are kept.';
  static const noUndo = 'This cannot be undone without a backup.';
  static const exportFirst = 'Export a backup first';
  static const fieldLabel = 'Type DELETE to confirm';
  static const actionAfterRestart = 'Delete previous Arc';
  static const actionFromSummary = 'Delete this Arc';
  static String actionDisabled(String action) =>
      '$action. Type DELETE to enable.';
  static const keep = 'Keep it';
  static const failed = "Couldn't delete. Nothing was removed.";
  static const retry = 'Retry';
  static const deleted = 'Winter Arc deleted.';
  static const loadFailed = "Couldn't load this Arc. Nothing was removed.";
}

/// "Ended early · Day 37 of 92" for an ended Arc (spec § 6.5), or null.
String? endedEarlyLabel(WinterArcSession session) => switch (session.closedOn) {
  final last? when session.status == WinterArcStatus.ended =>
    'Ended early · Day ${session.dayNumberOf(last)} of '
        '${session.lengthInDays}',
  _ => null,
};
