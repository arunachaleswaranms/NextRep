import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/winter_tokens.dart';
import '../achievements_controller.dart';

/// Opens the achievement collection, showing how much of it is unlocked:
/// the home arc's, or arc [sessionId]'s when shown from Arc History.
class TrophyButton extends ConsumerWidget {
  const TrophyButton({super.key, this.sessionId});

  final int? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.winter;
    final id = sessionId;
    final board = id == null
        ? ref.watch(achievementBoardProvider).value
        : ref.watch(arcAchievementBoardProvider(id)).value;
    final count = board == null
        ? null
        : '${board.unlockedCount}/${board.total}';
    void open() => context.push(
      id == null ? AppRoutes.achievements : AppRoutes.arcAchievements(id),
    );
    return Semantics(
      button: true,
      label: count == null
          ? 'Achievements'
          : 'Achievements, ${board!.unlockedCount} of ${board.total} unlocked',
      onTap: open,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: open,
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
