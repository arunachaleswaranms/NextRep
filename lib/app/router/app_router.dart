import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/winter_arc/winter_arc_session.dart';
import '../../features/habit_setup/habit_setup_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/journey/journey_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/shell/active_shell.dart';
import '../../features/today/today_screen.dart';
import '../dependencies.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const habitSetup = '/setup';
  static const today = '/today';
  static const habits = '/today/habits';
  static const journey = '/journey';

  /// Where the app should open, derived from persisted session state.
  static String forSession(WinterArcSession? session) =>
      switch (session?.status) {
        null => onboarding,
        WinterArcStatus.setup => habitSetup,
        WinterArcStatus.active || WinterArcStatus.completed => today,
      };
}

/// The launch location, resolved once from the database on startup.
final bootLocationProvider = FutureProvider<String>((ref) async {
  final session = await ref.watch(winterArcServiceProvider).currentSession();
  return AppRoutes.forSession(session);
});

/// Onboarding and setup are plain routes. An active arc lives in a
/// [StatefulShellRoute] with one branch per bottom-navigation tab; future tabs
/// are added as branches. Full-screen flows opened from a tab (e.g. habit
/// editing) use the root navigator so they cover the navigation bar.
GoRouter buildAppRouter({required String initialLocation}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.habitSetup,
        builder: (context, state) => const HabitSetupScreen(),
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
