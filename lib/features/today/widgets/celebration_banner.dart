import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/xp/xp.dart';

/// What to celebrate after a persisted change. Built only from the commit
/// result and the re-read state, never from UI timing.
final class Celebration {
  const Celebration({this.perfectStreak, this.level, this.levelXp});

  /// Set when the commit granted today's Perfect Day bonus.
  final int? perfectStreak;

  /// Set when the commit crossed a level boundary.
  final int? level;

  /// Total XP at [level].
  final int? levelXp;

  bool get isEmpty => perfectStreak == null && level == null;
}

/// A lightweight card shown over Today for a Perfect Day and/or a level up.
class CelebrationBanner extends StatelessWidget {
  const CelebrationBanner({
    super.key,
    required this.celebration,
    required this.onDismiss,
  });

  final Celebration celebration;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final heading = text.titleLarge?.copyWith(
      color: colors.celebration,
      fontWeight: FontWeight.w900,
      letterSpacing: 3,
    );
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.surfaceElevated,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinterRadii.card),
          side: BorderSide(color: colors.celebration.withValues(alpha: 0.7)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(WinterRadii.card),
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (celebration.perfectStreak case final streak?) ...[
                  Text('PERFECT DAY', style: heading),
                  const SizedBox(height: WinterSpacing.xs),
                  Text('Every habit complete.', style: text.bodyLarge),
                  const SizedBox(height: WinterSpacing.sm),
                  Text(
                    '+${XpRules.perfectDayBonus} XP bonus',
                    style: text.titleMedium?.copyWith(color: colors.warning),
                  ),
                  Text('🔥 Perfect streak: $streak', style: text.bodyMedium),
                ],
                if (celebration.perfectStreak != null &&
                    celebration.level != null)
                  const Divider(height: WinterSpacing.xl),
                if (celebration.level case final level?) ...[
                  Text('LEVEL $level', style: heading),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(
                    '${celebration.levelXp} XP reached',
                    style: text.bodyLarge,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
