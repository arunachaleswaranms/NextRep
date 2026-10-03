import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import 'habit_setup_controller.dart';
import 'widgets/habit_toggle_tile.dart';

class HabitSetupScreen extends ConsumerStatefulWidget {
  const HabitSetupScreen({super.key});

  @override
  ConsumerState<HabitSetupScreen> createState() => _HabitSetupScreenState();
}

class _HabitSetupScreenState extends ConsumerState<HabitSetupScreen> {
  bool _starting = false;

  HabitSetupController get _controller =>
      ref.read(habitSetupControllerProvider.notifier);

  Future<void> _toggle(Habit habit, bool enabled) async {
    final result = await _controller.setEnabled(habit.id, enabled: enabled);
    if (result case ActionFailure(:final failure)) _showFailure(failure);
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final result = await _controller.start();
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        context.go(AppRoutes.today);
      case ActionFailure(:final failure):
        setState(() => _starting = false);
        _showFailure(failure);
    }
  }

  void _showFailure(AppFailure failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
  }

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitSetupControllerProvider);
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (habits) {
            AsyncData(:final value) => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(habitSetupControllerProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<Habit> habits) {
    final text = Theme.of(context).textTheme;
    final selected = habits.where((h) => h.enabled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.lg,
            WinterSpacing.lg,
            WinterSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose your habits', style: text.headlineMedium),
              const SizedBox(height: WinterSpacing.sm),
              Text(
                'Pick the small daily actions you will show up for.',
                style: text.bodyLarge?.copyWith(
                  color: context.winter.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.lg),
            itemCount: habits.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: WinterSpacing.sm),
            itemBuilder: (context, index) {
              final habit = habits[index];
              return HabitToggleTile(
                key: ValueKey(habit.id),
                habit: habit,
                onChanged: (enabled) => _toggle(habit, enabled),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(WinterSpacing.lg),
          child: Column(
            children: [
              Text(
                selected == 1
                    ? '1 habit selected'
                    : '$selected habits selected',
                style: text.bodyMedium,
              ),
              const SizedBox(height: WinterSpacing.sm),
              PrimaryButton(
                label: 'Start Winter Arc',
                busy: _starting,
                onPressed: selected == 0 ? null : _start,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
