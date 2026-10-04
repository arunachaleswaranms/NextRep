import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/habit/starter_habits.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/day_record.dart';

void main() {
  final date = LocalDate(2026, 10, 1);
  final habits = StarterHabits.seed(DateTime(2026, 10, 1)).take(3).toList();

  List<HabitDayEntry> entries({required int completed}) => [
    for (final (i, habit) in habits.indexed)
      HabitDayEntry(
        habit: habit,
        config: habit.baseline,
        target: habit.target,
        progress: DailyHabitProgress(
          habitId: habit.id,
          date: date,
          currentValue: i < completed ? habit.target : 0,
          completed: i < completed,
        ),
      ),
  ];

  test('percentage is completed / tracked, rounded down', () {
    expect(DayCompletion.of(entries(completed: 0)).percent, 0);
    expect(DayCompletion.of(entries(completed: 1)).percent, 33);
    expect(DayCompletion.of(entries(completed: 2)).percent, 66);
    expect(DayCompletion.of(entries(completed: 3)).percent, 100);
  });

  test('100% only when every habit is done', () {
    expect(DayCompletion.of(entries(completed: 2)).isFull, isFalse);
    expect(DayCompletion.of(entries(completed: 3)).isFull, isTrue);
  });

  test('partial numeric progress does not count as completion', () {
    final partial = [
      HabitDayEntry(
        habit: habits.first,
        config: habits.first.baseline,
        target: habits.first.target,
        progress: DailyHabitProgress(
          habitId: habits.first.id,
          date: date,
          currentValue: habits.first.target - 1,
          completed: false,
        ),
      ),
    ];
    expect(DayCompletion.of(partial).percent, 0);
  });

  test('no tracked habits is 0%, not a division error', () {
    final none = DayCompletion.of(const []);
    expect(none.percent, 0);
    expect(none.ratio, 0);
    expect(none.isFull, isFalse);
  });

  test('starter catalogue has unique ids and valid targets', () {
    final ids = StarterHabits.all.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(StarterHabits.all.every((t) => t.target > 0), isTrue);
    expect(
      StarterHabits.all.every(
        (t) => t.minimumTarget > 0 && t.minimumTarget <= t.target,
      ),
      isTrue,
    );
  });
}
