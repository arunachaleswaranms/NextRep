import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/journey/journey_day.dart';
import '../../domain/journey/journey_overview.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/level_bar.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'journey_controller.dart';
import 'widgets/day_detail_sheet.dart';
import 'widgets/journey_tile.dart';

/// Journey v1: every day of the arc as a grid, from stored history.
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
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          // Keep showing the previous Journey while a refresh is loading, so
          // the grid (and its scroll position) is not torn down.
          child: switch (journey) {
            AsyncValue(hasError: false, :final value?) => _content(
              context,
              value,
            ),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(journeyControllerProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, JourneyOverview journey) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final perfect = journey.perfectDays;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.lg,
            WinterSpacing.lg,
            WinterSpacing.lg,
            WinterSpacing.md,
          ),
          sliver: SliverList.list(
            children: [
              Text(
                'JOURNEY',
                style: text.labelLarge?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: WinterSpacing.xs),
              Text(dayTitle(journey.position), style: text.headlineMedium),
              const SizedBox(height: WinterSpacing.md),
              WinterCard(
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
                    const SizedBox(height: WinterSpacing.md),
                    LevelBar(level: journey.level),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.lg),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: WinterSpacing.sm - 2,
              crossAxisSpacing: WinterSpacing.sm - 2,
            ),
            itemCount: journey.days.length,
            itemBuilder: (context, index) {
              final day = journey.days[index];
              return JourneyTile(
                key: ValueKey(day.dayNumber),
                day: day,
                onTap: day.isFuture
                    ? null
                    : () => DayDetailSheet.show(context, day),
              );
            },
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.all(WinterSpacing.lg),
          sliver: SliverToBoxAdapter(child: _Legend()),
        ),
      ],
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
          Text(value, style: text.headlineSmall),
          Text(label, style: text.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: WinterSpacing.md,
      runSpacing: WinterSpacing.sm,
      children: [
        for (final state in JourneyDayState.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: state.filled
                      ? state.color(colors)
                      : state.color(colors).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: WinterSpacing.xs),
              Text(state.label, style: text.bodySmall),
            ],
          ),
      ],
    );
  }
}
