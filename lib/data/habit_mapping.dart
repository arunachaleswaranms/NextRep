import 'package:drift/drift.dart';

import '../core/database/app_database.dart';
import '../domain/habit/habit.dart';

HabitsCompanion habitToCompanion(int sessionId, Habit habit) =>
    HabitsCompanion.insert(
      sessionId: sessionId,
      id: habit.id,
      title: habit.title,
      type: habit.type,
      target: habit.target,
      minimumTarget: Value(habit.minimumTarget),
      unit: Value(habit.unit),
      iconKey: habit.iconKey,
      enabled: habit.enabled,
      sortOrder: habit.sortOrder,
      createdAt: habit.createdAt,
    );

Habit habitFromRow(HabitRow row) => Habit(
  id: row.id,
  title: row.title,
  type: row.type,
  target: row.target,
  minimumTarget: row.minimumTarget,
  unit: row.unit,
  iconKey: row.iconKey,
  enabled: row.enabled,
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
);
