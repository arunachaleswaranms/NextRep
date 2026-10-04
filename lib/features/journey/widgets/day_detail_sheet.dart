import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/journey_day.dart';
import '../../../domain/progress/day_record.dart';
import '../../../shared/formatting/habit_labels.dart';
import 'journey_tile.dart';

/// Read-only summary of a past day or today.
class DayDetailSheet extends StatelessWidget {
  const DayDetailSheet({super.key, required this.day, required this.record});

  final JourneyDay day;
  final DayRecord record;

  static Future<void> show(BuildContext context, JourneyDay day) {
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
            _Fact(label: 'Perfect Day', value: record.isPerfect ? 'Yes' : 'No'),
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
                          ? colors.success
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: WinterSpacing.sm),
                    Expanded(
                      child: Text(entry.habit.title, style: text.bodyLarge),
                    ),
                    Text(
                      progressLabel(
                        entry.habit,
                        entry.progress.currentValue,
                        target: entry.target,
                        completed: entry.progress.completed,
                      ),
                      style: text.bodyMedium,
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
          Text(value, style: text.titleSmall),
        ],
      ),
    );
  }
}
