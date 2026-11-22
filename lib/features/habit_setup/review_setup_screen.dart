import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/reminder/reminder_preferences.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import 'habit_setup_controller.dart';
import 'setup_labels.dart';
import 'setup_navigation.dart';
import 'widgets/start_button.dart';

/// The stored reminder preferences, read for Review Setup's reminder line.
/// A plain read: nothing is scheduled or asked for.
final setupReminderPreferencesProvider =
    FutureProvider.autoDispose<ReminderPreferences>(
      (ref) => ref.watch(reminderPreferencesRepositoryProvider).load(),
    );

/// Review Setup (`/setup/review`): the arc in setup as it will start,
/// read-only. The kind and its dates, the habits that are on in their
/// order with their goals and Minimum Day goals, the habits that are off,
/// and the reminders.
///
/// Opening it, scrolling, refreshing or leaving writes nothing. Continue to
/// Start opens Confirm & Start (it never starts the arc itself); it is
/// unavailable, with the reason, whenever the domain says the arc can't
/// start today.
class ReviewSetupScreen extends ConsumerStatefulWidget {
  const ReviewSetupScreen({super.key, this.fromEditor = false});

  /// Opened from Habit Setup (which is beneath it): Edit Setup goes back
  /// to it instead of opening another editor.
  final bool fromEditor;

  @override
  ConsumerState<ReviewSetupScreen> createState() => _ReviewSetupScreenState();
}

class _ReviewSetupScreenState extends ConsumerState<ReviewSetupScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    // The setup as stored now, and today's date (not an older snapshot).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.read(habitSetupControllerProvider.notifier).refresh();
    ref.invalidate(setupReminderPreferencesProvider);
  }

  void _edit() {
    if (widget.fromEditor && context.canPop()) {
      context.pop();
    } else {
      context.pushReplacement(AppRoutes.habitSetup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(habitSetupControllerProvider);
    ref.listen(dayChangedProvider, (_, _) => _refresh());
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: BackButton(
          onPressed: () => setupBack(context, fallback: AppRoutes.savedSetup),
        ),
        // The title is the page's first heading instead, so it can wrap at
        // large text sizes.
      ),
      extendBodyBehindAppBar: false,
      body: WinterBackground(
        child: SafeArea(
          top: false,
          child: switch (setup) {
            AsyncData(:final value) => _Review(
              setup: value,
              onContinue: () => context.push(AppRoutes.confirmStart),
              onEdit: _edit,
              onSave: () => saveForLater(context),
            ),
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
}

class _Review extends ConsumerWidget {
  const _Review({
    required this.setup,
    required this.onContinue,
    required this.onEdit,
    required this.onSave,
  });

  final ArcSetup setup;
  final VoidCallback onContinue;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final on = setup.enabledHabits;
    final off = setup.disabledHabits;
    final empty = setup.habits.isEmpty;
    final reminders = ref.watch(setupReminderPreferencesProvider);
    final session = setup.session;

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(
        top: WinterSpacing.lg,
        bottom: WinterSpacing.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: text.labelLarge?.copyWith(
            color: colors.accentSecondary,
            letterSpacing: 2,
          ),
        ),
      ),
    );

    final edit = empty
        ? PrimaryButton(label: SetupLabels.editSetup, onPressed: onEdit)
        : OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text(SetupLabels.editSetup),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = SetupLayout.side(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            WinterSpacing.sm,
            side,
            WinterSpacing.lg,
          ),
          children: [
            Semantics(
              header: true,
              child: Text(SetupLabels.reviewSetup, style: text.headlineMedium),
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(SetupLabels.kindTitle(session), style: text.titleLarge),
            Text(
              SetupLabels.reviewDates(setup),
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            if (session.isSeasonal)
              Text(
                SetupLabels.whenItStarts(setup),
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            heading(SetupLabels.habitsHeading(on.length)),
            if (empty)
              Text(SetupLabels.noHabitsYet, style: text.bodyLarge)
            else if (on.isEmpty)
              Text(SetupLabels.noneOn, style: text.bodyLarge),
            for (final (i, habit) in on.indexed)
              _HabitRow(habit: habit, position: i + 1),
            if (off.isNotEmpty) ...[
              heading(SetupLabels.offHeading(off.length)),
              for (final habit in off) _HabitRow(habit: habit),
            ],
            const SizedBox(height: WinterSpacing.lg),
            Text(switch (reminders) {
              AsyncData(:final value) => SetupLabels.reminders(value),
              AsyncError() => SetupLabels.remindersUnknown,
              _ => ' ',
            }, style: text.bodyMedium),
            Text(
              SetupLabels.remindersWait,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: WinterSpacing.lg),
            StartButton(
              label: SetupLabels.continueToStart,
              blocked: SetupLabels.blocked(setup),
              onPressed: onContinue,
            ),
            const SizedBox(height: WinterSpacing.sm),
            edit,
            const SizedBox(height: WinterSpacing.sm),
            OutlinedButton(
              onPressed: onSave,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(SetupLabels.saveForLater),
            ),
          ],
        );
      },
    );
  }
}

/// One habit: its place (when on), icon, name and goals. One accessible
/// node: "1. Water. 8 glasses. Minimum 4."
class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit, this.position});

  final Habit habit;
  final int? position;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final stacked = SetupLayout.largeText(context);
    final goals = Text(
      SetupLabels.goals(habit),
      style: text.bodyMedium?.copyWith(color: colors.textSecondary),
    );
    final title = Text(habit.title, style: text.titleMedium);
    return Semantics(
      container: true,
      label: SetupLabels.reviewHabit(habit, position: position),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                position == null ? '' : '$position',
                style: text.titleMedium,
              ),
            ),
            HabitIcon(iconKey: habit.iconKey),
            const SizedBox(width: WinterSpacing.sm),
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, goals],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: WinterSpacing.sm),
                        Flexible(child: goals),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
