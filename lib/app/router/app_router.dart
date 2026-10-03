import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/winter_arc/winter_arc_session.dart';
import '../../features/habit_setup/habit_setup_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/today/today_screen.dart';
import '../dependencies.dart';

abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const habitSetup = '/setup';
  static const today = '/today';

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

// Future tabs (Journey, Progress, Journal, Profile) slot in as a
// StatefulShellRoute around [AppRoutes.today] when they exist.
GoRouter buildAppRouter({required String initialLocation}) => GoRouter(
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
    GoRoute(
      path: AppRoutes.today,
      builder: (context, state) => const TodayScreen(),
    ),
  ],
);
