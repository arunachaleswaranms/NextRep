import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation for an active Winter Arc. Each tab keeps its own
/// navigation stack and state while another tab is shown.
class ActiveShell extends StatelessWidget {
  const ActiveShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(BuildContext context, int index) {
    // Feedback such as "+15 XP · Undo" belongs to the tab that showed it.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    navigationShell.goBranch(
      index,
      // Tapping the current tab again returns it to its first page.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => _select(context, index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today_rounded),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.terrain_outlined),
          selectedIcon: Icon(Icons.terrain_rounded),
          label: 'Journey',
        ),
        NavigationDestination(
          icon: Icon(Icons.edit_note_outlined),
          selectedIcon: Icon(Icons.edit_note_rounded),
          label: 'Journal',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history_rounded),
          label: 'History',
        ),
      ],
    ),
  );
}
