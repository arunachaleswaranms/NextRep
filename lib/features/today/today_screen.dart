import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/progress/day_summary.dart';
import '../../domain/progress/habit_progress_rules.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'today_controller.dart';
import 'widgets/day_header.dart';
import 'widgets/habit_progress_tile.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-read on resume so a day rollover while backgrounded is picked up.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(todayControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _perform(Habit habit, HabitAction action) async {
    final result = await ref
        .read(todayControllerProvider.notifier)
        .perform(habit.id, action);
    if (!mounted) return;

    // Feedback runs only after the domain result is persisted.
    switch (result) {
      case ActionSuccess(
        value: ProgressTransition(xpEffect: GrantXp(:final award)),
      ):
        HapticFeedback.lightImpact();
        _showSnack(
          '${habit.title} complete · +${award.amount} XP',
          undo: () => _perform(habit, HabitProgressRules.undoActionFor(habit)),
        );
      case ActionSuccess(value: ProgressTransition(becameIncomplete: true)):
        _showSnack('${habit.title} marked not done');
      case ActionSuccess():
        break;
      case ActionFailure(:final failure):
        _showSnack(userMessageFor(failure));
    }
  }

  void _showSnack(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          action: undo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: undo),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayControllerProvider);
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (today) {
            AsyncData(:final value) => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(todayControllerProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DaySummary summary) {
    final text = Theme.of(context).textTheme;
    final completion = summary.completion;
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.lg),
      children: [
        DayHeader(summary: summary),
        const SizedBox(height: WinterSpacing.xl),
        Row(
          children: [
            Expanded(child: Text("Today's habits", style: text.titleMedium)),
            Text(
              '${completion.completed} of ${completion.total} done',
              style: text.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: WinterSpacing.md),
        for (final entry in summary.entries) ...[
          HabitProgressTile(
            key: ValueKey(entry.habit.id),
            entry: entry,
            enabled: summary.isTrackable,
            onAction: (action) => _perform(entry.habit, action),
          ),
          const SizedBox(height: WinterSpacing.sm),
        ],
      ],
    );
  }
}
