import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/winter_tokens.dart';
import '../achievements_controller.dart';

/// Opens the achievement collection, showing how much of it is unlocked.
class TrophyButton extends ConsumerWidget {
  const TrophyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.winter;
    final board = ref.watch(achievementBoardProvider).value;
    final count = board == null
        ? null
        : '${board.unlockedCount}/${board.total}';
    return Semantics(
      button: true,
      label: count == null
          ? 'Achievements'
          : 'Achievements, ${board!.unlockedCount} of ${board.total} unlocked',
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: () => context.push(AppRoutes.achievements),
        style: TextButton.styleFrom(
          foregroundColor: colors.celebration,
          minimumSize: const Size(48, 48),
        ),
        icon: const Icon(Icons.emoji_events_rounded),
        label: Text(count ?? ''),
      ),
    );
  }
}
