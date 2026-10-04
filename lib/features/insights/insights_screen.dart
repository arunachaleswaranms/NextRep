import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/insights/insight_snapshot.dart';
import '../../domain/reflection/daily_reflection.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import '../journal/widgets/mood_style.dart';
import 'insights_controller.dart';
import 'widgets/insight_charts.dart';

/// Insights across every started arc: overall totals, per-habit
/// consistency and the moods recorded in the Journal. Computed on this
/// device from stored history; descriptive only.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch (insights) {
            AsyncData(:final value) when value.isEmpty => const _Empty(),
            AsyncData(:final value) => _Content(value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(insightsProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(WinterSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insights_rounded,
            size: 48,
            color: context.winter.accentSecondary,
          ),
          const SizedBox(height: WinterSpacing.md),
          Text(
            'Insights appear once your first Winter Arc has started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

class _Content extends StatelessWidget {
  const _Content(this.snapshot);

  final InsightSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final o = snapshot.overall;
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    String plural(int n, String one, [String? many]) =>
        '$n ${n == 1 ? one : (many ?? '${one}s')}';

    final arcsValue = o.activeArc == null
        ? plural(o.completedArcs, 'completed')
        : '${o.completedArcs} done · Day ${o.activeDay} now';
    final stats = [
      _StatData('Arcs', arcsValue, Icons.landscape_rounded),
      _StatData('Days climbed', '${o.elapsedDays}', Icons.calendar_month),
      _StatData(
        'Consistency',
        '${o.consistencyPercent}%',
        Icons.insights_rounded,
        detail: '${o.fullDays} of ${o.elapsedDays} days full',
      ),
      _StatData('Perfect Days', '${o.perfectDays}', Icons.star_rounded),
      _StatData(
        'Minimum Days completed',
        '${o.minimumDaysCompleted}',
        Icons.spa_rounded,
      ),
      _StatData('Total XP', '${o.totalXp}', Icons.bolt_rounded),
      _StatData(
        'Highest level',
        'Level ${o.highestLevel ?? 1}',
        Icons.trending_up_rounded,
      ),
      _StatData(
        'XP per day',
        o.averageXpPerDay.toStringAsFixed(0),
        Icons.speed_rounded,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        WinterSpacing.md,
        WinterSpacing.sm,
        WinterSpacing.md,
        WinterSpacing.xl,
      ),
      children: [
        _Heading('ACROSS YOUR ARCS'),
        for (var i = 0; i < stats.length; i += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Stat(stats[i])),
                const SizedBox(width: WinterSpacing.sm),
                Expanded(child: _Stat(stats[i + 1])),
              ],
            ),
          ),
          const SizedBox(height: WinterSpacing.sm),
        ],
        Text(
          'Consistency counts every full day (Perfect Days and completed '
          'Minimum Days) out of every day climbed, across all Arcs. A '
          'running Arc counts up to today.',
          style: text.bodySmall,
        ),
        if (snapshot.mostConsistent != null || snapshot.bestStreak != null) ...[
          const SizedBox(height: WinterSpacing.lg),
          _Heading('STRONGEST HABITS'),
          if (snapshot.mostConsistent case final habit?)
            _Highlight(
              label: 'Most consistent',
              habit: habit,
              value: '${habit.completionPercent}%',
              accent: colors.celebration,
            ),
          if (snapshot.bestStreak case final habit?) ...[
            const SizedBox(height: WinterSpacing.sm),
            _Highlight(
              label: 'Best streak',
              habit: habit,
              value: plural(habit.bestStreak, 'day'),
              accent: colors.ember,
            ),
          ],
        ],
        const SizedBox(height: WinterSpacing.lg),
        _Heading('HABITS'),
        if (snapshot.habits.isEmpty)
          const _Muted('No habit has been tracked yet.')
        else
          for (final habit in snapshot.habits) ...[
            _HabitRow(habit),
            const SizedBox(height: WinterSpacing.sm),
          ],
        Text(
          'Only days a habit was turned on count. A Minimum Day done at the '
          'minimum counts as done.',
          style: text.bodySmall,
        ),
        const SizedBox(height: WinterSpacing.lg),
        _Heading('YOUR REFLECTIONS'),
        _Reflections(overall: o, moods: snapshot.moods),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: context.winter.accentSecondary, letterSpacing: 3),
      ),
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

final class _StatData {
  const _StatData(this.label, this.value, this.icon, {this.detail});

  final String label;
  final String value;
  final IconData icon;
  final String? detail;
}

class _Stat extends StatelessWidget {
  const _Stat(this.data);

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          '${data.label}: ${data.value}'
          '${data.detail == null ? '' : ', ${data.detail}'}',
      excludeSemantics: true,
      child: WinterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, size: 18, color: context.winter.accentSecondary),
            const SizedBox(height: WinterSpacing.xs),
            Text(data.value, style: text.titleLarge),
            Text(data.label, style: text.bodySmall),
            if (data.detail case final detail?)
              Text(detail, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.label,
    required this.habit,
    required this.value,
    required this.accent,
  });

  final String label;
  final HabitInsight habit;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$label: ${habit.title}, $value',
      excludeSemantics: true,
      child: WinterCard(
        highlighted: true,
        accent: accent,
        child: Row(
          children: [
            HabitIcon(iconKey: habit.iconKey),
            const SizedBox(width: WinterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: accent,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(habit.title, style: text.titleMedium),
                ],
              ),
            ),
            Text(value, style: text.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow(this.habit);

  final HabitInsight habit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final arcs = habit.arcCount == 1 ? '1 Arc' : '${habit.arcCount} Arcs';
    final streak = habit.bestStreak == 1 ? '1 day' : '${habit.bestStreak} days';
    final detail =
        '${habit.completedDays} of ${habit.applicableDays} days · '
        'best streak $streak · $arcs';
    return Semantics(
      container: true,
      label: '${habit.title}: ${habit.completionPercent}% done. $detail',
      excludeSemantics: true,
      child: WinterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HabitIcon(iconKey: habit.iconKey),
                const SizedBox(width: WinterSpacing.sm),
                Expanded(child: Text(habit.title, style: text.titleMedium)),
                Text('${habit.completionPercent}%', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: WinterSpacing.sm),
            RatioBar(value: habit.completion),
            const SizedBox(height: WinterSpacing.xs),
            Text(detail, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Reflections extends StatelessWidget {
  const _Reflections({required this.overall, required this.moods});

  final OverallInsight overall;
  final MoodInsight moods;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    if (moods.isEmpty) {
      return const _Muted(
        'No reflections yet. Saved Journal entries will show up here.',
      );
    }
    final count = overall.reflectionCount;
    final most = moods.counts.values.fold(0, (a, b) => a > b ? a : b);
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label:
                '$count ${count == 1 ? 'reflection' : 'reflections'}, on '
                '${overall.reflectionPercent}% of days',
            excludeSemantics: true,
            child: Text(
              '$count ${count == 1 ? 'reflection' : 'reflections'} · '
              '${overall.reflectionPercent}% of days',
              style: text.titleMedium,
            ),
          ),
          const SizedBox(height: WinterSpacing.md),
          for (final mood in Mood.values.reversed) ...[
            Semantics(
              container: true,
              label: '${mood.label}: ${moods.counts[mood]}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(mood.icon, size: 18, color: mood.colorOf(colors)),
                  const SizedBox(width: WinterSpacing.xs),
                  SizedBox(
                    width: 76,
                    child: Text(mood.label, style: text.bodyMedium),
                  ),
                  Expanded(
                    child: RatioBar(
                      value: most == 0 ? 0 : moods.counts[mood]! / most,
                      color: mood.colorOf(colors),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${moods.counts[mood]}',
                      textAlign: TextAlign.end,
                      style: text.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WinterSpacing.sm),
          ],
          if (moods.withoutMood > 0)
            Text(
              '${moods.withoutMood} saved without a mood',
              style: text.bodySmall,
            ),
          if (moods.recent.isNotEmpty) ...[
            const SizedBox(height: WinterSpacing.md),
            Text('Recent moods', style: text.titleSmall),
            const SizedBox(height: WinterSpacing.sm),
            MoodTimeline(points: moods.recent),
          ],
          const SizedBox(height: WinterSpacing.md),
          Text(
            'Moods are shown exactly as you chose them. What you wrote is '
            'never read for insights.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
