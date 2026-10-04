import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/progress/day_record.dart';
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
    this.streak = 0,
    this.minimum = false,
    this.enabled = true,
  });

  final HabitDayEntry entry;
  final ValueChanged<HabitAction> onAction;

  /// Current streak in days; shown when positive.
  final int streak;

  /// Today is a Minimum Day, so [HabitDayEntry.target] is the minimum.
  final bool minimum;

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
                        target: entry.target,
                        completed: completed,
                      ),
                      style: text.bodyMedium?.copyWith(
                        color: completed ? colors.success : null,
                      ),
                    ),
                    if (minimum || streak > 0) ...[
                      const SizedBox(height: WinterSpacing.xs),
                      Wrap(
                        spacing: WinterSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (minimum) const _MinimumChip(),
                          if (streak > 0)
                            Text(
                              streakLabel(streak),
                              style: text.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
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
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  end: (progress.currentValue / entry.target).clamp(0.0, 1.0),
                ),
                duration: context.motion.standard,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  semanticsLabel: '${_habit.title} progress',
                  minHeight: 6,
                  color: completed
                      ? colors.success
                      : minimum
                      ? colors.recovery
                      : colors.accentSecondary,
                ),
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
      icon: AnimatedSwitcher(
        duration: context.motion.quick,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          key: ValueKey(completed),
          color: completed ? colors.success : colors.textSecondary,
        ),
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
        onPressed: enabled && value < entry.target
            ? () => onAction(HabitAction.increment)
            : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ];
  }
}

class _MinimumChip extends StatelessWidget {
  const _MinimumChip();

  @override
  Widget build(BuildContext context) {
    final color = context.winter.recovery;
    return Text(
      'MINIMUM',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}
