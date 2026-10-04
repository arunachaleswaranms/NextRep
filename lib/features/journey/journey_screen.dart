import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../../domain/journey/arc_milestones.dart';
import '../../domain/journey/journey_day.dart';
import '../../domain/journey/journey_overview.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/level_bar.dart';
import '../../shared/winter_scene/scene_progress.dart';
import '../../shared/winter_scene/winter_scene.dart';
import '../achievements/widgets/trophy_button.dart';
import 'journey_controller.dart';
import 'widgets/journey_day_style.dart';
import 'widgets/journey_marker.dart';
import 'widgets/journey_path.dart';

/// Journey v2: the arc's days as a climb up the mountain, from stored
/// history. Also shown, read-only, for a completed arc.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(journeyControllerProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journey = ref.watch(journeyControllerProvider);
    final colors = context.winter;
    // Keep showing the previous Journey while a refresh is loading, so the
    // path (and its scroll position) is not torn down.
    final value = journey.hasError ? null : journey.value;
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (value != null) ...[
            WinterScene(scene: _backdrop(value), showTrail: false, maxSnow: 30),
            // Dims the world so the path and its labels stay readable.
            ColoredBox(color: colors.background.withValues(alpha: 0.45)),
          ],
          SafeArea(
            bottom: false,
            child: switch (journey) {
              _ when value != null => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(journey: value),
                  Expanded(child: JourneyPath(journey: value)),
                ],
              ),
              AsyncError(:final error, :final stackTrace) => FailureView(
                failure: toAppFailure(error, stackTrace),
                onRetry: () => ref.invalidate(journeyControllerProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  static SceneProgress _backdrop(JourneyOverview journey) => SceneProgress(
    dayNumber: switch (journey.position) {
      ArcInProgress(:final dayNumber) => dayNumber,
      ArcNotStarted() => 1,
      ArcFinished(:final totalDays) => totalDays,
    },
    totalDays: journey.position.totalDays,
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.journey});

  final JourneyOverview journey;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final perfect = journey.perfectDays;
    final day = switch (journey.position) {
      ArcInProgress(:final dayNumber) => dayNumber,
      ArcNotStarted() => 1,
      ArcFinished(:final totalDays) => totalDays,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WinterSpacing.md,
        WinterSpacing.xs,
        WinterSpacing.md,
        WinterSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (context.canPop()) ...[
                const BackButton(),
                const SizedBox(width: WinterSpacing.xs),
              ],
              Expanded(
                child: Text(
                  'JOURNEY',
                  style: text.labelLarge?.copyWith(
                    color: colors.accentSecondary,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Legend',
                onPressed: () => _Legend.show(context),
                icon: const Icon(Icons.info_outline_rounded),
              ),
              const TrophyButton(),
            ],
          ),
          Text(dayTitle(journey.position), style: text.headlineSmall),
          Text(
            '${chapterTitle(JourneyChapter.forDay(day))} · '
            '${milestoneTitle(ArcMilestone.forDay(day))}',
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: WinterSpacing.sm),
          Container(
            padding: const EdgeInsets.fromLTRB(
              WinterSpacing.md,
              WinterSpacing.sm,
              WinterSpacing.md,
              WinterSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: colors.glass,
              borderRadius: BorderRadius.circular(WinterRadii.card),
              border: Border.all(color: colors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Stat(label: 'Perfect Days', value: '${perfect.total}'),
                    _Stat(
                      label: 'Perfect streak',
                      value: '${perfect.streak.current}',
                    ),
                    _Stat(label: 'Best', value: '${perfect.streak.best}'),
                  ],
                ),
                const SizedBox(height: WinterSpacing.sm),
                LevelBar(level: journey.level),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: text.titleLarge),
          Text(label, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// What each marker means; shapes and icons, not only colours.
class _Legend extends StatelessWidget {
  const _Legend();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.winter.surface,
    builder: (_) => const _Legend(),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sample = LocalDate(2026, 10, 7);
    return SafeArea(
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
            Text('Legend', style: text.headlineSmall),
            const SizedBox(height: WinterSpacing.sm),
            for (final state in JourneyDayState.values)
              Row(
                children: [
                  ExcludeSemantics(
                    child: JourneyMarker(
                      day: JourneyDay(
                        dayNumber: 7,
                        date: sample,
                        state: state,
                        isToday: state == JourneyDayState.today,
                        xpEarned: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: WinterSpacing.sm),
                  Expanded(child: Text(state.label, style: text.bodyLarge)),
                ],
              ),
            const SizedBox(height: WinterSpacing.sm),
            Text(
              'Tap any day up to today for its details. Flags mark '
              'milestones of the climb.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
