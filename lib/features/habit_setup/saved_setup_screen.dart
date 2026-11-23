import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/arc_status.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import '../focus_guard/focus_guard_entry.dart';
import 'cancel_setup.dart';
import 'habit_setup_controller.dart';
import 'setup_labels.dart';
import 'setup_navigation.dart';
import 'widgets/start_button.dart';

/// The saved-setup hub (`/setup/saved`): the home of an arc in setup. The
/// app opens here whenever a setup exists (launch, process death, a
/// restore), and Save for Later lands here.
///
/// Reads only. Start Challenge opens Review Setup (it never starts the
/// arc itself), Review Setup opens the same review, Continue Editing opens
/// Habit Setup over the hub. Cancel setup is the editor's own dialog and
/// deletion. System back leaves the app.
class SavedSetupScreen extends ConsumerStatefulWidget {
  const SavedSetupScreen({super.key});

  @override
  ConsumerState<SavedSetupScreen> createState() => _SavedSetupScreenState();
}

class _SavedSetupScreenState extends ConsumerState<SavedSetupScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Whether it can start depends on today's date (a season opens on
    // 1 October and ends on 31 December).
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) ref.read(habitSetupControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(habitSetupControllerProvider);
    ref.listen(dayChangedProvider, (_, _) => _refresh());
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: switch (setup) {
            AsyncData(:final value) => _Hub(setup: value),
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

class _Hub extends ConsumerWidget {
  const _Hub({required this.setup});

  final ArcSetup setup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final empty = setup.habits.isEmpty;
    final reviewable = setup.blocker != SetupBlocker.seasonEnded;
    final hasHistory =
        ref.watch(arcResolutionProvider)?.latestCompleted != null;
    final focusGuard = ref.watch(focusGuardEntryProvider).value;

    void edit() => context.push(AppRoutes.habitSetup);
    void review() => context.push(AppRoutes.reviewSetup);

    final start = StartButton(
      label: SetupLabels.startChallenge,
      blocked: SetupLabels.blocked(setup),
      onPressed: review,
    );
    final reviewButton = OutlinedButton(
      onPressed: reviewable ? review : null,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: const Text(SetupLabels.reviewSetup),
    );
    final continueEditing = empty
        ? PrimaryButton(label: SetupLabels.continueEditing, onPressed: edit)
        : OutlinedButton(
            onPressed: edit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text(SetupLabels.continueEditing),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = SetupLayout.side(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            WinterSpacing.lg,
            side,
            WinterSpacing.lg,
          ),
          children: [
            ExcludeSemantics(
              child: Text(
                SetupLabels.hubEyebrow,
                style: text.labelLarge?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: WinterSpacing.xs),
            Semantics(
              header: true,
              child: Text(SetupLabels.hubTitle, style: text.headlineMedium),
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(SetupLabels.hubSummary(setup), style: text.titleMedium),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              SetupLabels.whenItStarts(setup),
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
            if (empty) ...[
              const SizedBox(height: WinterSpacing.sm),
              Text(SetupLabels.addAHabit, style: text.bodyLarge),
            ],
            const SizedBox(height: WinterSpacing.lg),
            // Zero habits: Continue Editing is the filled action.
            if (empty) ...[
              continueEditing,
              const SizedBox(height: WinterSpacing.sm),
              start,
              const SizedBox(height: WinterSpacing.sm),
              reviewButton,
            ] else ...[
              start,
              const SizedBox(height: WinterSpacing.sm),
              reviewButton,
              const SizedBox(height: WinterSpacing.sm),
              continueEditing,
            ],
            const SizedBox(height: WinterSpacing.xl),
            Text(
              SetupLabels.settingsHeading,
              style: text.labelLarge?.copyWith(
                color: colors.accentSecondary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: WinterSpacing.xs),
            _Link(
              icon: Icons.notifications_none_rounded,
              label: 'Reminders',
              route: AppRoutes.reminders,
            ),
            _Link(
              icon: Icons.volume_up_outlined,
              label: 'Sound & Feedback',
              route: AppRoutes.soundSettings,
            ),
            _Link(
              icon: Icons.save_alt_rounded,
              label: 'Data & Backup',
              route: AppRoutes.dataBackup,
            ),
            // Android only, and only once its support is known.
            if (focusGuard != null && focusGuard.supported)
              _Link(
                icon: Icons.shield_outlined,
                label: 'Focus Guard',
                route: AppRoutes.focusGuard,
              ),
            // Only with a finished Arc to show.
            if (hasHistory)
              _Link(
                icon: Icons.history_rounded,
                label: 'Arc History',
                route: AppRoutes.arcs,
              ),
            _Link(
              icon: Icons.info_outline_rounded,
              label: 'About NextRep',
              route: AppRoutes.about,
            ),
            const SizedBox(height: WinterSpacing.lg),
            Center(
              child: TextButton(
                onPressed: () => confirmCancelSetup(context, ref),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text(SetupLabels.cancelSetup),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A settings or history page, opened over the hub (back returns here).
class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => context.push(route),
    style: TextButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      alignment: AlignmentDirectional.centerStart,
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: WinterSpacing.sm),
        Expanded(child: Text(label)),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}
