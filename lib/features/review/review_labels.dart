import 'package:intl/intl.dart';

import '../../core/time/local_date.dart';
import '../../domain/journey/arc_weeks.dart';
import '../../domain/journey/journey_day.dart';
import '../../domain/review/weekly_review.dart';
import '../journey/widgets/journey_day_style.dart';

/// "Complete", "In progress", "Paused": a reviewable week's status.
String weekStatusLabel(ArcWeekStatus status) => switch (status) {
  ArcWeekStatus.complete => 'Complete',
  ArcWeekStatus.inProgress => 'In progress',
  ArcWeekStatus.paused => 'Paused',
  ArcWeekStatus.upcoming => 'Upcoming',
  ArcWeekStatus.beforeJoining => 'Before you joined',
  ArcWeekStatus.notReached => 'Not reached',
};

/// "Thu 15 Oct – Wed 21 Oct", with the year on both sides when the week
/// crosses one; "· includes a 9-day pause" when a closed pause falls
/// inside it; "Sun 8 Mar – paused" while an open pause hides its later
/// dates (spec § 12.3).
String weekDateRange(ArcWeek week) {
  final first = week.firstDate;
  final last = week.lastDate;
  if (first == null) return 'Dates are set when you resume';
  if (last == null) return '${_short(first, false)} – paused';
  final years = first.year != last.year;
  final range = '${_short(first, years)} – ${_short(last, years)}';
  final paused = week.pausedDaysWithin;
  return paused > 0 ? '$range · includes a $paused-day pause' : range;
}

/// The review header in words for a screen reader (spec § 8.1): "Week 3
/// of 13. Days 15 to 21. Thursday 15 October to Wednesday 21 October. In
/// progress."
String reviewHeaderLabel(WeeklyReview review) {
  final week = review.week;
  final first = week.firstDate;
  final last = week.lastDate;
  final dates = switch ((first, last)) {
    (final f?, final l?) => '${_long(f)} to ${_long(l)}. ',
    (final f?, null) =>
      'From ${_long(f)}; later dates are set when you '
          'resume. ',
    _ => 'Its dates are set when you resume. ',
  };
  final paused = switch (review.pausedSince) {
    final since? => ' Paused since ${_long(since)}.',
    null => '',
  };
  return 'Week ${week.number} of ${ArcWeeks.count}. Days ${week.firstDay} '
      'to ${week.lastDay}. $dates${weekStatusLabel(week.status)}.$paused';
}

/// A week-strip day for a screen reader: its day number, date, state and
/// progress, e.g. "Day 18, Sunday 18 October. Today. 40 percent
/// complete." (spec § 8.1). A day without a known date says so.
String reviewDayLabel(ReviewDay day) {
  final journey = journeyDayLabel(day.journeyDay);
  final prefix = 'Day ${day.dayNumber}. ';
  final rest = journey.startsWith(prefix)
      ? journey.substring(prefix.length)
      : journey;
  return switch (day.date) {
    final date? => 'Day ${day.dayNumber}, ${_long(date)}. $rest',
    null when day.journeyDay.state == JourneyDayState.future =>
      'Day ${day.dayNumber}. Upcoming. Its date is set when you resume.',
    null => journey,
  };
}

String _short(LocalDate date, bool year) =>
    DateFormat(year ? 'EEE d MMM y' : 'EEE d MMM')
        .format(date.toLocalDateTime());

String _long(LocalDate date) =>
    DateFormat('EEEE d MMMM').format(date.toLocalDateTime());
