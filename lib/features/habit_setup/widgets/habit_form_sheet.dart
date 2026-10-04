import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/habit/habit.dart';
import '../../../domain/habit/habit_edit.dart';
import '../../../domain/habit/setup_habit_rules.dart';
import '../../../shared/formatting/habit_labels.dart';
import '../../../shared/widgets/habit_icon.dart';

/// Creates a habit of the user's own, or changes one during setup. Pops a
/// [HabitDraft], or null.
///
/// The fields follow the type: nothing numeric for done / not done, a
/// target and a Minimum Day target for a count or minutes, a goal time for
/// "before a time" (whose Minimum Day target is the same). Switching type
/// resets the numbers, so nothing from another type is kept. The domain
/// validates the draft again when it is saved.
class HabitFormSheet extends StatefulWidget {
  const HabitFormSheet({super.key, this.habit});

  /// The habit being changed; null to create one. Its type can't change.
  final Habit? habit;

  static Future<HabitDraft?> show(BuildContext context, {Habit? habit}) =>
      showModalBottomSheet<HabitDraft>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.winter.surface,
        builder: (_) => HabitFormSheet(habit: habit),
      );

  @override
  State<HabitFormSheet> createState() => _HabitFormSheetState();
}

class _HabitFormSheetState extends State<HabitFormSheet> {
  late final _title = TextEditingController(text: widget.habit?.title ?? '');
  late final _unit = TextEditingController(
    text: widget.habit?.type == HabitType.count ? widget.habit?.unit : '',
  );
  late HabitType _type = widget.habit?.type ?? HabitType.binary;
  late String _icon = widget.habit?.iconKey ?? HabitIconKeys.fallback;
  late int _target = widget.habit?.target ?? _defaultTarget(_type);
  late int _minimum = widget.habit?.minimumTarget ?? _defaultMinimum(_type);
  String? _error;

  bool get _editing => widget.habit != null;

  static int _defaultTarget(HabitType type) => switch (type) {
    HabitType.binary => 1,
    HabitType.count => 5,
    HabitType.duration => 20,
    HabitType.timeBefore => NightTime(23, 0).value,
  };

  static int _defaultMinimum(HabitType type) => switch (type) {
    HabitType.binary => 1,
    HabitType.count => 2,
    HabitType.duration => 5,
    HabitType.timeBefore => _defaultTarget(type),
  };

  int get _step => _type == HabitType.duration ? 5 : 1;
  int get _max => HabitEditRules.maxTargetFor(_type);

  @override
  void dispose() {
    _title.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _setType(HabitType type) => setState(() {
    _type = type;
    // Nothing of the previous type is kept.
    _target = _defaultTarget(type);
    _minimum = _defaultMinimum(type);
    _unit.clear();
  });

  void _setTarget(int value) => setState(() {
    _target = value.clamp(_step, _max);
    if (_minimum > _target) _minimum = _target;
  });

  void _setMinimum(int value) =>
      setState(() => _minimum = value.clamp(1, _target));

  Future<void> _pickTime() async {
    final current = NightTime.fromValue(_target);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Goal: before',
    );
    if (picked == null || !mounted) return;
    final time = NightTime.tryClock(picked.hour, picked.minute);
    setState(() {
      if (time == null) {
        _error = 'Pick a time between 18:00 and 05:59.';
      } else {
        _error = null;
        _target = _minimum = time.value;
      }
    });
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give your habit a name.');
      return;
    }
    Navigator.of(context).pop(
      HabitDraft(
        title: _title.text,
        type: _type,
        iconKey: _icon,
        target: _type == HabitType.binary ? null : _target,
        minimumTarget: _type.isNumeric ? _minimum : null,
        unit: _type == HabitType.count ? _unit.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final unit = switch (_type) {
      HabitType.duration => 'min',
      HabitType.count =>
        _unit.text.trim().isEmpty
            ? SetupHabitRules.defaultCountUnit
            : _unit.text.trim(),
      _ => '',
    };
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
              Text(
                _editing ? 'Edit habit' : 'Create your own',
                style: text.headlineSmall,
              ),
              const SizedBox(height: WinterSpacing.md),
              TextField(
                controller: _title,
                maxLength: HabitEditRules.maxTitleLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (!_editing) ...[
                Text('Type', style: text.titleSmall),
                const SizedBox(height: WinterSpacing.xs),
                Semantics(
                  label: 'Habit type',
                  child: Wrap(
                    spacing: WinterSpacing.sm,
                    runSpacing: WinterSpacing.xs,
                    children: [
                      for (final type in HabitType.values)
                        ChoiceChip(
                          label: Text(habitTypeLabel(type)),
                          selected: _type == type,
                          onSelected: (_) => _setType(type),
                        ),
                    ],
                  ),
                ),
              ] else
                Text('Type: ${habitTypeLabel(_type)}', style: text.bodyMedium),
              const SizedBox(height: WinterSpacing.md),
              ...switch (_type) {
                HabitType.binary => [
                  Text(
                    'Done / not done, on normal and Minimum Days.',
                    style: text.bodyMedium,
                  ),
                ],
                HabitType.count || HabitType.duration => [
                  if (_type == HabitType.count)
                    TextField(
                      controller: _unit,
                      maxLength: SetupHabitRules.maxUnitLength,
                      decoration: const InputDecoration(
                        labelText: 'Unit (e.g. pages, glasses)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  _Stepper(
                    label: 'Daily goal',
                    value: '$_target $unit'.trimRight(),
                    onMinus: _target > _step
                        ? () => _setTarget(_target - _step)
                        : null,
                    onPlus: _target < _max
                        ? () => _setTarget(_target + _step)
                        : null,
                  ),
                  const SizedBox(height: WinterSpacing.sm),
                  _Stepper(
                    label: 'Minimum Day goal',
                    value: '$_minimum $unit'.trimRight(),
                    accent: colors.recovery,
                    onMinus: _minimum > 1
                        ? () => _setMinimum(_minimum - _step)
                        : null,
                    onPlus: _minimum < _target
                        ? () => _setMinimum(_minimum + _step)
                        : null,
                  ),
                ],
                HabitType.timeBefore => [
                  Semantics(
                    button: true,
                    label:
                        'Goal time, before ${clockLabel(_target)}. '
                        'Double tap to change.',
                    excludeSemantics: true,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Goal: before'),
                      trailing: Text(
                        clockLabel(_target),
                        style: text.titleMedium,
                      ),
                      onTap: _pickTime,
                    ),
                  ),
                  Text(
                    'Log the time once a day, between 18:00 and 05:59. '
                    'Clock-time habits keep the same target on a Minimum Day.',
                    style: text.bodySmall,
                  ),
                ],
              },
              const SizedBox(height: WinterSpacing.md),
              Text('Icon', style: text.titleSmall),
              const SizedBox(height: WinterSpacing.xs),
              Wrap(
                spacing: WinterSpacing.xs,
                runSpacing: WinterSpacing.xs,
                children: [
                  for (final key in {
                    ...HabitIconKeys.all,
                    if (widget.habit case final habit?) habit.iconKey,
                  })
                    Semantics(
                      button: true,
                      selected: key == _icon,
                      label: 'Icon ${key.replaceAll('_', ' ')}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(WinterRadii.button),
                        onTap: () => setState(() => _icon = key),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: HabitIcon(iconKey: key, active: key == _icon),
                        ),
                      ),
                    ),
                ],
              ),
              if (_error case final error?) ...[
                const SizedBox(height: WinterSpacing.sm),
                Text(
                  error,
                  style: text.bodyMedium?.copyWith(color: colors.danger),
                ),
              ],
              const SizedBox(height: WinterSpacing.lg),
              FilledButton(
                onPressed: _save,
                child: Text(_editing ? 'Save' : 'Add habit'),
              ),
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
    return Semantics(
      label: '$label, $value',
      child: Row(
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
      ),
    );
  }
}
