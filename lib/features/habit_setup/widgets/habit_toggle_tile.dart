import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

/// A habit of an arc in setup: switch it on or off, change it, or remove
/// it.
class HabitToggleTile extends StatelessWidget {
  const HabitToggleTile({
    super.key,
    required this.habit,
    required this.onChanged,
    this.onEdit,
    this.onDelete,
  });

  final Habit habit;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final goals = switch (habit.type) {
      HabitType.count || HabitType.duration =>
        '${targetLabel(habit, habit.target)} · Minimum '
            '${targetLabel(habit, habit.minimumTarget)}',
      _ => targetLabel(habit, habit.target),
    };
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
                Text(goals, style: text.bodyMedium),
              ],
            ),
          ),
          if (onEdit != null || onDelete != null)
            PopupMenuButton<VoidCallback>(
              tooltip: 'Options for ${habit.title}',
              icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                if (onEdit case final edit?)
                  PopupMenuItem(
                    value: edit,
                    child: const ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                    ),
                  ),
                if (onDelete case final delete?)
                  PopupMenuItem(
                    value: delete,
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Remove'),
                    ),
                  ),
              ],
            ),
          Semantics(
            label: habit.title,
            child: Switch(value: habit.enabled, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
