import '../../domain/habit/habit.dart';

/// "30 min", "8 glasses", or "Daily goal" for binary habits.
String targetLabel(Habit habit, int target) => habit.type.isNumeric
    ? '$target ${habit.unit ?? ''}'.trimRight()
    : 'Daily goal';

/// "15 / 30 min" for numeric habits, "Done" / "Not done" for binary ones.
String progressLabel(
  Habit habit,
  int currentValue, {
  required int target,
  required bool completed,
}) {
  if (!habit.type.isNumeric) return completed ? 'Done' : 'Not done yet';
  return '$currentValue / $target ${habit.unit ?? ''}'.trimRight();
}

/// "🔥 4 day streak".
String streakLabel(int days) => '🔥 $days day streak';
