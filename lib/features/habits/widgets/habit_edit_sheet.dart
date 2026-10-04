import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit_edit.dart';
import '../../../domain/progress/habit_tracking_service.dart';

/// Edits a habit's name and goals. Pops the [HabitEdit] to save, or null.
///
/// Goals start from the configuration that applies next (including an edit
/// already made today). Without [configEditable] (the arc's last day) only
/// the name can change.
class HabitEditSheet extends StatefulWidget {
  const HabitEditSheet({
    super.key,
    required this.setting,
    this.configEditable = true,
  });

  final HabitSetting setting;
  final bool configEditable;

  static Future<HabitEdit?> show(
    BuildContext context,
    HabitSetting setting, {
    bool configEditable = true,
  }) => showModalBottomSheet<HabitEdit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.winter.surface,
    builder: (_) =>
        HabitEditSheet(setting: setting, configEditable: configEditable),
  );

  @override
  State<HabitEditSheet> createState() => _HabitEditSheetState();
}

class _HabitEditSheetState extends State<HabitEditSheet> {
  late final _title = TextEditingController(text: widget.setting.habit.title);
  late int _target = widget.setting.editable.target;
  late int _minimum = widget.setting.editable.minimumTarget;
  bool get _goalsEditable => widget.configEditable;

  int get _step => widget.setting.habit.type.step;
  int get _max => HabitEditRules.maxTargetFor(widget.setting.habit.type);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _setTarget(int value) => setState(() {
    _target = value.clamp(_step, _max);
    if (_minimum > _target) _minimum = _target;
  });

  void _setMinimum(int value) =>
      setState(() => _minimum = value.clamp(_step, _target));

  void _save() {
    final habit = widget.setting.habit;
    Navigator.of(context).pop(
      HabitEdit(
        title: _title.text,
        target: habit.type.isNumeric && _goalsEditable ? _target : null,
        minimumTarget: habit.type.isNumeric && _goalsEditable ? _minimum : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final habit = widget.setting.habit;
    final unit = habit.unit ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
              Text('Edit habit', style: text.headlineSmall),
              const SizedBox(height: WinterSpacing.md),
              TextField(
                controller: _title,
                maxLength: HabitEditRules.maxTitleLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (habit.type.isNumeric) ...[
                const SizedBox(height: WinterSpacing.sm),
                _Stepper(
                  label: 'Daily goal',
                  value: '$_target $unit'.trimRight(),
                  onMinus: _goalsEditable && _target > _step
                      ? () => _setTarget(_target - _step)
                      : null,
                  onPlus: _goalsEditable && _target < _max
                      ? () => _setTarget(_target + _step)
                      : null,
                ),
                const SizedBox(height: WinterSpacing.sm),
                _Stepper(
                  label: 'Minimum Day goal',
                  value: '$_minimum $unit'.trimRight(),
                  accent: colors.recovery,
                  onMinus: _goalsEditable && _minimum > _step
                      ? () => _setMinimum(_minimum - _step)
                      : null,
                  onPlus: _goalsEditable && _minimum < _target
                      ? () => _setMinimum(_minimum + _step)
                      : null,
                ),
              ] else
                Text(
                  'Done / not done, on normal and Minimum Days.',
                  style: text.bodyMedium,
                ),
              const SizedBox(height: WinterSpacing.md),
              Text(
                _goalsEditable
                    ? 'A new name applies now. Goal changes start tomorrow; '
                          'today and past days keep the goals they had.'
                    : 'Today is the last day, so goals can no longer change. '
                          'You can still rename this habit.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: WinterSpacing.lg),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.accent,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: text.bodyLarge)),
        IconButton.filledTonal(
          tooltip: 'Decrease $label',
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 96,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: accent),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Increase $label',
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
