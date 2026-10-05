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
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_card.dart';
import '../../shared/winter_scene/scene_progress.dart';
import '../../shared/winter_scene/winter_scene.dart';
import '../achievements/widgets/trophy_button.dart';
import 'journey_controller.dart';
import 'widgets/journey_day_style.dart';
import 'widgets/journey_marker.dart';
import 'widgets/journey_path.dart';

/// Journey v2: the arc's days as a climb up the mountain, from stored
/// history. Without [sessionId] it shows the active arc (the Journey tab);
/// with one, that arc from Arc History, read-only.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key, this.sessionId});

  final int? sessionId;

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // A historical arc never changes; only the active arc's Journey
        // re-reads on resume.
        if (widget.sessionId == null) ref.invalidate(journeyControllerProvider);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _retry() => switch (widget.sessionId) {
    null => ref.invalidate(journeyControllerProvider),
    final id => ref.invalidate(arcJourneyProvider(id)),
  };

  @override
  Widget build(BuildContext context) {
    final journey = switch (widget.sessionId) {
      null => ref.watch(journeyControllerProvider),
      final id => ref.watch(arcJourneyProvider(id)),
    };
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
              _ when value != null => LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // With large text (or a short, landscape screen) the
                    // header scrolls within at most half the height, so the
                    // path always keeps room.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight / 2,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: _Header(
                          journey: value,
                          historical: widget.sessionId != null,
                        ),
                      ),
                    ),
                    Expanded(child: JourneyPath(journey: value)),
                  ],
                ),
              ),
              AsyncError(:final error, :final stackTrace) => FailureView(
                failure: toAppFailure(error, stackTrace),
                onRetry: _retry,
              ),
              _ => const LoadingView(),
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
  const _Header({required this.journey, required this.historical});

  final JourneyOverview journey;

  /// Shown from Arc History: names the arc by its dates.
  final bool historical;

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
                onPressed: () => _Legend.show(
                  context,
                  showNotJoined: journey.session.joinedLate,
                ),
                icon: const Icon(Icons.info_outline_rounded),
              ),
              TrophyButton(sessionId: historical ? journey.session.id : null),
            ],
          ),
          if (historical || journey.session.isSeasonal)
            Text(
              arcHeading(journey.session),
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          Text(dayTitle(journey.position), style: text.headlineSmall),
          if (journey.session.joinedLate)
            Text(
              'Joined on Day ${journey.session.joinDayNumber}. Earlier days '
              "don't count against you.",
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          Text(
            '${chapterTitle(JourneyChapter.forDay(day))} · '
            '${milestoneTitle(ArcMilestone.forDay(day))}',
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: WinterSpacing.sm),
          WinterCard(
            padding: const EdgeInsets.fromLTRB(
              WinterSpacing.md,
              WinterSpacing.sm,
              WinterSpacing.md,
              WinterSpacing.sm + 2,
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
  const _Legend({required this.showNotJoined});

  /// Include the "before you joined" marker of a seasonal arc joined late.
  final bool showNotJoined;

  static Future<void> show(
    BuildContext context, {
    required bool showNotJoined,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.winter.surface,
    builder: (_) => _Legend(showNotJoined: showNotJoined),
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
              if (showNotJoined || state != JourneyDayState.notJoined)
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
