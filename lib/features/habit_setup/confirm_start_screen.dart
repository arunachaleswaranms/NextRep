import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/arc_refresh.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'habit_setup_controller.dart';
import 'setup_labels.dart';
import 'setup_navigation.dart';
import 'widgets/start_button.dart';

/// Confirm & Start (`/setup/confirm`): the only screen whose action starts
/// an arc in setup. Reached from Review Setup.
///
/// It shows exactly what starting does, from one snapshot of the setup and
/// today's date ([ArcSetup.today], re-read on entry, on resume and at
/// midnight): Rolling, Day 1 is today and Day 92 is today + 91; Seasonal,
/// the season keeps 1 October – 31 December and the user joins today on
/// its day number. The start is [WinterArcService.startWinterArc] with the
/// date shown: if today is another date by the time it runs, nothing
/// starts and the new dates are shown. Back and Save for Later start
/// nothing. Pressing twice starts once.
class ConfirmStartScreen extends ConsumerStatefulWidget {
  const ConfirmStartScreen({super.key});

  @override
  ConsumerState<ConfirmStartScreen> createState() => _ConfirmStartScreenState();
}

class _ConfirmStartScreenState extends ConsumerState<ConfirmStartScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted && !_starting) {
      ref.read(habitSetupControllerProvider.notifier).refresh();
    }
  }

  Future<void> _confirm(ArcSetup setup) async {
    if (_starting) return;
    setState(() => _starting = true);
    final result = await ref
        .read(habitSetupControllerProvider.notifier)
        .start(confirmedOn: setup.today);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        context.go(AppRoutes.today);
      case ActionFailure(:final failure):
        setState(() => _starting = false);
        // A domain refusal says why (the screen has re-read the setup);
        // a storage failure changed nothing.
        final message = failure is DomainFailure
            ? userMessageFor(failure)
            : SetupLabels.startFailed;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(habitSetupControllerProvider);
    ref.listen(dayChangedProvider, (_, _) => _refresh());
    return PopScope(
      // Nothing to leave behind while the start is being written.
      canPop: !_starting,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: BackButton(
            onPressed: _starting
                ? null
                : () => setupBack(context, fallback: AppRoutes.reviewSetup),
          ),
        ),
        body: WinterBackground(
          child: SafeArea(
            top: false,
            child: switch (setup) {
              AsyncData(:final value) => _Confirm(
                setup: value,
                starting: _starting,
                onConfirm: () => _confirm(value),
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
      ),
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.setup,
    required this.starting,
    required this.onConfirm,
    required this.onSave,
  });

  final ArcSetup setup;
  final bool starting;
  final VoidCallback onConfirm;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final session = setup.session;
    // The arc as ArcStartRules would start it today; null when it can't.
    final preview = setup.startPreview;
    final secondary = text.bodyLarge?.copyWith(color: colors.textSecondary);

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
            // Keyboard focus starts here, not on the start button; Enter
            // does nothing until a button is chosen.
            Focus(
              autofocus: true,
              child: Semantics(
                header: true,
                child: Text(
                  SetupLabels.confirmTitle,
                  style: text.headlineMedium,
                ),
              ),
            ),
            const SizedBox(height: WinterSpacing.md),
            Text(SetupLabels.confirmSummary(setup), style: text.titleMedium),
            const SizedBox(height: WinterSpacing.md),
            if (preview != null) ...[
              _DateRow(
                label: 'Day 1',
                date: preview.startDate,
                today: setup.today,
              ),
              _DateRow(
                label: 'Day ${WinterArcRules.lengthInDays}',
                date: preview.endDate,
                today: setup.today,
              ),
              const SizedBox(height: WinterSpacing.md),
              if (session.isSeasonal) ...[
                Text(
                  SetupLabels.seasonalJoin(setup.todayDay),
                  style: text.titleMedium,
                ),
                Text(SetupLabels.seasonalConsequence(setup), style: secondary),
              ] else
                Text(SetupLabels.rollingConsequence, style: secondary),
            ],
            const SizedBox(height: WinterSpacing.lg),
            StartButton(
              label: SetupLabels.confirmButton(session),
              blocked: SetupLabels.blocked(setup),
              busy: starting,
              onPressed: onConfirm,
            ),
            // Clearly apart from the start (spec § 9.5: 24 dp).
            const SizedBox(height: WinterSpacing.lg),
            OutlinedButton(
              onPressed: starting ? null : onSave,
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

/// "Day 1    Today, Fri 13 Nov 2026", read as "Day 1: Today, Friday 13
/// November 2026". The label sits over the value above 1.3× text.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.today,
  });

  final String label;
  final LocalDate date;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isToday = date == today;
    final shown = isToday
        ? SetupLabels.todayDate(date)
        : SetupLabels.shortDate(date);
    final spoken =
        '$label: ${isToday ? 'Today, ' : ''}${SetupLabels.fullDate(date)}';
    final labelText = Text(
      label,
      style: text.titleMedium?.copyWith(color: context.winter.accentSecondary),
    );
    final value = Text(shown, style: text.titleMedium);
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
        child: SetupLayout.largeText(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, value],
              )
            : Row(
                children: [
                  SizedBox(width: 88, child: labelText),
                  Expanded(child: value),
                ],
              ),
      ),
    );
  }
}
