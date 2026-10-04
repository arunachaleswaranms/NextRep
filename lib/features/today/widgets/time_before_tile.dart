import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/progress/day_record.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

/// A clock-time habit on Today, e.g. Sleep Before Target: the time
/// recorded for today against the goal.
///
/// Sleep Before Target is a morning check-in: today's record is the time
/// the user went to bed for the sleep that ended this morning ("Last
/// night"). Tapping the card opens a clock picker; a recorded time can be
/// changed or cleared. A time after the goal stays recorded, it just isn't
/// a completion.
class TimeBeforeHabitTile extends StatelessWidget {
  const TimeBeforeHabitTile({
    super.key,
    required this.entry,
    required this.onSetTime,
    required this.onClear,
    this.streak = 0,
    this.enabled = true,
  });

  final HabitDayEntry entry;
  final ValueChanged<NightTime> onSetTime;
  final VoidCallback onClear;
  final int streak;
  final bool enabled;

  Habit get _habit => entry.habit;

  NightTime? get _logged => NightTime.tryValue(entry.progress.currentValue);

  Future<void> _pick(BuildContext context) async {
    final initial = _logged ?? NightTime.fromValue(entry.target);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: clockRecordLabel(_habit) == 'Last night'
          ? 'When did you go to bed last night?'
          : 'What time was it?',
    );
    if (picked == null || !context.mounted) return;
    final time = NightTime.tryClock(picked.hour, picked.minute);
    if (time == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Pick a time between 18:00 and 05:59.')),
        );
      return;
    }
    onSetTime(time);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completed = entry.progress.completed;
    final logged = _logged;
    final accent = WinterHabitAccents.of(_habit.iconKey);
    final goal = 'Goal · before ${clockLabel(entry.target)}';
    final record = clockRecordLabel(_habit);
    final status = logged == null
        ? 'Not logged'
        : completed
        ? 'Done'
        : 'After the goal';

    return Semantics(
      container: true,
      button: enabled,
      label: [
        _habit.title,
        if (logged == null) 'not logged' else '$record ${logged.hhmm}',
        'goal before ${clockLabel(entry.target)}',
        status,
        if (streak > 0) '$streak day streak',
      ].join(', '),
      hint: enabled
          ? (logged == null
                ? 'Double tap to log a time'
                : 'Double tap to change the time')
          : null,
      excludeSemantics: true,
      child: WinterCard(
        highlighted: completed,
        accent: accent,
        onTap: enabled ? () => _pick(context) : null,
        child: Row(
          children: [
            HabitIcon(
              iconKey: _habit.iconKey,
              active: completed,
              accent: accent,
            ),
            const SizedBox(width: WinterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_habit.title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  if (logged != null)
                    Text(
                      '$record · ${logged.hhmm}',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(goal, style: text.bodyMedium),
                  if (logged != null && !completed)
                    Text(
                      'After the goal',
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (streak > 0) ...[
                    const SizedBox(height: WinterSpacing.xs),
                    Text(
                      streakLabel(streak),
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (logged != null && enabled)
              IconButton(
                tooltip: 'Clear ${_habit.title} time',
                onPressed: onClear,
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              ),
            Icon(
              completed
                  ? Icons.check_circle_rounded
                  : logged == null
                  ? Icons.schedule_rounded
                  : Icons.radio_button_unchecked,
              size: 30,
              color: completed ? accent : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
