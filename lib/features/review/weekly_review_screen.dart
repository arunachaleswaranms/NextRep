import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../core/time/local_date.dart';
import '../../domain/journey/arc_weeks.dart';
import '../../domain/progress/day_mode.dart';
import '../../domain/review/weekly_review.dart';
import '../../domain/review/weekly_summary_rules.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/habit_icon.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_card.dart';
import '../journey/widgets/day_detail_sheet.dart';
import '../journey/widgets/journey_marker.dart';
import 'review_labels.dart';
import 'weekly_review_controller.dart';
import 'weekly_summary_text.dart';

/// The Weekly Arc Review (ARC_MOMENTUM_SPEC § 5): one Arc week's settled
/// totals, today's progress apart from them, highlights and a short
/// supportive summary. Without [sessionId] it shows the active Arc
/// (`/journey/review`); with one, that Arc from Arc History
/// (`/arc/:id/review`).
///
/// **Read-only.** It reads one snapshot ([weeklyReviewSourceProvider]) and
/// writes nothing: no close-out, no achievement sync, no XP. Changing weeks
/// replaces the location (`?week=`), so Back always returns to the Journey.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key, this.sessionId, this.requestedWeek});

  final int? sessionId;

  /// The week the location asks for; settled by [ArcWeeks.resolve].
  final int? requestedWeek;

  /// Content width cap on wide screens (spec § 5.3).
  static const double maxContentWidth = 600;

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  late final AppLifecycleListener _lifecycle;

  /// The week on screen once first resolved. Kept across refreshes (e.g.
  /// midnight), so the review stays on the week it opened with even when
  /// the current week moves on. Never persisted.
  int? _shown;

  @override
  void initState() {
    super.initState();
    // The local date may have changed while the app was away.
    _lifecycle = AppLifecycleListener(onResume: _reload);
  }

  @override
  void didUpdateWidget(WeeklyReviewScreen old) {
    super.didUpdateWidget(old);
    if (old.requestedWeek != widget.requestedWeek ||
        old.sessionId != widget.sessionId) {
      _shown = null;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _reload() =>
      ref.invalidate(weeklyReviewSourceProvider(widget.sessionId));

  void _showWeek(int week) {
    final location = switch (widget.sessionId) {
      null => AppRoutes.activeReview(week),
      final id => AppRoutes.arcReview(id, week),
    };
    // Replaces the review page in place: no growing back stack.
    GoRouter.of(context).replace(location);
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(weeklyReviewSourceProvider(widget.sessionId));
    final colors = context.winter;
    // Keep showing the previous review while a refresh loads (the Journey
    // pattern). A result for another arc is never shown.
    final value = switch (source.hasError ? null : source.value) {
      final v?
          when widget.sessionId == null ||
              v.history.session.id == widget.sessionId =>
        v,
      _ => null,
    };
    final week = value?.weeks.resolve(_shown ?? widget.requestedWeek);
    if (value != null) _shown = week;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(week == null ? 'Week review' : 'Week $week review'),
      ),
      body: SafeArea(
        top: false,
        child: switch (source) {
          _ when value != null && week == null => const EmptyStateView(
            icon: Icons.calendar_view_week_rounded,
            title: 'Your first week review appears once your Arc has started.',
          ),
          _ when value != null => _ReviewBody(
            review: value.review(week!),
            onShowWeek: _showWeek,
          ),
          AsyncError(:final error, :final stackTrace) => FailureView(
            failure: toAppFailure(error, stackTrace),
            onRetry: _reload,
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.review, required this.onShowWeek});

  final WeeklyReview review;
  final ValueChanged<int> onShowWeek;

  @override
  Widget build(BuildContext context) {
    final summary = WeeklySummaryRules.summarize(review);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final empty = review.countedDays == 0;
    final paused = review.status == ArcWeekStatus.paused;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth,
          WeeklyReviewScreen.maxContentWidth,
        );
        final side = (constraints.maxWidth - width) / 2;
        Widget card(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            0,
            WinterSpacing.md,
            WinterSpacing.sm,
          ),
          child: child,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            WinterSpacing.xs,
            side,
            WinterSpacing.xl,
          ),
          children: [
            // Focus and reading order (spec § 8.1): header, summary, week
            // strip, stats, Today, highlights, habits.
            card(_Header(review: review, onShowWeek: onShowWeek)),
            card(_Summary(summary: summary)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WinterSpacing.sm,
                0,
                WinterSpacing.sm,
                WinterSpacing.sm,
              ),
              child: _WeekStrip(
                review: review,
                width: width - 2 * WinterSpacing.sm,
                largeText: largeText,
              ),
            ),
            if (!empty)
              card(_Stats(review: review, stacked: largeText))
            else if (!paused)
              card(
                const _Note(
                  'Stats appear after your first full day this week.',
                ),
              ),
            if (review.today case final today?) card(_TodayBlock(today)),
            if (review.mostConsistent case final best?)
              card(
                _Highlight(
                  title: 'Most consistent this week',
                  tally: best,
                  stacked: largeText,
                ),
              ),
            if (review.roomToGrow case final grow?)
              card(
                _Highlight(
                  title: 'Room to grow',
                  tally: grow,
                  stacked: largeText,
                ),
              ),
            if (review.habits.isNotEmpty)
              card(_HabitBreakdown(review: review, stacked: largeText)),
            card(
              _Note(
                review.status == ArcWeekStatus.inProgress
                    ? 'Counts finished days; today is added when it ends. '
                          'Viewing a review never changes XP or progress.'
                    : 'Counts finished days. Viewing a review never changes '
                          'XP or progress.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.review, required this.onShowWeek});

  final WeeklyReview review;
  final ValueChanged<int> onShowWeek;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final week = review.week;
    final session = review.session;
    final previous = review.previousWeek;
    final next = review.nextWeek;
    final ended = session.status == WinterArcStatus.ended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          container: true,
          label: reviewHeaderLabel(review),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                arcHeading(session, today: review.date),
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              if (ended)
                Text(
                  dayTitle(
                    ArcEnded(
                      lastDayNumber: session.dayNumberOf(session.closedOn!)!,
                      closedOn: session.closedOn!,
                      totalDays: session.lengthInDays,
                    ),
                  ),
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              const SizedBox(height: WinterSpacing.xs),
              Text(
                'Week ${week.number} of ${ArcWeeks.count} · '
                'Days ${week.firstDay}–${week.lastDay}',
                style: text.titleLarge,
              ),
              Text(
                '${weekDateRange(week)} · ${weekStatusLabel(week.status)}',
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
              if (review.pausedSince case final since?)
                Text(
                  'Paused since ${shortDate(since)}',
                  style: text.bodyMedium?.copyWith(color: colors.recovery),
                ),
            ],
          ),
        ),
        if (previous != null || next != null) ...[
          const SizedBox(height: WinterSpacing.sm),
          Wrap(
            spacing: WinterSpacing.sm,
            runSpacing: WinterSpacing.xs,
            children: [
              if (previous != null)
                OutlinedButton.icon(
                  onPressed: () => onShowWeek(previous),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(
                    'Week $previous',
                    semanticsLabel: 'Previous week, Week $previous',
                  ),
                ),
              if (next != null)
                OutlinedButton.icon(
                  onPressed: () => onShowWeek(next),
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconAlignment: IconAlignment.end,
                  label: Text(
                    'Week $next',
                    semanticsLabel: 'Next week, Week $next',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) => WinterCard(
    child: Text(
      WeeklySummaryText.paragraph(summary),
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

/// The week's 7 or 8 days, wrapping (never scrolling sideways): 7 to a
/// line, or 4 with large text or when a cell would be under 48 dp.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.review,
    required this.width,
    required this.largeText,
  });

  final WeeklyReview review;
  final double width;
  final bool largeText;

  static const double minCell = 48;

  @override
  Widget build(BuildContext context) {
    final perLine = largeText || width / 7 < minCell ? 4 : 7;
    final cell = (width / perLine).floorToDouble();
    final joinDay = review.session.joinDayNumber;
    return FocusTraversalGroup(
      child: Wrap(
        children: [
          for (final day in review.days)
            _DayCell(day: day, width: cell, joinDay: joinDay),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.width,
    required this.joinDay,
  });

  final ReviewDay day;
  final double width;
  final int? joinDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final journeyDay = day.journeyDay;
    // Past days and today open the read-only detail; a day before joining
    // its note; upcoming and not-reached days have nothing to show.
    final onTap = journeyDay.isFuture
        ? null
        : () => DayDetailSheet.show(context, journeyDay, joinDay: joinDay);
    final markerSize = math.min(width, JourneyMarker.extent);
    return Semantics(
      container: true,
      button: onTap != null,
      label: reviewDayLabel(day),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WinterRadii.button),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: markerSize,
                child: FittedBox(child: JourneyMarker(day: journeyDay)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    switch (day.date) {
                      final date? => DateFormat(
                        'EEE',
                      ).format(date.toLocalDateTime()),
                      null => '–',
                    },
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.review, required this.stacked});

  final WeeklyReview review;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final completion = review.completionPercent;
    final consistency = review.consistencyPercent;
    final n = review.countedDays;
    final c = review.completedHabitDays;
    final h = review.habitOpportunities;
    final days = n == 1 ? 'day' : 'days';
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            label: 'Habit completion',
            value: completion == null ? '$c of $h' : '$c of $h · $completion%',
            detail: '$n $days counted',
            semantics:
                'Habit completion: $c of $h'
                '${completion == null ? '' : ', $completion percent'}. '
                '$n $days counted.',
            stacked: stacked,
            emphasis: true,
          ),
          _StatRow(
            label: 'Consistency',
            value: '${consistency ?? 0}% · ${review.fullDays} of $n $days full',
            semantics:
                'Consistency: ${consistency ?? 0} percent, '
                '${review.fullDays} of $n $days full.',
            stacked: stacked,
          ),
          _StatRow(
            label: 'XP earned',
            value: '+${review.xpEarned} XP',
            semantics: 'XP earned: ${review.xpEarned} XP.',
            stacked: stacked,
          ),
          _StatRow(
            label: 'Perfect Days',
            value: '${review.perfectDays}',
            semantics: 'Perfect Days: ${review.perfectDays}.',
            stacked: stacked,
          ),
          _StatRow(
            label: 'Minimum Days',
            value:
                '${review.minimumDaysCompleted} completed · '
                '${review.minimumDaysChosen} chosen',
            semantics:
                'Minimum Days: ${review.minimumDaysCompleted} completed, '
                '${review.minimumDaysChosen} chosen.',
            stacked: stacked,
          ),
        ],
      ),
    );
  }
}

/// One statistic: a label and its value, beside each other or, with large
/// text, the value under the label. One merged semantics node.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.semantics,
    required this.stacked,
    this.detail,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? detail;
  final String semantics;
  final bool stacked;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final labelText = Text(
      label.toUpperCase(),
      style: text.labelMedium?.copyWith(
        color: colors.accentSecondary,
        letterSpacing: 1.2,
      ),
    );
    final valueText = Text(
      value,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: (emphasis ? text.titleLarge : text.titleMedium)?.copyWith(
        color: colors.textPrimary,
      ),
    );
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stacked) ...[
              labelText,
              valueText,
            ] else
              Row(
                children: [
                  Expanded(child: labelText),
                  const SizedBox(width: WinterSpacing.sm),
                  Flexible(child: valueText),
                ],
              ),
            if (detail case final detail?)
              Text(
                detail,
                textAlign: stacked ? TextAlign.start : TextAlign.end,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayBlock extends StatelessWidget {
  const _TodayBlock(this.today);

  final TodaySoFar today;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final minimum = today.mode == DayMode.minimum;
    final habits = today.total == 1 ? 'habit' : 'habits';
    return Semantics(
      container: true,
      label:
          'Today so far, Day ${today.dayNumber}: ${today.completed} of '
          '${today.total} $habits, ${today.xp} XP.'
          '${minimum ? ' Minimum Day.' : ''} Today counts once it ends.',
      excludeSemantics: true,
      child: WinterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'TODAY SO FAR (DAY ${today.dayNumber})',
              style: text.labelMedium?.copyWith(
                color: colors.accentSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: WinterSpacing.xs),
            Text(
              '${today.completed} of ${today.total} $habits · ${today.xp} XP'
              '${minimum ? ' · Minimum Day' : ''}',
              style: text.titleMedium,
            ),
            Text(
              'Today counts once it ends.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.title,
    required this.tally,
    required this.stacked,
  });

  final String title;
  final HabitWeekTally tally;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final count = '${tally.completedDays} of ${tally.applicableDays} days';
    return Semantics(
      container: true,
      label: '$title: ${tally.habit.title}, $count.',
      excludeSemantics: true,
      child: WinterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: text.labelMedium?.copyWith(
                color: colors.accentSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: WinterSpacing.xs),
            _HabitLine(tally: tally, count: count, stacked: stacked),
          ],
        ),
      ),
    );
  }
}

class _HabitBreakdown extends StatelessWidget {
  const _HabitBreakdown({required this.review, required this.stacked});

  final WeeklyReview review;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'HABITS THIS WEEK',
              style: text.labelMedium?.copyWith(
                color: colors.accentSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final tally in review.habits)
            Semantics(
              container: true,
              label:
                  '${tally.habit.title}: ${tally.completedDays} of '
                  '${tally.applicableDays} days.',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(top: WinterSpacing.sm),
                child: _HabitLine(
                  tally: tally,
                  count:
                      '${tally.completedDays} of ${tally.applicableDays} days',
                  stacked: stacked,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HabitLine extends StatelessWidget {
  const _HabitLine({
    required this.tally,
    required this.count,
    required this.stacked,
  });

  final HabitWeekTally tally;
  final String count;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = Text(tally.habit.title, style: text.titleMedium);
    final value = Text(
      count,
      style: text.bodyMedium?.copyWith(color: context.winter.textSecondary),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitIcon(iconKey: tally.habit.iconKey),
        const SizedBox(width: WinterSpacing.sm),
        Expanded(
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, value],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: WinterSpacing.sm),
                    value,
                  ],
                ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.winter.textSecondary),
  );
}

/// "Thu 15 Oct": a review's short date.
String shortDate(LocalDate date) =>
    DateFormat('EEE d MMM').format(date.toLocalDateTime());
