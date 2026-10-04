import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/reflection/daily_reflection.dart';
import 'mood_style.dart';

/// "How did today feel?": four moods, at most one selected. Tapping the
/// selected mood clears it (a reflection can be text only).
class MoodSelector extends StatelessWidget {
  const MoodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final Mood? selected;
  final ValueChanged<Mood?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // One row normally; two rows of two at large text sizes, so every
    // label stays whole.
    final perRow = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 4;
    const moods = Mood.values;
    return Column(
      children: [
        for (var start = 0; start < moods.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: WinterSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + perRow; i++) ...[
                  if (i > start) const SizedBox(width: WinterSpacing.sm),
                  Expanded(
                    child: _MoodOption(
                      mood: moods[i],
                      selected: moods[i] == selected,
                      onTap: enabled
                          ? () => onChanged(
                              moods[i] == selected ? null : moods[i],
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoodOption extends StatelessWidget {
  const _MoodOption({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final tint = mood.colorOf(colors);
    final radius = BorderRadius.circular(WinterRadii.button);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: onTap != null,
      label: 'Mood: ${mood.label}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motion.standard,
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: selected ? tint.withValues(alpha: 0.18) : colors.glass,
          borderRadius: radius,
          border: Border.all(
            color: selected ? tint : colors.glassBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: WinterSpacing.sm,
                horizontal: WinterSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    mood.icon,
                    color: selected ? tint : colors.textSecondary,
                  ),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(
                    mood.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: selected ? colors.textPrimary : null,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
