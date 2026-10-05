import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/habit/habit_config.dart';
import '../../domain/habit/habit_edit.dart';
import '../../domain/progress/habit_tracking_service.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/formatting/habit_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'habits_controller.dart';
import 'widgets/habit_edit_sheet.dart';

/// Edit habits after the arc has started. Renames apply now; goals and
/// on/off apply from tomorrow, so today keeps the setup it started with.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    String habitId,
    HabitEdit edit,
  ) async {
    final result = await ref
        .read(habitsControllerProvider.notifier)
        .edit(habitId, edit);
    if (!context.mounted) return;
    final message = switch (result) {
      ActionSuccess(:final value) when value.configFrom != null =>
        'Saved. Applies from tomorrow.',
      ActionSuccess(:final value) when value.renamed => 'Renamed.',
      ActionSuccess() => 'No changes.',
      ActionFailure(:final failure) => userMessageFor(failure),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    HabitSetting setting,
    bool configEditable,
  ) async {
    final edit = await HabitEditSheet.show(
      context,
      setting,
      configEditable: configEditable,
    );
    if (edit != null && context.mounted) {
      await _apply(context, ref, setting.habit.id, edit);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(habitsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your habits')),
      body: WinterBackground(
        // Keeps the last card clear of the system gesture bar.
        child: SafeArea(
          top: false,
          child: switch (settings) {
            AsyncData(:final value) => _content(context, ref, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(habitsControllerProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, HabitSettings value) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.lg),
      children: [
        Text(
          value.configEditable
              ? 'Goal and on/off changes start tomorrow, so today stays as it '
                    'began. Renames apply now. Past days keep the goals they had.'
              : value.editable
              ? 'Today is the last day of your Winter Arc, so goals can no '
                    'longer change. You can still rename habits.'
              : 'Habits can no longer be edited.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: WinterSpacing.md),
        for (final setting in value.habits) ...[
          WinterCard(
            key: ValueKey(setting.habit.id),
            highlighted: setting.config.enabled,
            accent: WinterHabitAccents.of(setting.habit.iconKey),
            onTap: value.editable
                ? () => _openEditor(context, ref, setting, value.configEditable)
                : null,
            child: Row(
              children: [
                HabitIcon(iconKey: setting.habit.iconKey),
                const SizedBox(width: WinterSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(setting.habit.title, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        setting.config.enabled
                            ? _goals(setting.habit, setting.config)
                            : 'Off today',
                        style: text.bodyMedium,
                      ),
                      if (setting.hasPendingChange)
                        Text(
                          _pending(setting.habit, setting.upcoming!),
                          style: text.bodySmall?.copyWith(
                            color: colors.accentSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Semantics(
                  label: '${setting.habit.title} from tomorrow',
                  child: Switch(
                    value: setting.editable.enabled,
                    onChanged: value.configEditable
                        ? (enabled) => _apply(
                            context,
                            ref,
                            setting.habit.id,
                            HabitEdit(enabled: enabled),
                          )
                        : null,
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: WinterSpacing.sm),
        ],
      ],
    );
  }

  static String _goals(Habit habit, HabitConfig config) => switch (habit.type) {
    HabitType.count || HabitType.duration =>
      '${targetLabel(habit, config.target)} · Minimum '
          '${targetLabel(habit, config.minimumTarget)}',
    HabitType.timeBefore => '${targetLabel(habit, config.target)} · every day',
    HabitType.binary => 'Daily goal',
  };

  static String _pending(Habit habit, HabitConfig upcoming) => !upcoming.enabled
      ? 'Off from tomorrow'
      : 'From tomorrow: ${_goals(habit, upcoming)}';
}
