import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

/// Day 1 of the arcs built by these helpers.
final day1 = LocalDate(2026, 10, 1);

/// A test habit. Numeric unless [binary].
Habit habit(
  String id, {
  int target = 8,
  int? minimum,
  bool enabled = true,
  bool binary = false,
  int sortOrder = 0,
}) => Habit(
  id: id,
  title: id,
  type: binary ? HabitType.binary : HabitType.count,
  target: binary ? 1 : target,
  minimumTarget: binary ? 1 : (minimum ?? 1),
  unit: binary ? null : 'u',
  iconKey: id,
  enabled: enabled,
  sortOrder: sortOrder,
  createdAt: DateTime(2026, 10, 1),
);

HabitRevision revision(
  String habitId,
  LocalDate from, {
  required int target,
  int minimum = 1,
  bool enabled = true,
}) => HabitRevision(
  habitId: habitId,
  effectiveFrom: from,
  config: HabitConfig(target: target, minimumTarget: minimum, enabled: enabled),
  createdAt: from.toLocalDateTime(),
);

/// Stored progress of [value]; [completed] defaults to `value > 0`.
DailyHabitProgress progress(
  String habitId,
  LocalDate date,
  int value, {
  bool? completed,
}) {
  final done = completed ?? value > 0;
  return DailyHabitProgress(
    habitId: habitId,
    date: date,
    currentValue: value,
    completed: done,
    completedAt: done ? date.toLocalDateTime() : null,
  );
}

/// An active 92-day session starting on [day1].
WinterArcSession activeSession() => WinterArcSession(
  id: 1,
  startDate: day1,
  endDate: WinterArcRules.endDateFor(day1),
  status: WinterArcStatus.active,
  createdAt: DateTime(2026, 10, 1),
  startedAt: DateTime(2026, 10, 1),
);

/// The date of challenge day [dayNumber] in arcs built by these helpers.
LocalDate dayN(int dayNumber) => day1.addDays(dayNumber - 1);

/// An arc as of day [today] with [habits] (target 8, minimum 3) where [done]
/// lists, per day number, the habit ids completed that day (at 8), [partial]
/// incomplete values, [modes] day modes and [xp] the ledger total per day.
ArcHistory arcOf({
  required int today,
  List<String> habits = const ['water', 'junk'],
  Map<int, List<String>> done = const {},
  Map<int, Map<String, int>> partial = const {},
  Map<int, DayMode> modes = const {},
  List<HabitRevision> revisions = const [],
  Map<int, int> xp = const {},
}) {
  final list = [
    for (final (i, id) in habits.indexed)
      habit(id, target: 8, minimum: 3, sortOrder: i),
  ];
  return ArcHistory(
    session: activeSession(),
    today: dayN(today),
    records: ArcRecords(
      habits: HabitHistory(habits: list, revisions: revisions),
      progress: <DailyHabitProgress>[
        for (final MapEntry(key: day, value: ids) in done.entries)
          for (final id in ids) progress(id, dayN(day), 8),
        for (final MapEntry(key: day, value: values) in partial.entries)
          for (final MapEntry(key: id, value: v) in values.entries)
            progress(id, dayN(day), v, completed: false),
      ],
      modes: {
        for (final MapEntry(key: day, value: mode) in modes.entries)
          dayN(day): mode,
      },
      xpByDate: {
        for (final MapEntry(key: day, value: amount) in xp.entries)
          dayN(day): amount,
      },
      totalXp: xp.values.fold(0, (a, b) => a + b),
    ),
  );
}
