import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/achievement/achievement.dart';
import '../../share/share_preview_screen.dart';
import 'achievement_badge.dart';

/// An unlocked achievement up close, with the way to share it. Locked
/// achievements never open it.
class AchievementDetailSheet extends StatelessWidget {
  const AchievementDetailSheet({
    super.key,
    required this.status,
    required this.board,
  });

  final AchievementStatus status;
  final AchievementBoard board;

  static Future<void> show(
    BuildContext context,
    AchievementStatus status,
    AchievementBoard board,
  ) async {
    if (!status.unlocked) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.winter.surface,
      builder: (_) => AchievementDetailSheet(status: status, board: board),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final definition = status.definition;
    final day = board.dayNumberOf(status.unlock!.unlockedOn);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WinterSpacing.lg,
          0,
          WinterSpacing.lg,
          WinterSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: AchievementBadge(
                achievement: definition.key,
                unlocked: true,
                size: 88,
              ),
            ),
            const SizedBox(height: WinterSpacing.md),
            Text(
              definition.title,
              textAlign: TextAlign.center,
              style: text.headlineSmall,
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              definition.description,
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              'Unlocked on Day $day',
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(
                color: definition.key.accent(colors),
              ),
            ),
            const SizedBox(height: WinterSpacing.lg),
            FilledButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await SharePreviewScreen.achievement(context, status, board);
                if (navigator.mounted) navigator.pop();
              },
              icon: const Icon(Icons.ios_share_rounded),
              label: Text('Share ${definition.title}'),
            ),
          ],
        ),
      ),
    );
  }
}
