import 'dart:convert';

import '../../core/time/local_date.dart';
import '../progress/arc_history.dart';
import '../progress/day_record.dart';
import '../progress/day_rules.dart';
import '../winter_arc/winter_arc_session.dart';
import 'reminder_preferences.dart';

/// The stable id of the built-in Water habit (the `water` template).
///
/// Hydration Coach follows this habit only. It is recognised by id, never
/// by title: a renamed built-in Water habit still counts, and a custom habit
/// the user called "Water" (its id is `custom_<hex>`) never does.
const builtInWaterHabitId = 'water';

/// What Hydration Coach knows about one date, gathered by the reminder
/// service from the arc's stored records. The planner never reads storage.
final class HydrationDay {
  const HydrationDay({
    required this.date,
    required this.participating,
    required this.water,
    this.lastLoggedAt,
  });

  /// The date's state as [DayRules] sees it: the built-in Water habit's
  /// entry in [DayRules.recordFor], with that date's habit revisions and
  /// day mode (so a Minimum Day target where one applies) and its stored
  /// progress (none for a future date). [lastLoggedAt] goes with today
  /// only.
  factory HydrationDay.of({
    required WinterArcSession arc,
    required ArcRecords records,
    required LocalDate date,
    DateTime? lastLoggedAt,
  }) => HydrationDay(
    date: date,
    participating: arc.isParticipatingOn(date),
    water: DayRules.recordFor(
      date: date,
      habits: records.habits,
      mode: records.modeOn(date),
      progress: records.progressOn(date),
    ).entryFor(builtInWaterHabitId),
    lastLoggedAt: lastLoggedAt,
  );

  final LocalDate date;

  /// One of the arc's participating dates (never before a seasonal arc was
  /// joined, never after its last day).
  final bool participating;

  /// The built-in Water habit on [date]: its effective target (normal or
  /// Minimum Day) and progress. Null when the arc has no built-in Water
  /// habit or it is turned off on [date].
  final HabitDayEntry? water;

  /// When today's Water progress was last written, if it was.
  final DateTime? lastLoggedAt;

  /// The Water target Hydration Coach paces against on [date], or null if
  /// it doesn't run that day.
  int? get target {
    final entry = water;
    if (!participating || entry == null || !entry.habit.type.isNumeric) {
      return null;
    }
    return entry.target;
  }

  int get progress => water?.progress.currentValue ?? 0;
}

/// One pacing checkpoint: by [at], the user is expected to have logged
/// [expected] of the day's Water target.
final class HydrationCheckpoint {
  const HydrationCheckpoint({
    required this.date,
    required this.slot,
    required this.at,
    required this.expected,
  });

  final LocalDate date;

  /// 0-based position within the day.
  final int slot;

  /// Local wall-clock time.
  final DateTime at;

  /// Cumulative Water expected by [at].
  final int expected;

  @override
  String toString() => 'HydrationCheckpoint($date #$slot $at ≥$expected)';
}

/// Pure, deterministic planning of Hydration Coach nudges.
///
/// Hydration Coach is a pacing coach, not a timer. Each day gets at most
/// `min(mode maximum, Water target)` broad checkpoints spread across the
/// active hours, each expecting its share of the day's target. A nudge is
/// planned for a checkpoint only if, when the plan is made, the user is
/// behind that checkpoint's share, the checkpoint is still ahead, and it
/// isn't within [recentLogGrace] of the last Water log. On pace, ahead or
/// done: nothing. The reminder service re-plans after every change (Water
/// logged, Minimum Day, settings, a new day), so the plan follows progress.
abstract final class HydrationPlanner {
  /// Days ahead hydration is planned, today included: 7 × 5 nudges at most,
  /// which together with 14 daily and 14 reflection reminders stays within
  /// iOS's 64 pending notifications.
  static const horizonDays = 7;

  /// The most nudges any mode allows in a day ([HydrationMode.supportive]).
  static const maxNudgesPerDay = 5;

  /// A checkpoint this soon after Water was logged is skipped (not moved).
  static const recentLogGrace = Duration(minutes: 45);

  /// Largest daily variation of a checkpoint time, either way.
  static const maxJitterMinutes = 15;

  /// The nudges to have pending at [now], given each day in [days].
  static List<HydrationCheckpoint> plan({
    required HydrationMode mode,
    required HydrationWindow window,
    required Iterable<HydrationDay> days,
    required DateTime now,
  }) => [
    for (final day in days)
      if (day.target case final target? when day.progress < target)
        for (final checkpoint in checkpointsFor(
          date: day.date,
          target: target,
          mode: mode,
          window: window,
        ))
          if (checkpoint.at.isAfter(now) &&
              day.progress < checkpoint.expected &&
              !_justLogged(day.lastLoggedAt, checkpoint.at))
            checkpoint,
  ];

  /// Every checkpoint of [date] for a Water [target], before progress is
  /// taken into account.
  ///
  /// * count: `min(mode.maxNudges, target)`, so every checkpoint expects
  ///   one more glass at least and no two expect the same amount
  /// * base times: evenly from 15 % to 90 % of the window; a single
  ///   checkpoint at 62.5 %, past the middle of the day
  /// * each moves by up to ±[maxJitterMinutes], decided by [jitterMinutes]
  /// * checkpoint i expects `ceil(target × (i + 1) / count)`, so the last
  ///   one expects the whole target
  ///
  /// Order and spacing hold by construction: the shortest window (8 h)
  /// with the most checkpoints (5) has bases 90 minutes apart, so after
  /// ±15 minutes each they are still at least an hour apart. The first
  /// base is 72 minutes or more after the start and the last 48 minutes or
  /// more before the end, so every time stays inside the window.
  static List<HydrationCheckpoint> checkpointsFor({
    required LocalDate date,
    required int target,
    required HydrationMode mode,
    required HydrationWindow window,
  }) {
    if (target <= 0) return const [];
    final count = mode.maxNudges < target ? mode.maxNudges : target;
    final start = window.start.minuteOfDay;
    final length = window.lengthInMinutes;
    return [
      for (var i = 0; i < count; i++)
        () {
          final base = count == 1
              ? start + length * 5 ~/ 8
              : start +
                    length * (15 * (count - 1) + 75 * i) ~/ (100 * (count - 1));
          final minute = base + jitterMinutes(date, mode, window, i);
          return HydrationCheckpoint(
            date: date,
            slot: i,
            // The local constructor applies the device's time zone and
            // daylight saving for that date.
            at: DateTime(date.year, date.month, date.day, 0, minute),
            expected: (target * (i + 1) + count - 1) ~/ count,
          );
        }(),
    ];
  }

  /// The daily variation of checkpoint [index], `-15..15` minutes.
  ///
  /// Derived only from the date, the mode, the window and the index through
  /// [stableHash], so re-planning (a resume, a restart, another device)
  /// always gives the same times and nothing moves until the settings do.
  static int jitterMinutes(
    LocalDate date,
    HydrationMode mode,
    HydrationWindow window,
    int index,
  ) {
    final key =
        '${date.toIsoString()}|${mode.name}|${window.start}|${window.end}|'
        '$index';
    return stableHash(key) % (2 * maxJitterMinutes + 1) - maxJitterMinutes;
  }

  /// 32-bit FNV-1a of [text]'s UTF-8 bytes. Unlike `String.hashCode` or
  /// `Object.hash`, its value is specified, so it is the same in every
  /// process, run and app version.
  static int stableHash(String text) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(text)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static bool _justLogged(DateTime? loggedAt, DateTime at) =>
      loggedAt != null &&
      !at.isBefore(loggedAt) &&
      at.difference(loggedAt) < recentLogGrace;
}
