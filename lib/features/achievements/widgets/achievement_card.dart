import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/achievement/achievement.dart';
import '../../../shared/widgets/winter_card.dart';
import 'achievement_badge.dart';

/// One achievement in the collection: badge, title, criteria and, once
/// unlocked, when.
class AchievementCard extends StatelessWidget {
  const AchievementCard({super.key, required this.status, required this.board});

  final AchievementStatus status;
  final AchievementBoard board;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final definition = status.definition;
    final unlock = status.unlock;
    final when = unlock == null
        ? null
        : 'Day ${board.dayNumberOf(unlock.unlockedOn)} · '
              '${DateFormat('d MMM').format(unlock.unlockedOn.toLocalDateTime())}';
    return Semantics(
      container: true,
      label: [
        definition.title,
        if (when != null) 'Unlocked, $when' else 'Locked',
        definition.description,
      ].join('. '),
      excludeSemantics: true,
      child: WinterCard(
        highlighted: unlock != null,
        accent: definition.key.accent(colors),
        padding: const EdgeInsets.all(WinterSpacing.md),
        child: Column(
          children: [
            AchievementBadge(
              achievement: definition.key,
              unlocked: unlock != null,
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              definition.title,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: unlock != null
                    ? colors.textPrimary
                    : colors.textSecondary,
              ),
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              definition.description,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              when ?? 'LOCKED',
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: unlock != null
                    ? definition.key.accent(colors)
                    : colors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
