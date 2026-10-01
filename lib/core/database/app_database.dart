import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../domain/xp/xp.dart';
import '../time/local_date.dart';
import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The app's single local SQLite database.
///
/// Schema changes must bump [schemaVersion], add a step to [migration], and
/// add a schema snapshot (see docs/PHASE_1.md, "Schema evolution").
@DriftDatabase(
  tables: [
    WinterArcSessions,
    Habits,
    DailyHabitProgressEntries,
    XpTransactions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database file.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'nextrep'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
