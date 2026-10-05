import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../core/time/clock.dart';
import '../data/backup_files.dart';
import '../data/drift_achievement_repository.dart';
import '../data/drift_backup_store.dart';
import '../data/drift_habit_repository.dart';
import '../data/drift_progress_repository.dart';
import '../data/drift_reflection_repository.dart';
import '../data/drift_reminder_preferences_repository.dart';
import '../data/drift_winter_arc_repository.dart';
import '../domain/achievement/achievement_repository.dart';
import '../domain/achievement/achievement_service.dart';
import '../domain/backup/backup_service.dart';
import '../domain/backup/backup_store.dart';
import '../domain/habit/habit_repository.dart';
import '../domain/habit/setup_habit_rules.dart';
import '../domain/history/arc_history_service.dart';
import '../domain/insights/insight_service.dart';
import '../domain/progress/habit_tracking_service.dart';
import '../domain/progress/progress_repository.dart';
import '../domain/reflection/reflection_repository.dart';
import '../domain/reflection/reflection_service.dart';
import '../domain/reminder/reminder_preferences.dart';
import '../domain/reminder/reminder_scheduler.dart';
import '../domain/reminder/reminder_service.dart';
import '../domain/winter_arc/arc_lifecycle_service.dart';
import '../domain/winter_arc/winter_arc_repository.dart';
import '../domain/winter_arc/winter_arc_service.dart';
import 'app_info.dart';
import 'app_restart.dart';

// Composition root. Infrastructure is overridden in main() and in tests;
// features depend on the service providers only.

/// Must be overridden with an opened database (see `main.dart`).
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The database, for repository providers. Watching the app epoch here
/// means a restart (after a restore replaced all data) rebuilds every
/// repository, every service and every controller that watches one, so no
/// state read before the restore survives it, even in a screen's
/// controller that wasn't disposed yet.
AppDatabase _database(Ref ref) {
  ref.watch(appEpochProvider);
  return ref.watch(appDatabaseProvider);
}

/// Whether looping ambient scene motion (snow, aurora) may run at all. The
/// platform reduced-motion setting turns it off independently. Widget tests
/// override it with false so `pumpAndSettle` can settle.
final ambientMotionProvider = Provider<bool>((ref) => true);

final winterArcRepositoryProvider = Provider<WinterArcRepository>(
  (ref) => DriftWinterArcRepository(_database(ref)),
);

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => DriftHabitRepository(_database(ref)),
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => DriftProgressRepository(_database(ref), ref.watch(clockProvider)),
);

/// Ids of habits the user creates. Tests can override it with a
/// predictable generator.
final habitIdGeneratorProvider = Provider<HabitIdGenerator>(
  (ref) => SecureHabitIdGenerator(),
);

final winterArcServiceProvider = Provider<WinterArcService>(
  (ref) => WinterArcService(
    sessions: ref.watch(winterArcRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(habitIdGeneratorProvider),
  ),
);

final habitTrackingServiceProvider = Provider<HabitTrackingService>(
  (ref) => HabitTrackingService(
    sessions: ref.watch(winterArcRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final achievementRepositoryProvider = Provider<AchievementRepository>(
  (ref) => DriftAchievementRepository(_database(ref)),
);

final reflectionRepositoryProvider = Provider<ReflectionRepository>(
  (ref) => DriftReflectionRepository(_database(ref)),
);

final achievementServiceProvider = Provider<AchievementService>(
  (ref) => AchievementService(
    sessions: ref.watch(winterArcRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    achievements: ref.watch(achievementRepositoryProvider),
    reflections: ref.watch(reflectionRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => ReflectionService(
    sessions: ref.watch(winterArcRepositoryProvider),
    reflections: ref.watch(reflectionRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final arcHistoryServiceProvider = Provider<ArcHistoryService>(
  (ref) => ArcHistoryService(
    sessions: ref.watch(winterArcRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    achievements: ref.watch(achievementRepositoryProvider),
    reflections: ref.watch(reflectionRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The OS notification bridge. `main.dart` overrides it with the
/// plugin-backed scheduler; elsewhere (tests) nothing is ever scheduled.
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => const DisabledReminderScheduler(),
);

/// Payload of the reminder that cold-started the app, if any (set in
/// `main.dart`).
final reminderLaunchPayloadProvider = Provider<String?>((ref) => null);

/// Payloads of reminders tapped while the app is running (set in
/// `main.dart`).
final reminderTapsProvider = Provider<Stream<String?>>(
  (ref) => const Stream.empty(),
);

final reminderPreferencesRepositoryProvider =
    Provider<ReminderPreferencesRepository>(
      (ref) => DriftReminderPreferencesRepository(_database(ref)),
    );

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    sessions: ref.watch(winterArcRepositoryProvider),
    preferences: ref.watch(reminderPreferencesRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
    onScheduleError: (error, stackTrace) => ErrorReporter.report(
      toAppFailure(error, stackTrace),
      context: 'reminders',
    ),
  ),
);

final arcLifecycleServiceProvider = Provider<ArcLifecycleService>(
  (ref) => ArcLifecycleService(
    sessions: ref.watch(winterArcRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final insightServiceProvider = Provider<InsightService>(
  (ref) => InsightService(
    sessions: ref.watch(winterArcRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    reflections: ref.watch(reflectionRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final backupStoreProvider = Provider<BackupStore>(
  (ref) => DriftBackupStore(_database(ref)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    store: ref.watch(backupStoreProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
    appVersion: appVersion,
  ),
);

/// The system file UI for saving and choosing backups. Tests override it
/// with an in-memory fake; nothing here touches the network.
final backupFilesProvider = Provider<BackupFiles>(
  (ref) => const SystemBackupFiles(),
);
