import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/progress/day_summary.dart';
import '../../../domain/progress/habit_progress_rules.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

/// One habit on the Today screen.
///
/// Binary habits: tap the row (or the check) to complete; tap again to undo.
/// Numeric habits: use the − / + buttons; reaching the target completes it.
class HabitProgressTile extends StatelessWidget {
  const HabitProgressTile({
    super.key,
    required this.entry,
    required this.onAction,
    this.enabled = true,
  });

  final HabitDayEntry entry;
  final ValueChanged<HabitAction> onAction;

  /// False when the arc is not running today; the row is read-only.
  final bool enabled;

  Habit get _habit => entry.habit;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final progress = entry.progress;
    final completed = progress.completed;

    return WinterCard(
      highlighted: completed,
      onTap: enabled && !_habit.type.isNumeric
          ? () => onAction(
              completed ? HabitAction.undoCompletion : HabitAction.complete,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HabitIcon(iconKey: _habit.iconKey, active: completed),
              const SizedBox(width: WinterSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_habit.title, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      progressLabel(
                        _habit,
                        progress.currentValue,
                        completed: completed,
                      ),
                      style: text.bodyMedium?.copyWith(
                        color: completed ? colors.success : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (_habit.type.isNumeric)
                ..._stepper(context)
              else
                _check(context),
            ],
          ),
          if (_habit.type.isNumeric) ...[
            const SizedBox(height: WinterSpacing.sm + 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(WinterRadii.pill),
              child: LinearProgressIndicator(
                value: progress.currentValue / _habit.target,
                semanticsLabel: '${_habit.title} progress',
                minHeight: 6,
                color: completed ? colors.success : colors.accentSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _check(BuildContext context) {
    final colors = context.winter;
    final completed = entry.progress.completed;
    return IconButton(
      tooltip: completed ? 'Undo ${_habit.title}' : 'Complete ${_habit.title}',
      onPressed: enabled
          ? () => onAction(
              completed ? HabitAction.undoCompletion : HabitAction.complete,
            )
          : null,
      iconSize: 32,
      icon: Icon(
        completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: completed ? colors.success : colors.textSecondary,
      ),
    );
  }

  List<Widget> _stepper(BuildContext context) {
    final value = entry.progress.currentValue;
    return [
      IconButton.filledTonal(
        tooltip: 'Remove from ${_habit.title}',
        onPressed: enabled && value > 0
            ? () => onAction(HabitAction.decrement)
            : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      const SizedBox(width: WinterSpacing.xs),
      IconButton.filled(
        tooltip: 'Add to ${_habit.title}',
        onPressed: enabled && value < _habit.target
            ? () => onAction(HabitAction.increment)
            : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ];
  }
}
