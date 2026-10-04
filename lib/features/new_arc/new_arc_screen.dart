import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/habit/habit.dart';
import '../../domain/winter_arc/winter_arc_service.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/formatting/habit_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'new_arc_controller.dart';

/// Starts a Winter Arc: first the kind of Arc (Rolling 92-Day or the
/// Seasonal Winter Arc), then, for a user who has finished an arc, which
/// habits to begin with (reuse the last setup or start fresh), then Habit
/// Setup and Start as usual. First-time users come here from onboarding;
/// returning users from their last summary.
///
/// The Arc kind and the habit baseline are separate choices: reusing a
/// seasonal arc's habits for a rolling arc (or the other way round) only
/// copies the habits.
class NewArcScreen extends ConsumerStatefulWidget {
  const NewArcScreen({super.key});

  @override
  ConsumerState<NewArcScreen> createState() => _NewArcScreenState();
}

class _NewArcScreenState extends ConsumerState<NewArcScreen> {
  /// The kind picked in step 1; null while choosing it.
  ArcKind? _kind;

  Future<void> _create(ArcKind kind, NewArcBaseline baseline) async {
    final result = await ref
        .read(newArcControllerProvider.notifier)
        .start(baseline, kind: kind);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        context.go(AppRoutes.habitSetup);
      case ActionFailure(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
    }
  }

  void _chooseKind(ArcKind kind, {required bool returning}) {
    // Without a finished arc there's nothing to reuse: start from the
    // starter habits straight away.
    if (!returning) {
      _create(kind, NewArcBaseline.fresh);
      return;
    }
    setState(() => _kind = kind);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(newArcControllerProvider);
    final reusable = ref.watch(reusableHabitsProvider);
    final season = ref.watch(seasonAvailabilityProvider);
    final returning = reusable.value != null;
    final kind = _kind;
    return PopScope(
      canPop: kind == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _kind = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(returning ? 'New Winter Arc' : 'Choose your Arc'),
          backgroundColor: Colors.transparent,
        ),
        extendBodyBehindAppBar: true,
        body: WinterBackground(
          child: SafeArea(
            child: switch (reusable) {
              AsyncLoading() when !reusable.hasValue => const Center(
                child: CircularProgressIndicator(),
              ),
              // Without knowing whether there's an arc to reuse, a returning
              // user could be sent down the first-time path.
              AsyncError(:final error, :final stackTrace) => FailureView(
                failure: toAppFailure(error, stackTrace),
                onRetry: () => ref.invalidate(reusableHabitsProvider),
              ),
              _ when kind == null => _KindStep(
                returning: returning,
                season: season,
                busy: busy != null,
                onChoose: (kind) => _chooseKind(kind, returning: returning),
              ),
              _ => _BaselineStep(
                kind: kind,
                season: season,
                busy: busy,
                reusable: reusable.value,
                onChoose: (baseline) => _create(kind, baseline),
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Step 1: Rolling or Seasonal.
class _KindStep extends StatelessWidget {
  const _KindStep({
    required this.returning,
    required this.season,
    required this.busy,
    required this.onChoose,
  });

  final bool returning;
  final SeasonAvailability season;
  final bool busy;
  final ValueChanged<ArcKind> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    final seasonal = _seasonalCopy(season);
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.lg),
      children: [
        Text(
          returning ? 'Your next climb' : 'Your first climb',
          style: text.headlineMedium,
        ),
        const SizedBox(height: WinterSpacing.sm),
        Text(
          returning
              ? 'Pick how your Winter Arc runs. Your finished arcs stay in '
                    'Arc History.'
              : 'Pick how your Winter Arc runs. You can change your habits '
                    'before you start.',
          style: text.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WinterSpacing.lg),
        _Choice(
          icon: Icons.all_inclusive_rounded,
          title: 'Rolling 92-Day Arc',
          description:
              "Start whenever you're ready. 92 days from the day you begin.",
          enabled: !busy,
          onTap: () => onChoose(ArcKind.rolling92),
        ),
        const SizedBox(height: WinterSpacing.md),
        _Choice(
          icon: Icons.ac_unit_rounded,
          title: 'Seasonal Winter Arc',
          description: seasonal.description,
          status: seasonal.status,
          enabled: !busy && season.canSetUp,
          onTap: () => onChoose(ArcKind.seasonalWinter),
        ),
      ],
    );
  }

  static ({String description, String status}) _seasonalCopy(
    SeasonAvailability season,
  ) {
    const window = 'October 1 – December 31.';
    return switch (season.phase) {
      SeasonPhase.closed => (
        description: '$window One shared season, every year.',
        status: 'Preseason opens September 1',
      ),
      SeasonPhase.preseason => (
        description: '$window Set up your habits now.',
        status: 'Preseason · the season starts October 1',
      ),
      SeasonPhase.inSeason => (
        description: '$window Join the season already in progress.',
        status: 'In season · ${season.year}',
      ),
    };
  }
}

/// Step 2 for returning users: which habits to begin with.
class _BaselineStep extends StatelessWidget {
  const _BaselineStep({
    required this.kind,
    required this.season,
    required this.busy,
    required this.reusable,
    required this.onChoose,
  });

  final ArcKind kind;
  final SeasonAvailability season;
  final NewArcBaseline? busy;
  final List<Habit>? reusable;
  final ValueChanged<NewArcBaseline> onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.winter;
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.lg),
      children: [
        Text(
          kind.isSeasonal ? 'Seasonal Winter Arc' : 'Rolling 92-Day Arc',
          style: text.labelLarge?.copyWith(
            color: colors.accentSecondary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: WinterSpacing.xs),
        Text('Choose your habits', style: text.headlineMedium),
        const SizedBox(height: WinterSpacing.sm),
        Text(
          kind.isSeasonal
              ? 'October 1 – December 31, ${season.year}.'
              : '${WinterArcRules.lengthInDays} days, starting the day you '
                    'press Start.',
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
          enabled: busy == null && (reusable?.isNotEmpty ?? false),
          preview: reusable,
          onTap: () => onChoose(NewArcBaseline.reuseLast),
        ),
        const SizedBox(height: WinterSpacing.md),
        _Choice(
          icon: Icons.ac_unit_rounded,
          title: 'Start fresh',
          description: 'Begin again from the starter habits.',
          busy: busy == NewArcBaseline.fresh,
          enabled: busy == null,
          onTap: () => onChoose(NewArcBaseline.fresh),
        ),
        const SizedBox(height: WinterSpacing.md),
        Text(
          'You can add, change or remove habits before you start.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onTap,
    this.busy = false,
    this.status,
    this.preview,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  /// Availability, e.g. "Preseason opens September 1".
  final String? status;

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
        ?status,
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
                    if (status case final status?) ...[
                      const SizedBox(height: WinterSpacing.xs),
                      Text(
                        status,
                        style: text.labelLarge?.copyWith(
                          color: colors.accentSecondary,
                        ),
                      ),
                    ],
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
