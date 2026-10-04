import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit_edit.dart';
import '../../domain/progress/habit_tracking_service.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/formatting/habit_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'habits_controller.dart';
import 'widgets/habit_edit_sheet.dart';

/// Edit habits after the arc has started. Changes apply from today onwards.
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
      ActionSuccess() => 'Saved. Applies from today.',
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
  ) async {
    final edit = await HabitEditSheet.show(context, setting);
    if (edit != null && context.mounted) {
      await _apply(context, ref, setting.habit.id, edit);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(habitsControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your habits'),
        backgroundColor: context.winter.backgroundTop,
      ),
      body: WinterBackground(
        child: switch (settings) {
          AsyncData(:final value) => _content(context, ref, value),
          AsyncError(:final error, :final stackTrace) => FailureView(
            failure: toAppFailure(error, stackTrace),
            onRetry: () => ref.invalidate(habitsControllerProvider),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
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
          'Changes apply from today. Past days keep the goals and habits '
          'they had.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: WinterSpacing.md),
        for (final setting in value.habits) ...[
          WinterCard(
            key: ValueKey(setting.habit.id),
            highlighted: setting.config.enabled,
            onTap: value.editable
                ? () => _openEditor(context, ref, setting)
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
                        setting.habit.type.isNumeric
                            ? '${targetLabel(setting.habit, setting.config.target)}'
                                  ' · Minimum '
                                  '${targetLabel(setting.habit, setting.config.minimumTarget)}'
                            : 'Daily goal',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: setting.config.enabled,
                  onChanged: value.editable
                      ? (enabled) => _apply(
                          context,
                          ref,
                          setting.habit.id,
                          HabitEdit(enabled: enabled),
                        )
                      : null,
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
}
