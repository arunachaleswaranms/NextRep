import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';
import '../../../shared/widgets/winter_card.dart';
import '../setup_labels.dart';

/// A habit of an arc in setup: switch it on or off, move it, change it, or
/// remove it.
///
/// In Habit Setup's list ([movable]) the options menu offers Move up and
/// Move down and the card exposes them as screen-reader actions, so no
/// move needs a drag. With two or more habits the card can also be dragged
/// ([reorderable]): the leading handle starts a drag at once, a long press
/// anywhere else on the card after the usual delay. A short tap still
/// switches the habit.
class HabitToggleTile extends StatelessWidget {
  const HabitToggleTile({
    super.key,
    required this.habit,
    required this.onChanged,
    this.onEdit,
    this.onDelete,
    this.index = 0,
    this.count = 1,
    this.movable = false,
    this.onMoveUp,
    this.onMoveDown,
    this.reorderable = false,
    this.dragging = false,
  });

  final Habit habit;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// This card's place in the list (0-based) and the list's length.
  final int index;
  final int count;

  /// Whether the menu shows Move up / Move down (disabled where the move
  /// isn't possible).
  final bool movable;

  /// Null when the move isn't possible (first or last card).
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Whether the card can be dragged: it is in a [SliverReorderableList]
  /// of two or more habits.
  final bool reorderable;

  /// A drag is in progress somewhere in the list: switching, the menu and
  /// the moves wait until it ends.
  final bool dragging;

  /// Above this text scale the switch and menu move under the title.
  static const stackedTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > stackedTextScale;
    final goals = switch (habit.type) {
      HabitType.count || HabitType.duration =>
        '${targetLabel(habit, habit.target)} · Minimum '
            '${targetLabel(habit, habit.minimumTarget)}',
      _ => targetLabel(habit, habit.target),
    };
    final moveUp = dragging ? null : onMoveUp;
    final moveDown = dragging ? null : onMoveDown;

    final details = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(habit.title, style: text.titleMedium),
          const SizedBox(height: 2),
          Text(goals, style: text.bodyMedium),
          if (isBedtimeCheckIn(habit))
            Text(
              "Morning check-in · counts toward the day you wake up",
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
    final controls = [
      if (onEdit != null || onDelete != null || movable)
        _OptionsMenu(
          habit: habit,
          enabled: !dragging,
          showMoves: movable,
          onMoveUp: moveUp,
          onMoveDown: moveDown,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      Semantics(
        container: true,
        label: habit.title,
        child: Switch(
          value: habit.enabled,
          onChanged: dragging ? null : onChanged,
        ),
      ),
    ];

    final Widget body = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HabitIcon(iconKey: habit.iconKey),
                  const SizedBox(width: WinterSpacing.sm),
                  Expanded(child: details),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(mainAxisSize: MainAxisSize.min, children: controls),
              ),
            ],
          )
        : Row(
            children: [
              HabitIcon(iconKey: habit.iconKey),
              const SizedBox(width: WinterSpacing.md),
              Expanded(child: details),
              ...controls,
            ],
          );

    final card = Semantics(
      container: true,
      label: movable
          ? SetupLabels.habitCard(habit, index: index, of: count)
          : '${habit.title}, $goals, ${habit.enabled ? 'on' : 'off'}',
      customSemanticsActions: {
        const CustomSemanticsAction(label: SetupLabels.moveUp): ?moveUp,
        const CustomSemanticsAction(label: SetupLabels.moveDown): ?moveDown,
      },
      child: WinterCard(
        highlighted: habit.enabled,
        onTap: dragging ? null : () => onChanged(!habit.enabled),
        padding: reorderable
            ? const EdgeInsetsDirectional.fromSTEB(
                WinterSpacing.xs,
                WinterSpacing.md,
                WinterSpacing.md,
                WinterSpacing.md,
              )
            : const EdgeInsets.all(WinterSpacing.md),
        child: Row(
          children: [
            if (reorderable) _DragHandle(habit: habit, index: index),
            Expanded(child: body),
          ],
        ),
      ),
    );
    if (!reorderable) return card;
    // A long press on the rest of the card starts a drag too; a short tap
    // never does, so it keeps switching the habit.
    return ReorderableDelayedDragStartListener(index: index, child: card);
  }
}

/// The leading grip: pressing it starts a drag at once. 48 × 48 dp at any
/// text size.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.habit, required this.index});

  final Habit habit;
  final int index;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    // A tap on the grip is not a tap on the card: it never switches the
    // habit. (A drag still wins once it moves past the touch slop.)
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: Semantics(
        container: true,
        label: SetupLabels.reorderHandle(habit),
        child: SizedBox.square(
          dimension: 48,
          child: Icon(
            Icons.drag_indicator_rounded,
            color: context.winter.textSecondary,
          ),
        ),
      ),
    ),
  );
}

/// Move up · Move down · Edit · Remove.
class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({
    required this.habit,
    required this.enabled,
    required this.showMoves,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  final Habit habit;
  final bool enabled;
  final bool showMoves;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: 'Options for ${habit.title}',
    enabled: enabled,
    icon: Icon(Icons.more_vert_rounded, color: context.winter.textSecondary),
    onSelected: (action) => action(),
    itemBuilder: (context) => [
      if (showMoves) ...[
        _item(SetupLabels.moveUp, Icons.arrow_upward_rounded, onMoveUp),
        _item(SetupLabels.moveDown, Icons.arrow_downward_rounded, onMoveDown),
      ],
      if (onEdit case final edit?) _item('Edit', Icons.edit_outlined, edit),
      if (onDelete case final delete?)
        _item('Remove', Icons.delete_outline_rounded, delete),
    ],
  );

  static PopupMenuItem<VoidCallback> _item(
    String label,
    IconData icon,
    VoidCallback? action,
  ) => PopupMenuItem(
    value: action,
    enabled: action != null,
    child: ListTile(
      enabled: action != null,
      leading: Icon(icon),
      title: Text(label),
    ),
  );
}
