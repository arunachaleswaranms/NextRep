import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';
import '../../domain/journey/arc_calendar.dart';
import '../../domain/journey/arc_milestones.dart';
import '../../domain/journey/arc_weeks.dart';
import '../../domain/journey/journey_day.dart';
import '../../shared/formatting/arc_labels.dart';
import 'widgets/journey_day_style.dart';

/// Wording of the Arc Consistency Calendar (ARC_MOMENTUM_SPEC §§ 7.3, 8.1,
/// 12.4). Pure: every string comes from the calendar model, the session's
/// stored dates and the shared Journey labels.

/// A calendar cell for a screen reader: the Journey's own label with the
/// date after the day number, e.g. "Day 18, Sunday 18 October. Today. 40
/// percent complete." (spec § 8.1). A day the Arc did not reach, or one
/// whose date is not known yet, names no date.
String calendarDayLabel(JourneyDay day) {
  final journey = journeyDayLabel(day);
  final prefix = 'Day ${day.dayNumber}. ';
  final rest = journey.startsWith(prefix)
      ? journey.substring(prefix.length)
      : journey;
  return switch (day.date) {
    // Its planned date was never lived (spec § 12.4).
    _ when day.state == JourneyDayState.notReached =>
      'Day ${day.dayNumber}. Not reached.',
    final date? => 'Day ${day.dayNumber}, ${_weekdayLong(date)}. $rest',
    null when day.state == JourneyDayState.future =>
      'Day ${day.dayNumber}. Upcoming. Its date is set when you resume.',
    null => journey,
  };
}

/// A week's dates for its heading: "15–21 Oct", "29 Oct – 4 Nov", "28 Dec
/// 2026 – 3 Jan 2027" (spec § 7.3). While an open pause hides the later
/// dates: "8 Mar – paused", or "Dates are set when you resume" when none is
/// known (the Weekly Review's approved wording, spec § 12.3).
String calendarWeekRange(ArcWeek week) =>
    switch ((week.firstDate, week.lastDate)) {
      (final first?, final last?) => calendarDateRange(first, last),
      (final first?, null) => '${_short(first)} – paused',
      _ => 'Dates are set when you resume',
    };

/// "15–21 Oct", "29 Oct – 4 Nov", "28 Dec 2026 – 3 Jan 2027"; a single
/// date reads "11 Mar".
String calendarDateRange(LocalDate first, LocalDate last) {
  if (first == last) return _short(first);
  if (first.year != last.year) {
    return '${_shortYear(first)} – ${_shortYear(last)}';
  }
  if (first.month != last.month) return '${_short(first)} – ${_short(last)}';
  return '${first.day}–${_short(last)}';
}

/// The heading of week [block], e.g. "Week 3 · 15–21 Oct · 2 of 3 days
/// full · This week". The count covers settled days only, as the Weekly
/// Review's (spec § 4.2); weeks that can't be reviewed say why instead.
String calendarWeekHeading(CalendarWeek block) =>
    'Week ${block.number} · ${calendarWeekRange(block.week)} · '
    '${_status(block)}';

/// The heading for a screen reader (spec § 8.1): "Week 3 of 13, 15 to 21
/// October, 2 of 3 days full, this week. Opens the week review." The
/// review action is announced only when the week can be opened.
String calendarWeekHeadingLabel(CalendarWeek block) {
  final week = block.week;
  final dates = switch ((week.firstDate, week.lastDate)) {
    (final first?, final last?) => _longRange(first, last),
    (final first?, null) =>
      'from ${_long(first)}, later dates are set when you resume',
    _ => 'dates are set when you resume',
  };
  final status = [
    for (final part in _status(block).split(' · '))
      part[0].toLowerCase() + part.substring(1),
  ].join(', ');
  return 'Week ${block.number} of ${ArcWeeks.count}, $dates, $status.'
      '${block.isReviewable ? ' Opens the week review.' : ''}';
}

String _status(CalendarWeek block) {
  final count = switch (block.status) {
    ArcWeekStatus.beforeJoining => 'Before you joined',
    ArcWeekStatus.notReached => 'Not reached',
    ArcWeekStatus.upcoming => 'Upcoming',
    ArcWeekStatus.complete ||
    ArcWeekStatus.inProgress ||
    ArcWeekStatus.paused => switch (block.countedDays) {
      0 => 'No finished days yet',
      final counted =>
        '${block.fullDays} of $counted ${counted == 1 ? 'day' : 'days'} '
            'full',
    },
  };
  return switch (block.status) {
    ArcWeekStatus.inProgress => '$count · This week',
    ArcWeekStatus.paused => '$count · Paused',
    _ => count,
  };
}

/// "First Ascent begins on Day 15": a Journey chapter that starts in a
/// week (spec § 7.3).
String calendarChapterLine(JourneyChapter chapter) =>
    '${chapterTitle(chapter)} begins on Day ${chapter.firstDay}';

/// A pause row (spec § 12.4): "Paused 11–19 Mar · 9 days" once resumed,
/// "Paused since 11 Mar" while open, "Pause starts 20 Mar" while still to
/// come. Also its accessibility label. The last paused date is the day
/// before the resume date; an open pause names no end.
String calendarPauseText(CalendarPause pause) {
  final days = pause.pausedDays;
  final last = pause.lastDate;
  if (days != null && last != null) {
    return 'Paused ${calendarDateRange(pause.firstDate, last)} · $days '
        '${days == 1 ? 'day' : 'days'}';
  }
  return pause.scheduled
      ? 'Pause starts ${_short(pause.firstDate)}'
      : 'Paused since ${_short(pause.firstDate)}';
}

String _longRange(LocalDate first, LocalDate last) {
  if (first == last) return _long(first);
  if (first.year != last.year) {
    return '${_longYear(first)} to ${_longYear(last)}';
  }
  if (first.month != last.month) return '${_long(first)} to ${_long(last)}';
  return '${first.day} to ${_long(last)}';
}

String _format(String pattern, LocalDate date) =>
    DateFormat(pattern).format(date.toLocalDateTime());

String _short(LocalDate date) => _format('d MMM', date);
String _shortYear(LocalDate date) => _format('d MMM y', date);
String _long(LocalDate date) => _format('d MMMM', date);
String _longYear(LocalDate date) => _format('d MMMM y', date);
String _weekdayLong(LocalDate date) => _format('EEEE d MMMM', date);
