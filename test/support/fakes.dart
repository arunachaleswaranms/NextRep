export 'package:nextrep/core/time/clock.dart' show ClockToday;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/clock.dart';
import 'package:nextrep/data/drift_habit_repository.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/domain/progress/habit_tracking_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';

/// A clock tests can set and advance.
final class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  set current(DateTime value) => _now = value;

  void advance(Duration duration) => _now = _now.add(duration);
}

/// In-memory database, isolated per test.
AppDatabase memoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Real services wired to real Drift repositories over [db].
final class TestApp {
  TestApp(this.db, this.clock)
    : sessions = DriftWinterArcRepository(db),
      habits = DriftHabitRepository(db),
      progress = DriftProgressRepository(db, clock) {
    winterArc = WinterArcService(
      sessions: sessions,
      habits: habits,
      clock: clock,
    );
    tracking = HabitTrackingService(
      sessions: sessions,
      habits: habits,
      progress: progress,
      clock: clock,
    );
  }

  final AppDatabase db;
  final FakeClock clock;
  final DriftWinterArcRepository sessions;
  final DriftHabitRepository habits;
  final DriftProgressRepository progress;
  late final WinterArcService winterArc;
  late final HabitTrackingService tracking;
}
