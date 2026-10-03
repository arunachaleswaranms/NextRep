import 'package:drift/drift.dart';

import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../domain/xp/xp.dart';
import 'converters.dart';

// Enum columns are stored by name (textEnum), so enum values must never be
// renamed without a migration.

@DataClassName('SessionRow')
class WinterArcSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get startDate => text().map(const LocalDateConverter())();
  TextColumn get endDate => text().map(const LocalDateConverter())();
  TextColumn get status => textEnum<WinterArcStatus>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
}

@DataClassName('HabitRow')
class Habits extends Table {
  IntColumn get sessionId => integer().references(
    WinterArcSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get type => textEnum<HabitType>()();
  // Drift's DSL references the column inside its own definition.
  // ignore: recursive_getters
  IntColumn get target => integer().check(target.isBiggerThanValue(0))();
  TextColumn get unit => text().nullable()();
  TextColumn get iconKey => text()();
  BoolColumn get enabled => boolean()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, id};
}

@DataClassName('HabitProgressRow')
class DailyHabitProgressEntries extends Table {
  IntColumn get sessionId => integer()();
  TextColumn get habitId => text()();
  TextColumn get date => text().map(const LocalDateConverter())();
  IntColumn get currentValue =>
      // ignore: recursive_getters
      integer().check(currentValue.isBiggerOrEqualValue(0))();
  BoolColumn get completed => boolean()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, habitId, date};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (session_id, habit_id) REFERENCES habits (session_id, id) '
        'ON DELETE CASCADE',
  ];
}

@DataClassName('XpTransactionRow')
class XpTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(
    WinterArcSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Idempotency key, see `XpRules.habitCompletionKey`.
  TextColumn get sourceKey => text()();
  TextColumn get reason => textEnum<XpReason>()();
  IntColumn get amount => integer()();
  TextColumn get habitId => text().nullable()();
  TextColumn get date => text().map(const LocalDateConverter())();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, sourceKey},
  ];
}
