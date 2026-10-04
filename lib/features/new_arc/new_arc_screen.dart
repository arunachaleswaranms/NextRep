import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/formatting/habit_labels.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'new_arc_controller.dart';

/// Start another Winter Arc after finishing one: reuse the last setup or
/// start fresh, then Habit Setup and "Start Winter Arc" as usual. Returning
/// users skip first-time onboarding.
class NewArcScreen extends ConsumerWidget {
  const NewArcScreen({super.key});

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    NewArcBaseline baseline,
  ) async {
    final result = await ref
        .read(newArcControllerProvider.notifier)
        .start(baseline);
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess():
        context.go(AppRoutes.habitSetup);
      case ActionFailure(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(newArcControllerProvider);
    final reusable = ref.watch(reusableHabitsProvider);
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Winter Arc'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            children: [
              Text('Your next climb', style: text.headlineMedium),
              const SizedBox(height: WinterSpacing.sm),
              Text(
                '${WinterArcRules.lengthInDays} days, starting the day you '
                'press Start. Your finished arcs stay in Arc History.',
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: WinterSpacing.lg),
              _Choice(
                icon: Icons.replay_rounded,
                title: 'Reuse last setup',
                description:
                    'Start with the habits and goals you finished your last '
                    'arc with. Progress, XP and achievements start from zero.',
                busy: busy == NewArcBaseline.reuseLast,
                enabled: busy == null && (reusable.value?.isNotEmpty ?? false),
                preview: reusable.value,
                onTap: () => _choose(context, ref, NewArcBaseline.reuseLast),
              ),
              const SizedBox(height: WinterSpacing.md),
              _Choice(
                icon: Icons.ac_unit_rounded,
                title: 'Start fresh',
                description: 'Begin again from the starter habits.',
                busy: busy == NewArcBaseline.fresh,
                enabled: busy == null,
                onTap: () => _choose(context, ref, NewArcBaseline.fresh),
              ),
              const SizedBox(height: WinterSpacing.md),
              Text(
                'You can still change which habits are on before you start.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.description,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.preview,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  /// The habits this choice starts with, if shown.
  final List<Habit>? preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final habits = [...?preview?.where((h) => h.enabled)];
    final summary = habits
        .map((h) => '${h.title} (${targetLabel(h, h.target)})')
        .join(', ');
    return Semantics(
      button: true,
      enabled: enabled,
      label: [
        title,
        description,
        if (habits.isNotEmpty) 'Habits: $summary',
      ].join('. '),
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.5,
        child: WinterCard(
          highlighted: busy,
          onTap: enabled ? onTap : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.accentSecondary, size: 28),
              const SizedBox(width: WinterSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    const SizedBox(height: WinterSpacing.xs),
                    Text(description, style: text.bodyMedium),
                    if (habits.isNotEmpty) ...[
                      const SizedBox(height: WinterSpacing.sm),
                      for (final habit in habits)
                        Text(
                          '• ${habit.title} · ${targetLabel(habit, habit.target)}',
                          style: text.bodySmall,
                        ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
