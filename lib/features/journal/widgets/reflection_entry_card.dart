import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/reflection/daily_reflection.dart';
import '../../../shared/widgets/winter_card.dart';
import 'mood_style.dart';

/// A saved reflection, read-only: day, date, mood and the two answers.
/// Read by screen readers as one entry.
class ReflectionEntryCard extends StatelessWidget {
  const ReflectionEntryCard({
    super.key,
    required this.reflection,
    required this.dayNumber,
    this.trailing,
  });

  final DailyReflection reflection;
  final int dayNumber;

  /// E.g. an Edit button for today's reflection, shown below the entry.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final date = DateFormat('EEE d MMM')
        .format(reflection.date.toLocalDateTime());
    final mood = reflection.mood;
    final label = [
      'Day $dayNumber, $date',
      if (mood != null) 'Mood: ${mood.label}',
      if (reflection.win case final win?) 'Win: $win',
      if (reflection.improvement case final next?) 'To improve: $next',
    ].join('. ');
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: label,
            excludeSemantics: true,
            child: Wrap(
              spacing: WinterSpacing.sm,
              runSpacing: WinterSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Day $dayNumber', style: text.titleMedium),
                Text(date, style: text.bodySmall),
                if (mood != null) _MoodChip(mood: mood),
              ],
            ),
          ),
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reflection.win case final win?)
                  _Answer(
                    label: 'WIN',
                    text: win,
                    color: colors.accentSecondary,
                  ),
                if (reflection.improvement case final next?)
                  _Answer(
                    label: 'TO IMPROVE',
                    text: next,
                    color: colors.textSecondary,
                  ),
              ],
            ),
          ),
          if (trailing case final action?)
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
        ],
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({required this.mood});

  final Mood mood;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final tint = mood.colorOf(colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WinterSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WinterRadii.pill),
        border: Border.all(color: tint.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mood.icon, size: 16, color: tint),
          const SizedBox(width: WinterSpacing.xs),
          Flexible(
            child: Text(
              mood.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: WinterSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.labelSmall?.copyWith(color: color, letterSpacing: 1.5),
          ),
          const SizedBox(height: 2),
          Text(text, style: theme.bodyLarge),
        ],
      ),
    );
  }
}
