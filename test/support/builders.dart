import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
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
