import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
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

// Composition root. Infrastructure is overridden in main() and in tests;
// features depend on the service providers only.

/// Must be overridden with an opened database (see `main.dart`).
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Whether looping ambient scene motion (snow, aurora) may run at all. The
/// platform reduced-motion setting turns it off independently. Widget tests
/// override it with false so `pumpAndSettle` can settle.
final ambientMotionProvider = Provider<bool>((ref) => true);

final winterArcRepositoryProvider = Provider<WinterArcRepository>(
  (ref) => DriftWinterArcRepository(ref.watch(appDatabaseProvider)),
);

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => DriftHabitRepository(ref.watch(appDatabaseProvider)),
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => DriftProgressRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  ),
);

final winterArcServiceProvider = Provider<WinterArcService>(
  (ref) => WinterArcService(
    sessions: ref.watch(winterArcRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    clock: ref.watch(clockProvider),
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
  (ref) => DriftAchievementRepository(ref.watch(appDatabaseProvider)),
);

final reflectionRepositoryProvider = Provider<ReflectionRepository>(
  (ref) => DriftReflectionRepository(ref.watch(appDatabaseProvider)),
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
      (ref) =>
          DriftReminderPreferencesRepository(ref.watch(appDatabaseProvider)),
    );

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    sessions: ref.watch(winterArcRepositoryProvider),
    preferences: ref.watch(reminderPreferencesRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
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
  (ref) => DriftBackupStore(ref.watch(appDatabaseProvider)),
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
