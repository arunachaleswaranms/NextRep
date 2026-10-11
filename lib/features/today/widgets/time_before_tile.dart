import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/progress/day_record.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

/// A clock-time habit on Today, e.g. Sleep Before Target: the time
/// recorded for today against the goal.
///
/// Sleep Before Target ([isBedtimeCheckIn]) is a morning check-in: today's
/// record is the time the user went to bed for the sleep that ended this
/// morning ("Last night's bedtime"), and the card says so, with an
/// explanation of why it counts for today. Other clock-time habits keep
/// neutral wording. Tapping the card opens a clock picker; a recorded time
/// can be changed or cleared. A time after the goal stays recorded, it just
/// isn't a completion.
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
      helpText: isBedtimeCheckIn(_habit)
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
    final bedtime = isBedtimeCheckIn(_habit);
    final status = completed
        ? (bedtime ? 'Goal met' : 'Done')
        : 'After the goal';

    return Semantics(
      container: true,
      button: enabled,
      label: [
        _habit.title,
        if (bedtime)
          logged == null
              ? "last night's bedtime not logged"
              : "last night's bedtime ${logged.hhmm}"
        else if (logged == null)
          'not logged'
        else
          '$record ${logged.hhmm}',
        'goal before ${clockLabel(entry.target)}',
        // Found on a device: "not logged" was said twice.
        if (logged != null) status,
        if (bedtime) "counts toward today's check-in",
        if (streak > 0) '$streak day streak',
      ].join(', '),
      hint: enabled
          ? (logged == null
                ? 'Double tap to log a time'
                : 'Double tap to change the time')
          : null,
      onTap: enabled ? () => _pick(context) : null,
      // The card's Clear and info buttons are inside the excluded subtree,
      // so they are offered as custom actions instead.
      customSemanticsActions: {
        if (logged != null && enabled)
          const CustomSemanticsAction(label: 'Clear time'): onClear,
        if (bedtime)
          const CustomSemanticsAction(label: BedtimeExplanation.question): () =>
              BedtimeExplanation.show(context),
      },
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
                  if (bedtime)
                    Row(
                      children: [
                        Expanded(
                          child: Text(_habit.title, style: text.titleMedium),
                        ),
                        IconButton(
                          tooltip: BedtimeExplanation.question,
                          iconSize: 20,
                          onPressed: () => BedtimeExplanation.show(context),
                          icon: Icon(
                            Icons.info_outline_rounded,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(_habit.title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  if (logged != null)
                    Text(
                      '$record · ${logged.hhmm}',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (bedtime)
                    Text(
                      record,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  Text(goal, style: text.bodyMedium),
                  if (logged != null && (bedtime || !completed))
                    Text(
                      status,
                      style: text.bodySmall?.copyWith(
                        color: completed ? accent : colors.textSecondary,
                      ),
                    )
                  else if (logged == null && bedtime && enabled)
                    Text(
                      "Tap to log it for today's check-in",
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

/// Why last night's bedtime counts for today, for Sleep Before Target.
abstract final class BedtimeExplanation {
  static const question = 'Why does this count for today?';

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(question),
      content: const SingleChildScrollView(
        child: Text(
          'Your sleep ended this morning, so last night\'s bedtime belongs '
          "to today's check-in. Log it each morning after you wake up.",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
