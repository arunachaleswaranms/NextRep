import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../core/time/clock.dart';
import '../data/backup_files.dart';
import '../data/drift_achievement_repository.dart';
import '../data/drift_arc_activity_repository.dart';
import '../data/drift_backup_store.dart';
import '../data/drift_feedback_preferences_repository.dart';
import '../data/drift_focus_guard_settings_repository.dart';
import '../data/drift_habit_repository.dart';
import '../data/drift_progress_repository.dart';
import '../data/drift_reflection_repository.dart';
import '../data/drift_reminder_preferences_repository.dart';
import '../data/drift_winter_arc_repository.dart';
import '../data/external_links.dart';
import '../data/platform_app_info.dart';
import '../data/share_gateway.dart';
import '../domain/achievement/achievement_repository.dart';
import '../domain/achievement/achievement_service.dart';
import '../domain/backup/backup_service.dart';
import '../domain/backup/backup_store.dart';
import '../domain/feedback/completion_feedback.dart';
import '../domain/feedback/completion_sound.dart';
import '../domain/feedback/feedback_preferences.dart';
import '../domain/focus_guard/focus_guard_background.dart';
import '../domain/focus_guard/focus_guard_platform.dart';
import '../domain/focus_guard/focus_guard_service.dart';
import '../domain/focus_guard/focus_guard_settings.dart';
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
import '../domain/update/installed_app.dart';
import '../domain/update/release_feed.dart';
import '../domain/winter_arc/arc_clock_guard.dart';
import '../domain/winter_arc/arc_lifecycle_service.dart';
import '../domain/winter_arc/arc_pause_service.dart';
import '../domain/winter_arc/arc_restart_service.dart';
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
    progress: ref.watch(progressRepositoryProvider),
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

/// The latest activity date of an arc, for the clock guard (addendum
/// AD19).
final arcActivityRepositoryProvider = Provider<ArcActivityRepository>(
  (ref) => DriftArcActivityRepository(_database(ref)),
);

/// Freeze, Cancel pause and Resume (Phase 12E2).
final arcPauseServiceProvider = Provider<ArcPauseService>(
  (ref) => ArcPauseService(
    sessions: ref.watch(winterArcRepositoryProvider),
    activity: ref.watch(arcActivityRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Restart (Phase 12F).
final arcRestartServiceProvider = Provider<ArcRestartService>(
  (ref) => ArcRestartService(
    sessions: ref.watch(winterArcRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    activity: ref.watch(arcActivityRepositoryProvider),
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
    focusGuard: ref.watch(focusGuardSchedulerProvider),
    clock: ref.watch(clockProvider),
    appVersion: appVersion,
  ),
);

/// Android's app-usage facilities. `main.dart` overrides it on Android;
/// elsewhere (iOS, tests) Focus Guard is unsupported and omitted.
final focusGuardPlatformProvider = Provider<FocusGuardPlatform>(
  (ref) => const UnsupportedFocusGuardPlatform(),
);

/// Focus Guard's periodic background check. `main.dart` overrides it on
/// Android; elsewhere nothing is ever scheduled.
final focusGuardSchedulerProvider = Provider<FocusGuardBackgroundScheduler>(
  (ref) => const DisabledFocusGuardBackgroundScheduler(),
);

final focusGuardSettingsRepositoryProvider =
    Provider<FocusGuardSettingsRepository>(
      (ref) => DriftFocusGuardSettingsRepository(_database(ref)),
    );

final focusGuardServiceProvider = Provider<FocusGuardService>(
  (ref) => FocusGuardService(
    settings: ref.watch(focusGuardSettingsRepositoryProvider),
    platform: ref.watch(focusGuardPlatformProvider),
    background: ref.watch(focusGuardSchedulerProvider),
    notifications: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The system file UI for saving and choosing backups. Tests override it
/// with an in-memory fake; nothing here touches the network.
final backupFilesProvider = Provider<BackupFiles>(
  (ref) => const SystemBackupFiles(),
);

/// The system share sheet for share cards. Tests override it with a fake;
/// sharing never touches the network or the database.
final shareGatewayProvider = Provider<ShareGateway>(
  (ref) => const SystemShareGateway(),
);

/// The installed app's version and build, from the platform. Tests
/// override it with fixed values.
final installedAppSourceProvider = Provider<InstalledAppSource>(
  (ref) => const PlatformInstalledAppSource(),
);

/// GitHub's latest-release metadata, for the manual update check. Null
/// where update checks aren't offered: `main.dart` provides it on Android
/// only (releases are Android APKs), so on iOS, and in tests unless they
/// supply one, nothing can reach the network.
///
/// Read only by the About screen's "Check for updates" action: never at
/// startup, on resume, on a schedule or in the background.
final releaseFeedProvider = Provider<ReleaseFeed?>((ref) => null);

/// The device's browser, for official NextRep pages. Tests override it
/// with a fake.
final externalLinksProvider = Provider<ExternalLinks>(
  (ref) => const SystemExternalLinks(),
);

/// The app-level Sound & Feedback settings (`feedback_preferences`).
final feedbackPreferencesRepositoryProvider =
    Provider<FeedbackPreferencesRepository>(
      (ref) => DriftFeedbackPreferencesRepository(_database(ref)),
    );

/// The native completion-sound player. `main.dart` overrides it on Android
/// and iOS; elsewhere, and in tests unless they supply a fake, nothing
/// plays.
final soundPlayerProvider = Provider<SoundPlayer>(
  (ref) => const SilentSoundPlayer(),
);

/// The throttle's clock: monotonic, never the wall clock. Tests override
/// it.
final monotonicClockProvider = Provider<MonotonicClock>(
  (ref) => processElapsed,
);

/// Completion sounds (Phase 12G). One per app process: it deliberately
/// doesn't follow the app epoch, so a restore can't reset the throttle or
/// replay a Perfect Day sound. It reads the setting from storage on every
/// request, so a restored or changed setting applies at once.
final completionFeedbackProvider = Provider<CompletionFeedback>(
  (ref) => CompletionFeedback(
    preferences: DriftFeedbackPreferencesRepository(
      ref.watch(appDatabaseProvider),
    ),
    player: ref.watch(soundPlayerProvider),
    elapsed: ref.watch(monotonicClockProvider),
  ),
);
