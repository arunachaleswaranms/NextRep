import 'package:drift/drift.dart';

import '../../domain/habit/habit.dart';
import '../../domain/progress/day_mode.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../domain/xp/xp.dart';
import 'converters.dart';

// Enum columns are stored by name (textEnum), so enum values must never be
// renamed without a migration.

/// Winter Arc sessions. Any number may be completed, but the partial unique
/// index (schema v4) allows at most one unfinished (setup or active)
/// session, so two arcs can never run side by side.
@DataClassName('SessionRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX single_open_session ON winter_arc_sessions '
  "((status IN ('setup', 'active'))) WHERE status IN ('setup', 'active')",
)
class WinterArcSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get startDate => text().map(const LocalDateConverter())();
  TextColumn get endDate => text().map(const LocalDateConverter())();
  TextColumn get status => textEnum<WinterArcStatus>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
}

/// A session's habits. [target], [minimumTarget] and [enabled] hold the
/// baseline configuration chosen in setup (effective from Day 1). Changes
/// after the arc starts go to [HabitRevisions] and never rewrite these.
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

  /// Baseline Minimum Day target. Added in schema v2 (so it is the last
  /// column, as `ALTER TABLE ADD COLUMN` appends). The default only exists so
  /// the column can be added to existing rows; the v1 → v2 migration
  /// backfills real values.
  IntColumn get minimumTarget => integer()
      .withDefault(const Constant(1))
      // ignore: recursive_getters
      .check(minimumTarget.isBetween(const Constant(1), target))();

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

/// A habit configuration change effective from [effectiveFrom] until the
/// next revision of the same habit (schema v2). Never written for a past
/// date (Phase 3 writes them for the next challenge day), so past days keep
/// their configuration.
@DataClassName('HabitRevisionRow')
class HabitRevisions extends Table {
  IntColumn get sessionId => integer()();
  TextColumn get habitId => text()();
  TextColumn get effectiveFrom => text().map(const LocalDateConverter())();
  // ignore: recursive_getters
  IntColumn get target => integer().check(target.isBiggerThanValue(0))();
  IntColumn get minimumTarget =>
      // ignore: recursive_getters
      integer().check(minimumTarget.isBetween(const Constant(1), target))();
  BoolColumn get enabled => boolean()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, habitId, effectiveFrom};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (session_id, habit_id) REFERENCES habits (session_id, id) '
        'ON DELETE CASCADE',
  ];
}

/// The mode of a challenge date (schema v2). Dates without a row are
/// [DayMode.normal].
@DataClassName('DayModeRow')
class DayModes extends Table {
  IntColumn get sessionId => integer().references(
    WinterArcSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get date => text().map(const LocalDateConverter())();
  TextColumn get mode => textEnum<DayMode>()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, date};
}

/// An achievement unlocked in a session (schema v3). Written once per
/// session and key, never updated. The catalog itself lives in code
/// (`AchievementCatalog`); only the unlock is stored.
@DataClassName('AchievementUnlockRow')
class AchievementUnlocks extends Table {
  IntColumn get sessionId => integer().references(
    WinterArcSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Stable `AchievementKey.id`, e.g. `first_rep`.
  TextColumn get achievementKey => text()();

  /// The challenge date on which it was earned.
  TextColumn get unlockedOn => text().map(const LocalDateConverter())();

  /// When the unlock was first persisted.
  DateTimeColumn get unlockedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, achievementKey};
}

/// A nightly reflection (schema v4): one per session and challenge date.
/// The challenge day number isn't stored; it follows from the session's
/// start date. Private, local-only text.
@DataClassName('ReflectionRow')
class DailyReflections extends Table {
  IntColumn get sessionId => integer().references(
    WinterArcSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get date => text().map(const LocalDateConverter())();

  /// Stable `Mood.key`, or null when only text was given.
  TextColumn get mood => text().nullable()();
  TextColumn get win => text().nullable()();
  TextColumn get improvement => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sessionId, date};
}

/// The app's reminder preferences (schema v4): a single row with id 1,
/// absent until the user first changes a reminder. They belong to the app,
/// not to an arc. Both reminders are off unless stored as on.
@DataClassName('ReminderPreferencesRow')
class ReminderPrefs extends Table {
  @override
  String get tableName => 'reminder_preferences';

  // ignore: recursive_getters
  IntColumn get id => integer().check(id.equals(1))();
  BoolColumn get dailyEnabled => boolean()();
  IntColumn get dailyHour =>
      // ignore: recursive_getters
      integer().check(dailyHour.isBetweenValues(0, 23))();
  IntColumn get dailyMinute =>
      // ignore: recursive_getters
      integer().check(dailyMinute.isBetweenValues(0, 59))();
  BoolColumn get reflectionEnabled => boolean()();
  IntColumn get reflectionHour =>
      // ignore: recursive_getters
      integer().check(reflectionHour.isBetweenValues(0, 23))();
  IntColumn get reflectionMinute =>
      // ignore: recursive_getters
      integer().check(reflectionMinute.isBetweenValues(0, 59))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
