import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/progress/day_record.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/winter_card.dart';

/// Entry point to Minimum Day on a normal day. Opens the explanation; it
/// never switches the day by itself.
class RoughDayCard extends StatelessWidget {
  const RoughDayCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined, color: colors.recovery),
          const SizedBox(width: WinterSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Having a rough day?', style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Keep your streaks alive with a Minimum Day.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
        ],
      ),
    );
  }
}

/// Shown on Today while it is a Minimum Day.
class MinimumDayBanner extends StatelessWidget {
  const MinimumDayBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(WinterSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.recovery.withValues(alpha: 0.2),
            colors.warmLight.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(WinterRadii.card),
        border: Border.all(color: colors.recovery.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_fire_department_rounded, color: colors.recovery),
          const SizedBox(width: WinterSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minimum Day',
                  style: text.titleMedium?.copyWith(color: colors.recovery),
                ),
                const SizedBox(height: 2),
                Text(
                  'Keep moving, even if today is smaller.',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text('Consistency beats intensity.', style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains Minimum Day and asks for confirmation. Pops `true` only when
/// the user confirms.
class MinimumDaySheet extends StatelessWidget {
  const MinimumDaySheet({super.key, required this.entries});

  /// Today's habits, used to preview their minimum targets.
  final List<HabitDayEntry> entries;

  static Future<bool> show(
    BuildContext context,
    List<HabitDayEntry> entries,
  ) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => MinimumDaySheet(entries: entries),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
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
            Text(
              'MINIMUM DAY',
              style: text.labelLarge?.copyWith(
                color: colors.recovery,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text('Today can be smaller.', style: text.headlineSmall),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              'Keep the chain alive with the essential version of your '
              'habits. Consistency beats intensity on hard days.',
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WinterSpacing.lg),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(entry.habit.title, style: text.bodyLarge),
                    ),
                    const SizedBox(width: WinterSpacing.sm),
                    Flexible(
                      child: Text(
                        entry.habit.type.isNumeric
                            ? '${targetLabel(entry.habit, entry.target)}  →  '
                                  '${targetLabel(entry.habit, entry.config.minimumTarget)}'
                            : 'Same',
                        textAlign: TextAlign.end,
                        style: text.bodyMedium?.copyWith(
                          color: colors.recovery,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              'Your progress so far is kept. Minimum Days keep habit '
              'streaks going, but are not Perfect Days. This applies to '
              'today only and cannot be undone.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WinterSpacing.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.recovery,
                foregroundColor: colors.background,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Switch to Minimum Day'),
            ),
            const SizedBox(height: WinterSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
