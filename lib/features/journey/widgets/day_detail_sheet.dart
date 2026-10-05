import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/arc_milestones.dart';
import '../../../domain/journey/journey_day.dart';
import '../../../domain/progress/day_record.dart';
import '../../../shared/formatting/arc_labels.dart';
import '../../../shared/formatting/habit_labels.dart';
import 'journey_day_style.dart';

/// Read-only summary of a past day or today.
class DayDetailSheet extends StatelessWidget {
  const DayDetailSheet({super.key, required this.day, required this.record});

  final JourneyDay day;
  final DayRecord record;

  /// Shows [day]'s detail. A day before the user joined a seasonal arc
  /// ([joinDay] is the day they joined) only gets a short, read-only note;
  /// future days have none.
  static Future<void> show(
    BuildContext context,
    JourneyDay day, {
    int? joinDay,
  }) {
    if (day.isNotJoined) {
      return showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => NotJoinedDaySheet(day: day, joinDay: joinDay),
      );
    }
    final record = day.record;
    if (record == null) return Future.value(); // future days have no detail
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.winter.surface,
      builder: (_) => DayDetailSheet(day: day, record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final completion = record.completion;
    final stateColor = day.state.color(colors);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Day ${day.dayNumber}',
                    style: text.headlineSmall,
                  ),
                ),
                if (day.state.icon case final icon?) ...[
                  Icon(icon, size: 18, color: stateColor),
                  const SizedBox(width: WinterSpacing.xs),
                ],
                Text(
                  day.state.label.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: day.state == JourneyDayState.missed
                        ? colors.textSecondary
                        : stateColor,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              DateFormat('EEEE, d MMMM y').format(day.date.toLocalDateTime()),
              style: text.bodyMedium,
            ),
            Text(
              chapterTitle(JourneyChapter.forDay(day.dayNumber)),
              style: text.bodySmall?.copyWith(color: colors.accentSecondary),
            ),
            const SizedBox(height: WinterSpacing.md),
            _Fact(
              label: 'Mode',
              value: record.mode.isMinimum ? 'Minimum Day' : 'Normal Day',
            ),
            _Fact(
              label: 'Habits complete',
              value: '${completion.completed} / ${completion.total}',
            ),
            _Fact(label: 'Completion', value: '${completion.percent}%'),
            _Fact(label: 'XP earned', value: '${day.xpEarned} XP'),
            // A Minimum Day is never a Perfect Day by design, so it gets no
            // "Perfect Day: No" row that would read like a failure.
            if (record.mode.isMinimum)
              _Fact(
                label: 'Minimum Day',
                value: record.isMinimumComplete ? 'Completed' : 'In part',
              )
            else
              _Fact(
                label: 'Perfect Day',
                value: record.isPerfect ? 'Yes' : 'No',
              ),
            const Divider(height: WinterSpacing.xl),
            for (final entry in record.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      entry.progress.completed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: entry.progress.completed
                          ? colors.accentSecondary
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: WinterSpacing.sm),
                    Expanded(
                      child: Text(entry.habit.title, style: text.bodyLarge),
                    ),
                    const SizedBox(width: WinterSpacing.sm),
                    Flexible(
                      child: Text(
                        progressLabel(
                          entry.habit,
                          entry.progress.currentValue,
                          target: entry.target,
                          completed: entry.progress.completed,
                        ),
                        textAlign: TextAlign.end,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A season day before the user joined: neutral, with nothing to show.
class NotJoinedDaySheet extends StatelessWidget {
  const NotJoinedDaySheet({super.key, required this.day, this.joinDay});

  final JourneyDay day;
  final int? joinDay;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Day ${day.dayNumber}', style: text.headlineSmall),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              DateFormat('EEEE, d MMMM y').format(day.date.toLocalDateTime()),
              style: text.bodyMedium,
            ),
            const SizedBox(height: WinterSpacing.md),
            Text(
              'Before you joined this Seasonal Winter Arc.',
              style: text.titleMedium,
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              joinDay == null
                  ? 'Earlier season days are not counted against you.'
                  : 'You joined on Day $joinDay. Earlier season days are '
                        'not counted against you.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: WinterSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
