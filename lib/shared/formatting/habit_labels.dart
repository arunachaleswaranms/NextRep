import '../../domain/habit/habit.dart';

/// "30 min", "8 glasses", "Before 23:30", or "Daily goal" for binary
/// habits.
String targetLabel(Habit habit, int target) => switch (habit.type) {
  HabitType.count ||
  HabitType.duration => '$target ${habit.unit ?? ''}'.trimRight(),
  HabitType.timeBefore => 'Before ${clockLabel(target)}',
  HabitType.binary => 'Daily goal',
};

/// "15 / 30 min" for numeric habits, "Done" / "Not done" for binary ones,
/// "00:45 · goal before 01:00" for a logged clock-time habit.
String progressLabel(
  Habit habit,
  int currentValue, {
  required int target,
  required bool completed,
}) => switch (habit.type) {
  HabitType.binary => completed ? 'Done' : 'Not done yet',
  HabitType.count || HabitType.duration =>
    '$currentValue / $target ${habit.unit ?? ''}'.trimRight(),
  HabitType.timeBefore =>
    currentValue == 0
        ? 'Not logged · goal before ${clockLabel(target)}'
        : '${clockLabel(currentValue)} · goal before ${clockLabel(target)}',
};

/// A normalized night-time value as "HH:MM" (24-hour), or "--:--" for a
/// value that isn't one.
String clockLabel(int value) => NightTime.tryValue(value)?.hhmm ?? '--:--';

/// Whether [habit] is the built-in Sleep Before Target: a morning check-in
/// of the bedtime of the sleep that ended that morning, which belongs to
/// the day the user wakes up. Decided by the stable id, so a renamed one
/// keeps this copy and a custom clock-time habit (even one with the sleep
/// icon) never gets it.
bool isBedtimeCheckIn(Habit habit) =>
    habit.id == 'sleep_before' && habit.type == HabitType.timeBefore;

/// "Last night's bedtime" for Sleep Before Target, otherwise "Logged".
String clockRecordLabel(Habit habit) =>
    isBedtimeCheckIn(habit) ? "Last night's bedtime" : 'Logged';

/// What a habit type is called in the app.
String habitTypeLabel(HabitType type) => switch (type) {
  HabitType.binary => 'Done / not done',
  HabitType.count => 'Count',
  HabitType.duration => 'Minutes',
  HabitType.timeBefore => 'Before a time',
};

/// "🔥 4 day streak".
String streakLabel(int days) => '🔥 $days day streak';
