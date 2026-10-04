import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/winter_arc/winter_arc_session.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/habit_setup/habit_setup_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/journey/journey_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/shell/active_shell.dart';
import '../../features/summary/summary_screen.dart';
import '../../features/today/today_screen.dart';
import '../arc_status.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const habitSetup = '/setup';
  static const today = '/today';
  static const habits = '/today/habits';
  static const journey = '/journey';
  static const achievements = '/achievements';
  static const summary = '/summary';
  static const summaryJourney = '/summary/journey';

  /// Where the app should open, derived from persisted session state.
  static String forSession(WinterArcSession? session) =>
      switch (session?.status) {
        null => onboarding,
        WinterArcStatus.setup => habitSetup,
        WinterArcStatus.active => today,
        WinterArcStatus.completed => summary,
      };

  /// Keeps the location consistent with the arc's lifecycle: a completed
  /// arc can't show the (writable) active-arc tabs, and the summary only
  /// exists for a completed arc. Achievements are reachable from both.
  static String? redirect(WinterArcStatus? status, String location) {
    final inActiveArc =
        location == today ||
        location.startsWith('$today/') ||
        location == journey;
    if (status == WinterArcStatus.completed && inActiveArc) return summary;
    if (status == WinterArcStatus.active && location.startsWith(summary)) {
      return today;
    }
    return null;
  }
}

/// The launch location, resolved once at startup after closing out an arc
/// that ended while the app was away.
final bootLocationProvider = FutureProvider<String>((ref) async {
  final session = await ref.read(arcStatusProvider.notifier).reconcile();
  return AppRoutes.forSession(session);
});

/// Onboarding and setup are plain routes. An active arc lives in a
/// [StatefulShellRoute] with one branch per bottom-navigation tab; a
/// completed arc lives under the summary. Full-screen flows opened from a
/// tab (habit editing, achievements) use the root navigator so they cover
/// the navigation bar. [status] drives the lifecycle redirect.
GoRouter buildAppRouter({
  required String initialLocation,
  required ValueListenable<WinterArcStatus?> status,
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: status,
    redirect: (context, state) =>
        AppRoutes.redirect(status.value, state.matchedLocation),
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
        path: AppRoutes.achievements,
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.summary,
        builder: (context, state) => const SummaryScreen(),
        routes: [
          GoRoute(
            path: 'journey',
            builder: (context, state) => const JourneyScreen(),
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
        ],
      ),
    ],
  );
}
