import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/reminder/reminder_plan.dart';
import '../../domain/winter_arc/current_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/backup/data_backup_screen.dart';
import '../../features/habit_setup/habit_setup_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/history/arc_history_screen.dart';
import '../../features/insights/insights_screen.dart';
import '../../features/journal/journal_screen.dart';
import '../../features/journey/journey_screen.dart';
import '../../features/new_arc/new_arc_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/reminders/reminder_settings_screen.dart';
import '../../features/shell/active_shell.dart';
import '../../features/shell/unknown_page_screen.dart';
import '../../features/summary/summary_screen.dart';
import '../../features/today/today_screen.dart';
import '../app_restart.dart';
import '../arc_status.dart';
import '../dependencies.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const habitSetup = '/setup';
  static const newArc = '/new-arc';

  // The active arc's tabs.
  static const today = '/today';
  static const habits = '/today/habits';
  static const journey = '/journey';
  static const journal = '/journal';
  static const history = '/history';

  /// The active arc's achievements.
  static const achievements = '/achievements';

  /// Arc History when no arc is running (outside the tab shell).
  static const arcs = '/arcs';
  static const reminders = '/settings/reminders';

  /// Data & Backup: export, restore. Reachable in every state, including
  /// before the first arc (to restore on a new device).
  static const dataBackup = '/settings/data';

  /// On-device insights across every started arc.
  static const insights = '/insights';

  /// A started arc by id: its summary, read-only. The home of a completed
  /// arc.
  static String arc(int sessionId) => '/arc/$sessionId';
  static String arcJourney(int sessionId) => '/arc/$sessionId/journey';
  static String arcJournal(int sessionId) => '/arc/$sessionId/journal';
  static String arcAchievements(int sessionId) =>
      '/arc/$sessionId/achievements';

  /// Where the app should open:
  ///
  /// 1. an arc in setup → Habit Setup
  /// 2. an active arc → Today
  /// 3. otherwise, after any completed arc → the latest one's summary
  /// 4. a first install → onboarding
  static String home(ArcResolution resolution) {
    if (resolution.setup != null) return habitSetup;
    if (resolution.active != null) return today;
    if (resolution.latestCompleted case final done?) return arc(done.id);
    return onboarding;
  }

  /// Where [session] opens, by its status.
  static String forSession(WinterArcSession? session) =>
      switch (session?.status) {
        null => onboarding,
        WinterArcStatus.setup => habitSetup,
        WinterArcStatus.active => today,
        WinterArcStatus.completed => arc(session!.id),
      };

  /// Where a tapped reminder leads. Reminders only ever point at the active
  /// arc; a stale one (the arc has since completed, or a new one is in
  /// setup) falls back to [home] instead of a writable screen.
  static String forReminder(String? payload, ArcResolution resolution) {
    if (resolution.active == null) return home(resolution);
    return switch (ReminderKind.fromPayload(payload)) {
      ReminderKind.reflection => journal,
      ReminderKind.daily || null => today,
    };
  }

  /// Keeps the location consistent with the arcs:
  ///
  /// * the active-arc screens (tabs, achievements) need an active arc
  /// * onboarding, setup and New Arc aren't reachable while an arc runs
  /// * the current arc is never shown as history (`/arc/:id`)
  /// * onboarding is only for a first install
  static String? redirect(ArcResolution? resolution, String location) {
    if (resolution == null) return null;
    bool under(String path) =>
        location == path || location.startsWith('$path/');

    final inActiveArc =
        under(today) ||
        under(journey) ||
        under(journal) ||
        under(history) ||
        under(achievements);
    final viewedArc = _arcIdIn(location);
    if (location.startsWith('/arc/') && viewedArc == null) {
      return home(resolution); // malformed arc id
    }

    if (resolution.active != null) {
      if (under(onboarding) || under(habitSetup) || under(newArc)) {
        return today;
      }
      if (under(arcs)) return history;
      if (viewedArc == resolution.active!.id) return today;
      return null;
    }
    if (inActiveArc) return home(resolution);
    if (viewedArc != null && viewedArc == resolution.current?.id) {
      return home(resolution);
    }
    if (resolution.setup != null && (under(onboarding) || under(newArc))) {
      return habitSetup;
    }
    if (resolution.current == null &&
        !resolution.isEmpty &&
        (under(onboarding) || under(habitSetup))) {
      return home(resolution);
    }
    return null;
  }

  static int? _arcIdIn(String location) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.length < 2 || segments.first != 'arc') return null;
    return int.tryParse(segments[1]);
  }
}

/// The launch location, resolved once at startup after closing out an arc
/// that ended while the app was away. A reminder that cold-started the app
/// leads to its own (arc-checked) destination.
final bootLocationProvider = FutureProvider<String>((ref) async {
  // A restart (after a restore) resolves the boot location again, but the
  // reminder that cold-started the app only counts for the first launch.
  final firstLaunch = ref.watch(appEpochProvider) == 0;
  final resolution = await ref.read(arcResolutionProvider.notifier).reconcile();
  final payload = firstLaunch ? ref.read(reminderLaunchPayloadProvider) : null;
  return payload == null
      ? AppRoutes.home(resolution)
      : AppRoutes.forReminder(payload, resolution);
});

/// Onboarding, setup, New Arc and the history pages are plain routes. An
/// active arc lives in a [StatefulShellRoute] with one branch per
/// bottom-navigation tab. Full-screen flows opened from a tab (habit
/// editing, achievements, an arc from History) use the root navigator so
/// they cover the navigation bar. Every history page takes the arc's id
/// from its path and reloads that arc from storage. [resolution] drives the
/// lifecycle redirect.
GoRouter buildAppRouter({
  required String initialLocation,
  required ValueListenable<ArcResolution?> resolution,
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  int sessionIdOf(GoRouterState state) =>
      int.parse(state.pathParameters['sessionId']!);
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: resolution,
    redirect: (context, state) =>
        AppRoutes.redirect(resolution.value, state.uri.path),
    // An unknown location (never a link the app builds itself) gets a
    // calm page with a way home, never go_router's exception text.
    errorBuilder: (context, state) => const UnknownPageScreen(),
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.habitSetup,
        builder: (context, state) => const HabitSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.newArc,
        builder: (context, state) => const NewArcScreen(),
      ),
      GoRoute(
        path: AppRoutes.achievements,
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.arcs,
        builder: (context, state) => const ArcHistoryScreen(standalone: true),
      ),
      GoRoute(
        path: AppRoutes.reminders,
        builder: (context, state) => const ReminderSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.dataBackup,
        builder: (context, state) => const DataBackupScreen(),
      ),
      GoRoute(
        path: AppRoutes.insights,
        builder: (context, state) => const InsightsScreen(),
      ),
      GoRoute(
        path: '/arc/:sessionId',
        builder: (context, state) =>
            SummaryScreen(sessionId: sessionIdOf(state)),
        routes: [
          GoRoute(
            path: 'journey',
            builder: (context, state) =>
                JourneyScreen(sessionId: sessionIdOf(state)),
          ),
          GoRoute(
            path: 'journal',
            builder: (context, state) =>
                JournalScreen(sessionId: sessionIdOf(state)),
          ),
          GoRoute(
            path: 'achievements',
            builder: (context, state) =>
                AchievementsScreen(sessionId: sessionIdOf(state)),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ActiveShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.today,
                builder: (context, state) => const TodayScreen(),
                routes: [
                  GoRoute(
                    path: 'habits',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => const HabitsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.journey,
                builder: (context, state) => const JourneyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.journal,
                builder: (context, state) => const JournalScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, state) => const ArcHistoryScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
