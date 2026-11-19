import '../../core/time/local_date.dart';
import '../progress/day_record.dart';
import '../winter_arc/winter_arc_session.dart';
import 'arc_milestones.dart';
import 'arc_weeks.dart';
import 'journey_day.dart';
import 'journey_overview.dart';

/// One challenge day of the Arc Consistency Calendar: the Journey's own
/// [JourneyDay] for that day, beside its Arc-week day.
///
/// Nothing here classifies a day. [state], [isToday], [date] and [record]
/// are the Journey's, by identity: the calendar is another layout of the
/// same computation (ARC_MOMENTUM_SPEC § 7.2, decision D6).
final class CalendarDay {
  const CalendarDay({required this.journeyDay, required this.weekDay});

  /// The day exactly as `JourneyOverview.days` holds it.
  final JourneyDay journeyDay;

  /// The same day in its Arc week ([ArcWeeks]): its day class.
  final ArcWeekDay weekDay;

  int get dayNumber => journeyDay.dayNumber;

  /// Null while the day comes after the start of an open pause: never an
  /// estimate.
  LocalDate? get date => journeyDay.date;
  JourneyDayState get state => journeyDay.state;
  bool get isToday => journeyDay.isToday;
  DayRecord? get record => journeyDay.record;

  /// Whether tapping the day opens something, always read-only: the detail
  /// of a past day or today, or the note of a day before joining. Upcoming
  /// and not-reached days have nothing to open.
  bool get isInteractive => !journeyDay.isFuture;

  /// Counted in its week's "x of y days full" (a settled day).
  bool get isSettled => weekDay.dayClass == ArcDayClass.settled;

  /// A settled day whose stored record is a full day: a Perfect Day or a
  /// completed Minimum Day, exactly the Weekly Review's "full" (spec
  /// § 4.2). Read from the Journey state, which for a settled day is
  /// `perfect` or `minimumComplete` exactly when the record is.
  bool get isFull =>
      isSettled &&
      (state == JourneyDayState.perfect ||
          state == JourneyDayState.minimumComplete);
}

/// A pause of a Rolling Arc as the calendar shows it: one row between the
/// last challenge day before it and the first one after (spec § 12.4). It
/// is not a challenge day: it has no cell, no day number and no state, and
/// is never counted.
final class CalendarPause {
  const CalendarPause({
    required this.freeze,
    required this.afterDay,
    required this.scheduled,
  });

  final ArcFreeze freeze;

  /// The last challenge day before the pause (`1..91`). The pause row sits
  /// right after that day's cell.
  final int afterDay;

  /// Still to come: an open pause whose first date is after today (a
  /// "freeze scheduled" Arc). Today still counts.
  final bool scheduled;

  /// The first paused date.
  LocalDate get firstDate => freeze.frozenFrom;

  /// The last paused date, the day before the resume date (`resumedOn` is
  /// a challenge day, not a paused one); null while the pause is open.
  LocalDate? get lastDate => freeze.resumedOn?.addDays(-1);

  /// The number of paused dates, null while open.
  int? get pausedDays => freeze.pausedDays;

  bool get isOpen => freeze.isOpen;
}

/// An entry of a week block, in chronological order: a day cell or a pause
/// row.
sealed class CalendarEntry {
  const CalendarEntry();
}

final class CalendarDayEntry extends CalendarEntry {
  const CalendarDayEntry(this.day);

  final CalendarDay day;
}

final class CalendarPauseEntry extends CalendarEntry {
  const CalendarPauseEntry(this.pause);

  final CalendarPause pause;
}

/// One of the calendar's 13 week blocks: its Arc week, its 7 (or 8) days
/// and any pause rows, in order.
final class CalendarWeek {
  CalendarWeek._({
    required this.week,
    required this.days,
    required this.entries,
    required this.chapters,
  });

  final ArcWeek week;

  /// The week's days, Day [ArcWeek.firstDay] first.
  final List<CalendarDay> days;

  /// The week's days and pause rows, in chronological order.
  final List<CalendarEntry> entries;

  /// The Journey chapters that begin on one of this week's days, in order.
  final List<JourneyChapter> chapters;

  int get number => week.number;
  ArcWeekStatus get status => week.status;

  /// Whether the heading opens the week's Weekly Review.
  bool get isReviewable => week.isReviewable;

  /// The pause rows of this block.
  Iterable<CalendarPause> get pauses => [
    for (final entry in entries)
      if (entry case CalendarPauseEntry(:final pause)) pause,
  ];

  /// Settled days: the "y" of "x of y days full". Never upcoming, today,
  /// before-joining, not-reached or paused dates.
  late final int countedDays = days.where((d) => d.isSettled).length;

  /// Settled full days: the "x" of "x of y days full".
  late final int fullDays = days.where((d) => d.isFull).length;
}

/// The Arc Consistency Calendar (ARC_MOMENTUM_SPEC §§ 7, 12.4): the
/// Journey's 92 days laid out in the 13 Arc weeks. Pure and read-only.
///
/// It is built from a loaded [JourneyOverview] and nothing else: no
/// repository, no provider, no clock. Every cell is the Journey's own
/// [JourneyDay]; week boundaries, day classes and statuses are
/// [ArcWeeks]'; pause rows come from the session's freeze intervals.
final class ArcCalendar {
  ArcCalendar._({
    required this.journey,
    required this.weeks,
    required this.blocks,
    required this.pauses,
  });

  /// The calendar of [journey]. [weeks], when given, must be
  /// `ArcWeeks.of(journey.session, journey.today)`; it is accepted only to
  /// avoid computing it twice.
  ///
  /// Throws [StateError] if [journey] doesn't list the Arc's 92 challenge
  /// days in order, or a day's date disagrees with its Arc week.
  factory ArcCalendar.of(JourneyOverview journey, {ArcWeeks? weeks}) {
    final arcWeeks = weeks ?? ArcWeeks.of(journey.session, journey.today);
    if (!identical(arcWeeks.session, journey.session) ||
        arcWeeks.today != journey.today) {
      throw ArgumentError.value(weeks, 'weeks', 'weeks of another Journey');
    }
    final days = journey.days;
    if (days.length != WinterArcRules.lengthInDays) {
      throw StateError('a Journey of ${days.length} days');
    }

    final pauses = _pausesOf(journey.session, journey.today);
    final blocks = <CalendarWeek>[
      for (final week in arcWeeks.weeks)
        () {
          final calendarDays = [
            for (final weekDay in week.days)
              () {
                final journeyDay = days[weekDay.dayNumber - 1];
                if (journeyDay.dayNumber != weekDay.dayNumber ||
                    journeyDay.date != weekDay.date) {
                  throw StateError(
                    'Day ${weekDay.dayNumber}: the Journey and the Arc week '
                    'disagree',
                  );
                }
                return CalendarDay(journeyDay: journeyDay, weekDay: weekDay);
              }(),
          ];
          final entries = <CalendarEntry>[
            for (final day in calendarDays) ...[
              CalendarDayEntry(day),
              for (final pause in pauses)
                if (pause.afterDay == day.dayNumber) CalendarPauseEntry(pause),
            ],
          ];
          return CalendarWeek._(
            week: week,
            days: List.unmodifiable(calendarDays),
            entries: List.unmodifiable(entries),
            chapters: List.unmodifiable([
              for (final chapter in JourneyChapter.values)
                if (chapter.firstDay >= week.firstDay &&
                    chapter.firstDay <= week.lastDay)
                  chapter,
            ]),
          );
        }(),
    ];
    return ArcCalendar._(
      journey: journey,
      weeks: arcWeeks,
      blocks: List.unmodifiable(blocks),
      pauses: List.unmodifiable(pauses),
    );
  }

  final JourneyOverview journey;
  final ArcWeeks weeks;

  /// The 13 week blocks, Week 1 first.
  final List<CalendarWeek> blocks;

  /// Every pause of the Arc, oldest first; each is in exactly one block.
  final List<CalendarPause> pauses;

  /// Week [number], `1..13`.
  CalendarWeek block(int number) => blocks[weeks.week(number).number - 1];

  /// Every day cell, Day 1 first.
  Iterable<CalendarDay> get days => [for (final block in blocks) ...block.days];

  /// The week the calendar opens on: the week in progress, else the paused
  /// week, else the latest reviewable one (Week 13 of a completed Arc, the
  /// week of an ended Arc's last day), as the Weekly Review opens
  /// ([ArcWeeks.defaultWeek]). Before the participation start, when no
  /// week is reviewable, the week the user joins in.
  int get initialWeek => weeks.defaultWeek ?? weeks.joinWeek;

  /// The session's pauses, each placed after the last challenge day before
  /// it. Computed from the interval bounds only.
  static List<CalendarPause> _pausesOf(
    WinterArcSession session,
    LocalDate today,
  ) => [
    for (final freeze in session.freezes)
      CalendarPause(
        freeze: freeze,
        // The date before a pause is always a challenge date: a pause
        // starts after a lived day and never touches another one
        // (ArcFreezeRules.problemWith).
        afterDay: (session.dayNumberOf(freeze.frozenFrom.addDays(-1)) ?? 1)
            .clamp(1, WinterArcRules.lengthInDays - 1),
        scheduled: freeze.isOpen && freeze.frozenFrom.isAfter(today),
      ),
  ];
}
