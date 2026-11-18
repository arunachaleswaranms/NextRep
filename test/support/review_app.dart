import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/progress/progress_repository.dart';

import 'fakes.dart';
import 'updates.dart';

/// The whole app (real router, real Drift repositories over [db]) opened
/// at [route], with platform services faked as in the Phase 11E layout
/// sweep: no notification, Focus Guard or network access. All synthetic.
Widget reviewApp(
  AppDatabase db,
  FakeClock clock,
  String route, {
  ProgressRepository? progress,
}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    ambientMotionProvider.overrideWithValue(false),
    reminderSchedulerProvider.overrideWithValue(
      FakeReminderScheduler(granted: false),
    ),
    focusGuardPlatformProvider.overrideWithValue(
      FakeFocusGuardPlatform(access: UsageAccess.notGranted)..nudges = false,
    ),
    focusGuardSchedulerProvider.overrideWithValue(
      FakeFocusGuardBackgroundScheduler(),
    ),
    releaseFeedProvider.overrideWithValue(
      GitHubReleaseFeed(client: FakeGitHubClient.new),
    ),
    installedAppSourceProvider.overrideWithValue(FakeInstalledAppSource()),
    externalLinksProvider.overrideWithValue(FakeExternalLinks()),
    bootLocationProvider.overrideWith((ref) async => route),
    if (progress != null)
      progressRepositoryProvider.overrideWithValue(progress),
  ],
  retry: (_, _) => null,
  child: const NextRepApp(),
);
