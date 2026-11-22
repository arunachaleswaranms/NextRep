import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/habit/setup_habit_rules.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/feedback/haptics.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../about/about_entry.dart';
import 'cancel_setup.dart';
import 'habit_setup_controller.dart';
import 'setup_labels.dart';
import 'setup_navigation.dart';
import 'widgets/add_habit_sheet.dart';
import 'widgets/habit_form_sheet.dart';
import 'widgets/habit_toggle_tile.dart';
import 'widgets/start_button.dart';

/// Habit Setup: which Arc this is, its habits (switch on or off, put in
/// order, change, remove, add from a template or create your own), then
/// Review & Start or Save for Later.
///
/// Everything here edits the arc's baseline directly: nothing has happened
/// yet, so there's no history to protect. Once started, habits can only be
/// renamed, re-targeted from the next day or switched off, and their order
/// is fixed. Nothing here starts the arc: Review & Start opens Review
/// Setup, and only Confirm & Start (after it) starts.
class HabitSetupScreen extends ConsumerStatefulWidget {
  const HabitSetupScreen({super.key});

  @override
  ConsumerState<HabitSetupScreen> createState() => _HabitSetupScreenState();
}

class _HabitSetupScreenState extends ConsumerState<HabitSetupScreen> {
  late final AppLifecycleListener _lifecycle;

  /// A card is being dragged: the menus, switches and moves wait.
  bool _dragging = false;

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
    if (_dragging) return;
    final draft = await HabitFormSheet.show(context, habit: habit);
    if (draft == null || !mounted) return;
    final result = await _controller.edit(habit.id, draft);
    if (result case ActionFailure(:final failure)) _showFailure(failure);
  }

  Future<void> _delete(Habit habit) async {
    if (_dragging) return;
    final result = await _controller.delete(habit.id);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        _showSnack('${habit.title} removed');
      case ActionFailure(:final failure):
        _showFailure(failure);
    }
  }

  /// Moves [habit] to [index]: a drop, the menu and the screen-reader
  /// actions all come here, and all use the one stored operation. The new
  /// position is announced once it is stored; a failed save puts the
  /// stored order back and says so.
  Future<void> _move(Habit habit, int index) async {
    final view = View.of(context);
    final direction = Directionality.of(context);
    final result = await _controller.move(habit.id, index);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        final stored = ref.read(habitSetupControllerProvider).value?.habits;
        final at = stored?.indexWhere((h) => h.id == habit.id) ?? -1;
        if (stored == null || at < 0) return;
        SemanticsService.sendAnnouncement(
          view,
          SetupLabels.moved(habit, index: at, of: stored.length),
          direction,
        );
      case ActionFailure():
        _showSnack(SetupLabels.reorderFailed);
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
    // The same, with the app left open across midnight.
    ref.listen(dayChangedProvider, (_, _) => _controller.refresh());
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (setup) {
            AsyncData(:final value) => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(habitSetupControllerProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ArcSetup setup) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final habits = setup.habits;
    final count = habits.length;
    // The actions stay pinned under the list when there is room; with large
    // text or a short screen they follow the list, so it keeps its space.
    final pinned =
        !SetupLayout.largeText(context) &&
        MediaQuery.sizeOf(context).height >= 600;
    final actions = _Actions(
      setup: setup,
      onReview: () => context.push(AppRoutes.reviewFromEditor),
      onSave: () => saveForLater(context),
      onCancel: () => confirmCancelSetup(context, ref),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = SetupLayout.side(constraints.maxWidth);
        EdgeInsets pad(double top, double bottom) =>
            EdgeInsets.fromLTRB(side, top, side, bottom);
        final list = CustomScrollView(
          slivers: [
            SliverPadding(
              padding: pad(WinterSpacing.lg, 0),
              sliver: SliverList.list(
                children: [
                  _ArcHeader(setup: setup),
                  const SizedBox(height: WinterSpacing.lg),
                  Text('Choose your habits', style: text.headlineMedium),
                  const SizedBox(height: WinterSpacing.sm),
                  Text(
                    'Pick the small daily actions you will show up for.',
                    style: text.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (count > 1)
                    Text(
                      SetupLabels.reorderHint,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
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
                ],
              ),
            ),
            SliverPadding(
              padding: pad(0, 0),
              sliver: SliverReorderableList(
                itemCount: count,
                onReorderStart: (_) {
                  Haptics.reorderGrip();
                  setState(() => _dragging = true);
                },
                onReorderEnd: (_) {
                  Haptics.reorderGrip();
                  setState(() => _dragging = false);
                },
                // Dropped where it was: nothing to write.
                onReorderItem: (from, to) {
                  if (from != to) _move(habits[from], to);
                },
                proxyDecorator: (child, index, animation) =>
                    _Lifted(animation: animation, child: child),
                itemBuilder: (context, index) {
                  final habit = habits[index];
                  return Padding(
                    // The habit's id, never its index, is its identity.
                    key: ValueKey(habit.id),
                    padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
                    child: HabitToggleTile(
                      habit: habit,
                      index: index,
                      count: count,
                      movable: true,
                      reorderable: count > 1,
                      dragging: _dragging,
                      onMoveUp: index == 0
                          ? null
                          : () => _move(habit, index - 1),
                      onMoveDown: index == count - 1
                          ? null
                          : () => _move(habit, index + 1),
                      onChanged: (enabled) => _toggle(habit, enabled),
                      onEdit: () => _edit(habit),
                      onDelete: () => _delete(habit),
                    ),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: pad(0, WinterSpacing.md),
              sliver: SliverList.list(
                children: [
                  _AddHabitButton(setup: setup, onAdd: () => _add(setup)),
                  if (setup.atHabitLimit)
                    Padding(
                      padding: const EdgeInsets.only(top: WinterSpacing.xs),
                      child: Text(
                        "You've reached ${SetupHabitRules.maxHabits} habits, "
                        'the most an Arc can have. Remove one to add another.',
                        style: text.bodySmall,
                      ),
                    ),
                  const SizedBox(height: WinterSpacing.md),
                  if (!pinned) ...[
                    actions,
                    const SizedBox(height: WinterSpacing.sm),
                  ],
                  // Setup is saved as it is edited, so About can open on top.
                  const Center(child: AboutLink()),
                ],
              ),
            ),
          ],
        );
        if (!pinned) return list;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            Padding(
              padding: pad(WinterSpacing.sm, WinterSpacing.lg),
              child: actions,
            ),
          ],
        );
      },
    );
  }
}

/// The lifted card while it is dragged: elevation and a 1.02 scale, eased
/// in, or at once with reduced motion.
class _Lifted extends StatelessWidget {
  const _Lifted({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = context.motion.reduced;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = reduced ? 1.0 : Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            type: MaterialType.transparency,
            elevation: 8 * t,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(WinterRadii.card),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _AddHabitButton extends StatelessWidget {
  const _AddHabitButton({required this.setup, required this.onAdd});

  final ArcSetup setup;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: !setup.atHabitLimit,
    label: setup.atHabitLimit
        ? 'Add Habit, unavailable: ${SetupHabitRules.maxHabits} '
              'habits is the limit'
        : 'Add Habit',
    onTap: setup.atHabitLimit ? null : onAdd,
    excludeSemantics: true,
    child: OutlinedButton.icon(
      onPressed: setup.atHabitLimit ? null : onAdd,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add Habit'),
    ),
  );
}

/// "N habits selected", Review & Start (with the reason it's unavailable),
/// Save for Later and Cancel setup.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.setup,
    required this.onReview,
    required this.onSave,
    required this.onCancel,
  });

  final ArcSetup setup;
  final VoidCallback onReview;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = setup.enabledCount;
    final blocked = SetupLabels.blocked(setup);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selected == 1 ? '1 habit selected' : '$selected habits selected',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: WinterSpacing.sm),
        StartButton(
          label: SetupLabels.reviewAndStart,
          blocked: blocked,
          onPressed: setup.canStart ? onReview : null,
        ),
        const SizedBox(height: WinterSpacing.sm),
        OutlinedButton(
          onPressed: onSave,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text(SetupLabels.saveForLater),
        ),
        const SizedBox(height: WinterSpacing.xs),
        Center(
          child: TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(SetupLabels.cancelSetup),
          ),
        ),
      ],
    );
  }
}

/// "YOUR WINTER ARC": the kind, its dates, and where the season stands.
class _ArcHeader extends StatelessWidget {
  const _ArcHeader({required this.setup});

  final ArcSetup setup;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final session = setup.session;
    final kind = session.isSeasonal
        ? 'Seasonal · ${arcDateRange(session)}'
        : 'Rolling 92-Day';
    final detail = switch ((session.kind, setup.startState)) {
      (ArcKind.rolling92, _) =>
        'Your ${WinterArcRules.lengthInDays}-day Arc begins when you confirm '
            'the start.',
      (_, SetupStartState.seasonNotStarted) =>
        'Preseason. The season starts October 1.',
      (_, SetupStartState.seasonEnded) => 'This season has ended.',
      (_, SetupStartState.ready) =>
        setup.todayDay == 1
            ? 'The season starts today: Day 1 of '
                  '${WinterArcRules.lengthInDays}.'
            : 'The season is on Day ${setup.todayDay} of '
                  '${WinterArcRules.lengthInDays}. Join now and start on '
                  'Day ${setup.todayDay}; earlier days won\'t count against '
                  'you.',
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
