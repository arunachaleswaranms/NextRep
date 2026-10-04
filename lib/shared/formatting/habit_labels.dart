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

/// "Last night" for a sleep habit (logged the next morning), otherwise
/// "Logged".
String clockRecordLabel(Habit habit) =>
    habit.iconKey == 'sleep' ? 'Last night' : 'Logged';

/// What a habit type is called in the app.
String habitTypeLabel(HabitType type) => switch (type) {
  HabitType.binary => 'Done / not done',
  HabitType.count => 'Count',
  HabitType.duration => 'Minutes',
  HabitType.timeBefore => 'Before a time',
};

/// "🔥 4 day streak".
String streakLabel(int days) => '🔥 $days day streak';
