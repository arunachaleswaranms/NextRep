import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';
import '../../domain/winter_arc/arc_clock_guard.dart';

/// Freeze and Resume wording (ARC_CONTROL_SPEC §§ 9.6–9.8). Everything the
/// pause screens print is here, so the wording can be reviewed in one
/// place (Gate E2).

/// "Sat 14 Nov", with the year when it isn't [today]'s ("Mon 25 Jan 2027").
String pauseDate(LocalDate date, {required LocalDate today}) =>
    DateFormat(date.year == today.year ? 'EEE d MMM' : 'EEE d MMM y')
        .format(date.toLocalDateTime());

/// "Saturday 14 November 2026": how a screen reader reads a date (spec
/// § 9.6 "the dates are read as full dates").
String pauseDateSpoken(LocalDate date) =>
    DateFormat('EEEE d MMMM y').format(date.toLocalDateTime());

/// "14 Nov": the short form used inside a sentence about a refusal.
String _dayMonth(LocalDate date) =>
    DateFormat('d MMM').format(date.toLocalDateTime());

/// "1 day", "6 days".
String dayCount(int days) => '$days ${days == 1 ? 'day' : 'days'}';

abstract final class PauseCopy {
  static const menuItem = 'Pause Arc';
  static const sheetTitle = 'Pause your Arc';
  static const pauseAction = 'Pause from tomorrow';
  static const notNow = 'Not now';
  static const pauseFailed = "Couldn't pause. Nothing was changed.";
  static const retry = 'Retry';
  static const dateChanged =
      'The date changed while this was open. These are the new dates.';

  /// "From tomorrow, Sat 14 Nov, your Arc stops counting days until you
  /// resume."
  static String intro(LocalDate frozenFrom, LocalDate today) =>
      'From tomorrow, ${pauseDate(frozenFrom, today: today)}, your Arc '
      'stops counting days until you resume.';

  static String introSpoken(LocalDate frozenFrom) =>
      'From tomorrow, ${pauseDateSpoken(frozenFrom)}, your Arc stops '
      'counting days until you resume.';

  static String todayCounts(int day) =>
      'Today (Day $day) still counts. You can finish it, or use a Minimum '
      'Day.';
  static const neverMissed = 'Paused days are never missed days.';
  static String continuesOn(int nextDay) =>
      'You continue on Day $nextDay when you resume; your last day moves '
      'later.';
  static const remindersPause = 'Reminders pause.';
  static const focusGuardOwn = 'Focus Guard keeps its own schedule.';
  static const focusGuardLink = 'Focus Guard settings';

  /// The clock-guard refusal (spec § 5.3, addendum AD19): "Your phone's
  /// date (9 Mar) is earlier than your latest logged day (10 Mar). You can
  /// pause from 10 Mar. Nothing was changed."
  static String clockBehind(ClockGuardBehind guard) {
    final latest = switch (guard.bound) {
      ClockGuardBound.lastActivity => 'your latest logged day',
      ClockGuardBound.lastResume => 'the day your Arc last resumed',
      ClockGuardBound.participationStart => "your Arc's first day",
    };
    final safe = _dayMonth(guard.earliestSafe);
    return "Your phone's date (${_dayMonth(guard.today)}) is earlier than "
        '$latest ($safe). You can pause from $safe. Nothing was changed.';
  }

  static String clockBehindSpoken(ClockGuardBehind guard) {
    final latest = switch (guard.bound) {
      ClockGuardBound.lastActivity => 'your latest logged day',
      ClockGuardBound.lastResume => 'the day your Arc last resumed',
      ClockGuardBound.participationStart => "your Arc's first day",
    };
    final safe = pauseDateSpoken(guard.earliestSafe);
    return "Your phone's date, ${pauseDateSpoken(guard.today)}, is earlier "
        'than $latest, $safe. You can pause from $safe. Nothing was '
        'changed.';
  }

  /// Shown instead of the Pause action when the pause can't be scheduled
  /// today for another reason (a stale sheet: Day 92 arrived, a pause was
  /// scheduled elsewhere).
  static const unavailable =
      "Your Arc can't be paused today. Nothing was changed.";

  // Scheduled banner (spec § 9.6).
  static const bannerTomorrow = 'Pause starts tomorrow. Today still counts.';
  static String bannerOn(LocalDate frozenFrom, LocalDate today) =>
      'Pause starts ${pauseDate(frozenFrom, today: today)}. Today still '
      'counts.';
  static const cancelAction = 'Cancel pause';

  /// Shown instead of Cancel pause when the phone's date isn't the day the
  /// pause was set (a clock moved back; Gate E2 review R1).
  static String cancelOnlyOn(LocalDate scheduledOn, LocalDate today) =>
      'This pause can only be cancelled on '
      '${pauseDate(scheduledOn, today: today)}, the day it was set.';
  static String cancelOnlyOnSpoken(LocalDate scheduledOn) =>
      'This pause can only be cancelled on ${pauseDateSpoken(scheduledOn)}, '
      'the day it was set.';
  static const cancelled = 'Pause cancelled. Nothing was paused.';
  static const cancelFailed = "Couldn't cancel the pause. Please try again.";
}

abstract final class PausedCopy {
  static const heading = 'Arc paused';

  /// "Paused since Sat 14 Nov · 6 days", or "Paused since today, Sat 14
  /// Nov" on its first date.
  static String since(LocalDate pausedSince, int days, LocalDate today) =>
      days == 0
      ? 'Paused since today, ${pauseDate(pausedSince, today: today)}'
      : 'Paused since ${pauseDate(pausedSince, today: today)} · '
            '${dayCount(days)}';

  static String sinceSpoken(LocalDate pausedSince, int days) => days == 0
      ? 'Paused since today, ${pauseDateSpoken(pausedSince)}'
      : 'Paused since ${pauseDateSpoken(pausedSince)}, ${dayCount(days)}';

  /// A pause the date moved back into (spec § 9.7 empty state): "Paused
  /// Sat 14 Nov – Thu 19 Nov".
  static String closed(LocalDate from, LocalDate resumedOn, LocalDate today) =>
      'Paused ${pauseDate(from, today: today)} – '
      '${pauseDate(resumedOn.addDays(-1), today: today)}';

  static String closedSpoken(LocalDate from, LocalDate resumedOn) =>
      'Paused from ${pauseDateSpoken(from)} to '
      '${pauseDateSpoken(resumedOn.addDays(-1))}';

  static String stoppedAfter(int lastDay, int total) =>
      'You stopped after Day $lastDay of $total.';
  static String becomes(int nextDay) =>
      'When you resume, that day becomes Day $nextDay.';
  static const noCount = "Paused days don't count against you.";
  static String continuesOn(LocalDate date, LocalDate today) =>
      'Continues on ${pauseDate(date, today: today)}.';
  static String continuesOnSpoken(LocalDate date) =>
      'Continues on ${pauseDateSpoken(date)}.';
  static const resumeAction = 'Resume Arc';
  static const journey = 'Journey';
  static const journal = 'Journal';
  static const history = 'Arc History';

  /// Habits and Journal while paused (spec § 9.7 "each place says Paused").
  static const habitsReadOnly =
      'Your Arc is paused. Habits can be edited again when you resume.';
  static const journalReadOnly =
      'Your Arc is paused. Reflections continue when you resume.';
}

abstract final class ResumeCopy {
  static const title = 'Resume your Arc?';
  static const resumeAction = 'Resume today';
  static const notYet = 'Not yet';
  static const failed = "Couldn't resume. Your Arc is still paused.";
  static const notPaused = 'Your Arc is not paused today.';

  /// "Today, Fri 20 Nov, becomes Day 26 of 92."
  static String becomes(LocalDate today, int day, int total) =>
      'Today, ${pauseDate(today, today: today)}, becomes Day $day of $total.';
  static String becomesSpoken(LocalDate today, int day, int total) =>
      'Today, ${pauseDateSpoken(today)}, becomes Day $day of $total.';

  /// "Your new last day is Mon 25 Jan 2027."
  static String lastDay(LocalDate lastDay, LocalDate today) =>
      'Your new last day is ${pauseDate(lastDay, today: today)}.';
  static String lastDaySpoken(LocalDate lastDay) =>
      'Your new last day is ${pauseDateSpoken(lastDay)}.';

  /// "You paused for 6 days." (this pause); with earlier pauses, the Arc's
  /// total follows.
  static String pausedFor(int days) =>
      days == 0 ? 'No days were paused.' : 'You paused for ${dayCount(days)}.';
  static String totalPaused(int days) =>
      'Paused days in this Arc: ${dayCount(days)}.';
}

/// "Paused 9 days" for the Arc summary and its Arc History card (spec
/// § 5.2 F11), or null for an arc that was never paused.
String? pausedTotalLabel(int days) =>
    days == 0 ? null : 'Paused ${dayCount(days)}';
