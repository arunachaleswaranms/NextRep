import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';
import '../../domain/achievement/achievement_catalog.dart';
import '../../domain/xp/xp.dart';
import '../achievements/widgets/achievement_badge.dart';
import 'celebration_queue.dart';

/// The card for one [CelebrationEvent]. Tapping it dismisses it.
class CelebrationCard extends StatelessWidget {
  const CelebrationCard({
    super.key,
    required this.event,
    required this.onDismiss,
  });

  final CelebrationEvent event;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final accent = switch (event) {
      DayCelebration() => colors.celebration,
      AchievementCelebration(:final unlocks) => unlocks.first.key.accent(
        colors,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      hint: 'Tap to dismiss',
      child: Material(
        color: colors.surfaceElevated,
        elevation: 10,
        shadowColor: accent.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinterRadii.card),
          side: BorderSide(color: accent.withValues(alpha: 0.7)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(WinterRadii.card),
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            child: switch (event) {
              final DayCelebration day => _DayContent(day),
              final AchievementCelebration achievements => _AchievementContent(
                achievements,
              ),
            },
          ),
        ),
      ),
    );
  }
}

TextStyle? _heading(BuildContext context, Color color) =>
    Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: color, fontWeight: FontWeight.w900, letterSpacing: 3);

/// Perfect Day and / or level up.
class _DayContent extends StatelessWidget {
  const _DayContent(this.day);

  final DayCelebration day;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (day.perfectStreak case final streak?) ...[
          Text(
            'PERFECT DAY',
            textAlign: TextAlign.center,
            style: _heading(context, colors.celebration),
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text('Every habit complete.', style: text.bodyLarge),
          const SizedBox(height: WinterSpacing.sm),
          Text(
            '+${XpRules.perfectDayBonus} XP bonus',
            style: text.titleMedium?.copyWith(color: colors.warmLight),
          ),
          Text('🔥 Perfect streak: $streak', style: text.bodyMedium),
        ],
        if (day.perfectStreak != null && day.level != null)
          const Divider(height: WinterSpacing.xl),
        if (day.level case final level?) ...[
          Text(
            'LEVEL $level',
            textAlign: TextAlign.center,
            style: _heading(context, colors.celebration),
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text('${day.levelXp} XP reached', style: text.bodyLarge),
        ],
      ],
    );
  }
}

/// One or more achievements stored by the same reconciliation.
class _AchievementContent extends StatelessWidget {
  const _AchievementContent(this.event);

  final AchievementCelebration event;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final definitions = [
      for (final u in event.unlocks) AchievementCatalog.of(u.key),
    ];
    final single = definitions.length == 1;
    final shown = definitions.take(3).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          single
              ? 'ACHIEVEMENT UNLOCKED'
              : '${definitions.length} ACHIEVEMENTS UNLOCKED',
          textAlign: TextAlign.center,
          style: _heading(
            context,
            shown.first.key.accent(colors),
          )?.copyWith(fontSize: text.titleMedium?.fontSize),
        ),
        const SizedBox(height: WinterSpacing.md),
        TweenAnimationBuilder<double>(
          // Badge reveal; immediate under reduced motion.
          tween: Tween(begin: 0.6, end: 1),
          duration: context.motion.celebration,
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: WinterSpacing.sm,
            children: [
              for (final d in shown)
                AchievementBadge(
                  achievement: d.key,
                  unlocked: true,
                  size: single ? 72 : 52,
                ),
            ],
          ),
        ),
        const SizedBox(height: WinterSpacing.md),
        if (single) ...[
          Text(
            definitions.single.title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text(
            definitions.single.description,
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ] else
          Text(
            [
              for (final d in shown) d.title,
              if (definitions.length > shown.length)
                '+${definitions.length - shown.length} more',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: text.titleMedium,
          ),
      ],
    );
  }
}
