import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

class HabitToggleTile extends StatelessWidget {
  const HabitToggleTile({
    super.key,
    required this.habit,
    required this.onChanged,
  });

  final Habit habit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return WinterCard(
      highlighted: habit.enabled,
      onTap: () => onChanged(!habit.enabled),
      child: Row(
        children: [
          HabitIcon(iconKey: habit.iconKey),
          const SizedBox(width: WinterSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.title, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(targetLabel(habit, habit.target), style: text.bodyMedium),
              ],
            ),
          ),
          Switch(value: habit.enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
