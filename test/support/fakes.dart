export 'package:nextrep/core/time/clock.dart' show ClockToday;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/clock.dart';
import 'package:nextrep/data/drift_achievement_repository.dart';
import 'package:nextrep/data/drift_habit_repository.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_reflection_repository.dart';
import 'package:nextrep/data/drift_reminder_preferences_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/domain/achievement/achievement_service.dart';
import 'package:nextrep/domain/history/arc_history_service.dart';
import 'package:nextrep/domain/progress/habit_tracking_service.dart';
import 'package:nextrep/domain/reflection/reflection_service.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_scheduler.dart';
import 'package:nextrep/domain/reminder/reminder_service.dart';
import 'package:nextrep/domain/winter_arc/arc_lifecycle_service.dart';
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

/// Records what the app asked the OS to schedule. Permission is granted
/// unless [grant] is false.
final class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.grant = true, this.granted = false});

  /// What a permission request returns.
  bool grant;

  /// Whether permission is currently granted.
  bool granted;
  int permissionRequests = 0;

  /// Currently pending reminders, as the OS would hold them.
  List<PlannedReminder> pending = const [];
  int scheduleCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    granted = grant;
    return granted;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    scheduleCalls++;
    pending = List.unmodifiable(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    pending = const [];
  }
}

/// Real services wired to real Drift repositories over [db].
final class TestApp {
  TestApp(this.db, this.clock, {FakeReminderScheduler? scheduler})
    : sessions = DriftWinterArcRepository(db),
      habits = DriftHabitRepository(db),
      progress = DriftProgressRepository(db, clock),
      achievementStore = DriftAchievementRepository(db),
      reflectionStore = DriftReflectionRepository(db),
      reminderStore = DriftReminderPreferencesRepository(db),
      scheduler = scheduler ?? FakeReminderScheduler() {
    winterArc = WinterArcService(
      sessions: sessions,
      habits: habits,
      clock: clock,
    );
    tracking = HabitTrackingService(
      sessions: sessions,
      progress: progress,
      clock: clock,
    );
    achievements = AchievementService(
      sessions: sessions,
      progress: progress,
      achievements: achievementStore,
      reflections: reflectionStore,
      clock: clock,
    );
    lifecycle = ArcLifecycleService(sessions: sessions, clock: clock);
    reflections = ReflectionService(
      sessions: sessions,
      reflections: reflectionStore,
      clock: clock,
    );
    history = ArcHistoryService(
      sessions: sessions,
      progress: progress,
      achievements: achievementStore,
      reflections: reflectionStore,
      clock: clock,
    );
    reminders = ReminderService(
      sessions: sessions,
      preferences: reminderStore,
      scheduler: this.scheduler,
      clock: clock,
    );
  }

  final AppDatabase db;
  final FakeClock clock;
  final DriftWinterArcRepository sessions;
  final DriftHabitRepository habits;
  final DriftProgressRepository progress;
  final DriftAchievementRepository achievementStore;
  final DriftReflectionRepository reflectionStore;
  final DriftReminderPreferencesRepository reminderStore;
  final FakeReminderScheduler scheduler;
  late final WinterArcService winterArc;
  late final HabitTrackingService tracking;
  late final AchievementService achievements;
  late final ArcLifecycleService lifecycle;
  late final ReflectionService reflections;
  late final ArcHistoryService history;
  late final ReminderService reminders;
}
