export 'package:nextrep/core/time/clock.dart' show ClockToday;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/clock.dart';
import 'package:nextrep/data/backup_files.dart';
import 'package:nextrep/data/drift_achievement_repository.dart';
import 'package:nextrep/data/drift_backup_store.dart';
import 'package:nextrep/data/drift_habit_repository.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/data/drift_reflection_repository.dart';
import 'package:nextrep/data/drift_reminder_preferences_repository.dart';
import 'package:nextrep/data/drift_winter_arc_repository.dart';
import 'package:nextrep/domain/achievement/achievement_service.dart';
import 'package:nextrep/domain/backup/backup_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_background.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/history/arc_history_service.dart';
import 'package:nextrep/domain/insights/insight_service.dart';
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

  /// Makes the permission check, or scheduling, throw (a failing plugin).
  bool failPermissionCheck = false;
  bool failSchedule = false;

  @override
  Future<bool> permissionGranted() async {
    if (failPermissionCheck) throw StateError('permission check failed');
    return granted;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    granted = grant;
    return granted;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    if (failSchedule) throw StateError('scheduling failed');
    scheduleCalls++;
    pending = List.unmodifiable(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    pending = const [];
  }
}

/// Usage Access and app usage as a test sets them. Access can change
/// between calls, as when the user revokes it in system settings.
final class FakeFocusGuardPlatform implements FocusGuardPlatform {
  FakeFocusGuardPlatform({
    this.access = UsageAccess.notGranted,
    this.apps = const [],
    this.usage = const {},
  });

  UsageAccess access;
  List<LaunchableAppCandidate> apps;

  /// Whether a nudge could appear (notifications on, channel not blocked).
  bool nudges = true;

  /// What a usage query returns, before the fake limits it to the
  /// requested packages.
  Map<String, Duration> usage;

  /// Called during a usage query, after it was asked for (e.g. to revoke
  /// access mid-query).
  void Function()? duringQuery;
  bool failAccessCheck = false;
  bool failQuery = false;
  int settingsOpened = 0;
  int accessChecks = 0;
  final queries = <({Set<String> packages, DateTime from, DateTime to})>[];

  @override
  Future<UsageAccess> usageAccess() async {
    accessChecks++;
    if (failAccessCheck) throw StateError('access check failed');
    return access;
  }

  @override
  Future<void> openUsageAccessSettings() async => settingsOpened++;

  @override
  Future<bool> nudgesAllowed() async => nudges;

  @override
  Future<List<LaunchableAppCandidate>> launchableApps() async => apps;

  @override
  Future<Map<String, Duration>> foregroundTime(
    Set<String> packages, {
    required DateTime from,
    required DateTime to,
  }) async {
    queries.add((packages: packages, from: from, to: to));
    duringQuery?.call();
    if (failQuery) throw StateError('usage query failed');
    // Android answers without access with no data, not an error.
    if (access != UsageAccess.granted) return const {};
    return {
      for (final MapEntry(:key, :value) in usage.entries)
        if (packages.contains(key)) key: value,
    };
  }
}

/// Records whether the periodic Focus Guard check is scheduled.
final class FakeFocusGuardBackgroundScheduler
    implements FocusGuardBackgroundScheduler {
  bool scheduled = false;
  int scheduleCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> ensureScheduled() async {
    scheduleCalls++;
    scheduled = true;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    scheduled = false;
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
      backupStore = DriftBackupStore(db),
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
      progress: progress,
      preferences: reminderStore,
      scheduler: this.scheduler,
      clock: clock,
    );
    backup = BackupService(
      store: backupStore,
      scheduler: this.scheduler,
      clock: clock,
      appVersion: '1.0.0',
    );
    insights = InsightService(
      sessions: sessions,
      progress: progress,
      reflections: reflectionStore,
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
  final DriftBackupStore backupStore;
  final FakeReminderScheduler scheduler;
  late final WinterArcService winterArc;
  late final HabitTrackingService tracking;
  late final AchievementService achievements;
  late final ArcLifecycleService lifecycle;
  late final ReflectionService reflections;
  late final ArcHistoryService history;
  late final ReminderService reminders;
  late final BackupService backup;
  late final InsightService insights;
}

/// [BackupFiles] in memory: "saving" keeps the file, "picking" returns
/// [toPick] (null: the user cancelled).
final class FakeBackupFiles implements BackupFiles {
  FakeBackupFiles({this.toPick, this.saveAccepted = true});

  Uint8List? toPick;
  bool saveAccepted;
  final saved = <(String, Uint8List)>[];
  int picks = 0;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (!saveAccepted) return false;
    saved.add((fileName, bytes));
    return true;
  }

  @override
  Future<Uint8List?> pick() async {
    picks++;
    return toPick;
  }
}
