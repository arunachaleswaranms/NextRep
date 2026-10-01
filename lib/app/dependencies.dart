import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/time/clock.dart';
import '../data/drift_habit_repository.dart';
import '../data/drift_progress_repository.dart';
import '../data/drift_winter_arc_repository.dart';
import '../domain/habit/habit_repository.dart';
import '../domain/progress/habit_tracking_service.dart';
import '../domain/progress/progress_repository.dart';
import '../domain/winter_arc/winter_arc_repository.dart';
import '../domain/winter_arc/winter_arc_service.dart';

// Composition root. Infrastructure is overridden in main() and in tests;
// features depend on the service providers only.

/// Must be overridden with an opened database (see `main.dart`).
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

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
    habits: ref.watch(habitRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
