import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/time/clock.dart';
import '../data/drift_achievement_repository.dart';
import '../data/drift_habit_repository.dart';
import '../data/drift_progress_repository.dart';
import '../data/drift_winter_arc_repository.dart';
import '../domain/achievement/achievement_repository.dart';
import '../domain/achievement/achievement_service.dart';
import '../domain/habit/habit_repository.dart';
import '../domain/progress/habit_tracking_service.dart';
import '../domain/progress/progress_repository.dart';
import '../domain/winter_arc/arc_lifecycle_service.dart';
import '../domain/winter_arc/winter_arc_repository.dart';
import '../domain/winter_arc/winter_arc_service.dart';

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

final achievementServiceProvider = Provider<AchievementService>(
  (ref) => AchievementService(
    sessions: ref.watch(winterArcRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    achievements: ref.watch(achievementRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final arcLifecycleServiceProvider = Provider<ArcLifecycleService>(
  (ref) => ArcLifecycleService(
    sessions: ref.watch(winterArcRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
