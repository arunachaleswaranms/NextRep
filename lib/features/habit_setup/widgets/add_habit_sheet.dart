import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/habit/habit_template_catalog.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';

/// What the user picked in [AddHabitSheet].
sealed class AddHabitChoice {
  const AddHabitChoice();
}

final class TemplateChoice extends AddHabitChoice {
  const TemplateChoice(this.template);

  final HabitTemplate template;
}

final class CustomChoice extends AddHabitChoice {
  const CustomChoice();
}

/// Add Habit: the bundled templates, then "Create your own". Templates
/// already in the arc are shown as added.
class AddHabitSheet extends StatelessWidget {
  const AddHabitSheet({super.key, required this.existing, this.controller});

  /// Habit ids already in the arc.
  final Set<String> existing;

  final ScrollController? controller;

  static Future<AddHabitChoice?> show(
    BuildContext context, {
    required Set<String> existing,
  }) => showModalBottomSheet<AddHabitChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.winter.surface,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          AddHabitSheet(existing: existing, controller: controller),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final templates = HabitTemplateCatalog.all;
    return SafeArea(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          WinterSpacing.lg,
          0,
          WinterSpacing.lg,
          WinterSpacing.lg,
        ),
        children: [
          Text('Add a habit', style: text.headlineSmall),
          const SizedBox(height: WinterSpacing.md),
          Text(
            'TEMPLATES',
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: WinterSpacing.sm),
          for (final template in templates) ...[
            _TemplateCard(
              template: template,
              added: existing.contains(template.id),
            ),
            const SizedBox(height: WinterSpacing.sm),
          ],
          const SizedBox(height: WinterSpacing.sm),
          Text(
            'CUSTOM',
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: WinterSpacing.sm),
          Semantics(
            button: true,
            label: 'Create your own habit',
            onTap: () => Navigator.of(context).pop(const CustomChoice()),
            excludeSemantics: true,
            child: WinterCard(
              onTap: () => Navigator.of(context).pop(const CustomChoice()),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: colors.accentSecondary,
                    size: 28,
                  ),
                  const SizedBox(width: WinterSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create your own', style: text.titleMedium),
                        Text(
                          'Done / not done, a count, minutes, or before a '
                          'time.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.added});

  final HabitTemplate template;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final goals = templateGoals(template);
    return Semantics(
      button: !added,
      enabled: !added,
      label: [
        '${template.title} template',
        habitTypeLabel(template.type),
        goals,
        if (added) 'already added',
      ].join(', '),
      onTap: added
          ? null
          : () => Navigator.of(context).pop(TemplateChoice(template)),
      excludeSemantics: true,
      child: Opacity(
        opacity: added ? 0.5 : 1,
        child: WinterCard(
          onTap: added
              ? null
              : () => Navigator.of(context).pop(TemplateChoice(template)),
          child: Row(
            children: [
              HabitIcon(iconKey: template.iconKey),
              const SizedBox(width: WinterSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.title, style: text.titleMedium),
                    Text(
                      '${habitTypeLabel(template.type)} · $goals',
                      style: text.bodySmall,
                    ),
                    if (template.description case final description?)
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (added)
                Text('Added', style: text.labelMedium)
              else
                Icon(Icons.add_rounded, color: colors.accentSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Goal 30 min · Minimum 10 min", "Before 23:30, also on Minimum Days",
/// or "Daily".
String templateGoals(HabitTemplate template) {
  final habit = template.toHabit(sortOrder: 0, createdAt: DateTime(2000));
  return switch (template.type) {
    HabitType.count || HabitType.duration =>
      'Goal ${targetLabel(habit, template.target)} · Minimum '
          '${targetLabel(habit, template.minimumTarget)}',
    HabitType.timeBefore =>
      '${targetLabel(habit, template.target)}, also on Minimum Days',
    HabitType.binary => 'Daily',
  };
}
