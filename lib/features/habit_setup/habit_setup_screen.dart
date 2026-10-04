import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_status.dart';
import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/time/clock.dart';
import '../../domain/habit/habit.dart';
import '../../domain/habit/setup_habit_rules.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import '../summary/arc_removal.dart';
import 'habit_setup_controller.dart';
import 'widgets/add_habit_sheet.dart';
import 'widgets/habit_form_sheet.dart';
import 'widgets/habit_toggle_tile.dart';

/// Habit Setup v2: which Arc this is, its habits (switch on or off, change,
/// remove, add from a template or create your own), then Start.
///
/// Everything here edits the arc's baseline directly: nothing has happened
/// yet, so there's no history to protect. Once started, habits can only be
/// renamed, re-targeted from the next day or switched off.
class HabitSetupScreen extends ConsumerStatefulWidget {
  const HabitSetupScreen({super.key});

  @override
  ConsumerState<HabitSetupScreen> createState() => _HabitSetupScreenState();
}

class _HabitSetupScreenState extends ConsumerState<HabitSetupScreen> {
  bool _starting = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // A setup left open overnight may have become startable (1 October)
    // or expired (1 January).
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  HabitSetupController get _controller =>
      ref.read(habitSetupControllerProvider.notifier);

  Future<void> _toggle(Habit habit, bool enabled) async {
    final result = await _controller.setEnabled(habit.id, enabled: enabled);
    if (result case ActionFailure(:final failure)) _showFailure(failure);
  }

  Future<void> _add(ArcSetup setup) async {
    final choice = await AddHabitSheet.show(
      context,
      existing: {for (final h in setup.habits) h.id},
    );
    if (choice == null || !mounted) return;
    final ActionResult<Habit> result;
    switch (choice) {
      case TemplateChoice(:final template):
        result = await _controller.addTemplate(template.id);
      case CustomChoice():
        final draft = await HabitFormSheet.show(context);
        if (draft == null || !mounted) return;
        result = await _controller.addCustom(draft);
    }
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value):
        _showSnack('${value.title} added');
      case ActionFailure(:final failure):
        _showFailure(failure);
    }
  }

  Future<void> _edit(Habit habit) async {
    final draft = await HabitFormSheet.show(context, habit: habit);
    if (draft == null || !mounted) return;
    final result = await _controller.edit(habit.id, draft);
    if (result case ActionFailure(:final failure)) _showFailure(failure);
  }

  Future<void> _delete(Habit habit) async {
    final result = await _controller.delete(habit.id);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        _showSnack('${habit.title} removed');
      case ActionFailure(:final failure):
        _showFailure(failure);
    }
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

  Future<void> _cancelSetup() async {
    final hasHistory = ref.read(arcResolutionProvider)?.latestCompleted != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this setup?'),
        content: Text(
          hasHistory
              ? 'Your previous completed Arcs will remain safe.'
              : 'Your habit choices will be cleared. You can start again '
                    'whenever you are ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Setup'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.winter.danger,
              foregroundColor: context.winter.textPrimary,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Setup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref.read(arcRemovalProvider).cancelSetup();
    if (!mounted) return;
    switch (result) {
      case ActionSuccess(:final value):
        context.go(value);
      case ActionFailure(:final failure):
        _showFailure(failure);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showFailure(AppFailure failure) {
    if (!mounted) return;
    _showSnack(userMessageFor(failure));
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(habitSetupControllerProvider);
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (setup) {
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

  Widget _content(BuildContext context, ArcSetup setup) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final habits = setup.habits;
    final selected = setup.enabledCount;
    final today = ref.read(clockProvider).today();
    final session = setup.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              WinterSpacing.lg,
              WinterSpacing.lg,
              WinterSpacing.lg,
              WinterSpacing.md,
            ),
            children: [
              _ArcHeader(
                session: session,
                state: setup.startState,
                todayDay: session.dayNumberOf(today),
              ),
              const SizedBox(height: WinterSpacing.lg),
              Text('Choose your habits', style: text.headlineMedium),
              const SizedBox(height: WinterSpacing.sm),
              Text(
                'Pick the small daily actions you will show up for.',
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: WinterSpacing.md),
              Text(
                'YOUR HABITS',
                style: text.labelLarge?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: WinterSpacing.sm),
              if (habits.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                  child: Text(
                    'No habits yet. Add one to begin.',
                    style: text.bodyMedium,
                  ),
                ),
              for (final habit in habits) ...[
                HabitToggleTile(
                  key: ValueKey(habit.id),
                  habit: habit,
                  onChanged: (enabled) => _toggle(habit, enabled),
                  onEdit: () => _edit(habit),
                  onDelete: () => _delete(habit),
                ),
                const SizedBox(height: WinterSpacing.sm),
              ],
              Semantics(
                button: true,
                enabled: !setup.atHabitLimit,
                label: setup.atHabitLimit
                    ? 'Add Habit, unavailable: ${SetupHabitRules.maxHabits} '
                          'habits is the limit'
                    : 'Add Habit',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  onPressed: setup.atHabitLimit ? null : () => _add(setup),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Habit'),
                ),
              ),
              if (setup.atHabitLimit)
                Padding(
                  padding: const EdgeInsets.only(top: WinterSpacing.xs),
                  child: Text(
                    "You've reached ${SetupHabitRules.maxHabits} habits, the "
                    'most an Arc can have. Remove one to add another.',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.sm,
            WinterSpacing.lg,
            WinterSpacing.lg,
          ),
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
                label: session.isSeasonal
                    ? 'Join Seasonal Winter Arc'
                    : 'Start Winter Arc',
                busy: _starting,
                onPressed: setup.canStart ? _start : null,
              ),
              if (_startNote(setup) case final note?)
                Padding(
                  padding: const EdgeInsets.only(top: WinterSpacing.xs),
                  child: Text(
                    note,
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ),
              const SizedBox(height: WinterSpacing.xs),
              TextButton(
                onPressed: _starting ? null : _cancelSetup,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Cancel setup'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Why Start is unavailable, if it is.
  static String? _startNote(ArcSetup setup) => switch (setup.startState) {
    SetupStartState.seasonNotStarted =>
      'Season starts October 1. Your setup is saved until then.',
    SetupStartState.seasonEnded =>
      'This season has ended. Cancel this setup to choose a new Arc.',
    SetupStartState.ready =>
      setup.enabledCount == 0 ? 'Turn on at least one habit to start.' : null,
  };
}

/// "YOUR WINTER ARC": the kind, its dates, and where the season stands.
class _ArcHeader extends StatelessWidget {
  const _ArcHeader({
    required this.session,
    required this.state,
    required this.todayDay,
  });

  final WinterArcSession session;
  final SetupStartState state;

  /// Today's day number in the season (seasonal only).
  final int todayDay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final kind = session.isSeasonal
        ? 'Seasonal · ${arcDateRange(session)}'
        : 'Rolling 92-Day';
    final detail = switch ((session.kind, state)) {
      (ArcKind.rolling92, _) =>
        '${WinterArcRules.lengthInDays} days from the day you press Start.',
      (_, SetupStartState.seasonNotStarted) =>
        'Preseason. The season starts October 1.',
      (_, SetupStartState.seasonEnded) => 'This season has ended.',
      (_, SetupStartState.ready) =>
        todayDay == 1
            ? 'The season starts today: Day 1 of '
                  '${WinterArcRules.lengthInDays}.'
            : 'The season is on Day $todayDay of '
                  '${WinterArcRules.lengthInDays}. Join now and start on '
                  'Day $todayDay; earlier days won\'t count against you.',
    };
    return Semantics(
      container: true,
      label: 'Your Winter Arc. $kind. $detail',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR WINTER ARC',
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text(kind, style: text.titleLarge),
          Text(
            detail,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
