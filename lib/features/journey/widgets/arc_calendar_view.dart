import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/arc_calendar.dart';
import '../../../domain/journey/journey_overview.dart';
import '../calendar_labels.dart';
import 'calendar_day_cell.dart';
import 'day_detail_sheet.dart';

/// The Arc Consistency Calendar (ARC_MOMENTUM_SPEC §§ 7, 12.4): the
/// Journey's 92 days in 13 Arc-week blocks, Week 1 first.
///
/// A second layout of the [JourneyOverview] the Journey screen has already
/// loaded: it reads no repository and no provider, and writes nothing.
/// Days open the existing read-only sheets; a reviewable week's heading
/// opens that week's existing Weekly Review.
class ArcCalendarView extends StatefulWidget {
  const ArcCalendarView({
    super.key,
    required this.journey,
    required this.historical,
  });

  final JourneyOverview journey;

  /// Shown from Arc History (`/arc/:id/journey`): week headings open
  /// `/arc/:id/review`, not the active Arc's review.
  final bool historical;

  /// The widest the calendar gets (landscape, tablets), centred.
  static const double maxWidth = 600;

  /// The grid's side gutter (spec § 7.4).
  static const double gutter = WinterSpacing.sm;

  /// The text scale above which a week takes lines of 4 (spec § 7.4).
  static const double largeTextScale = 1.3;

  /// Days per line for a calendar [width] dp wide at [textScale]: 7, or 4
  /// with large text or when 7 cells would be under 48 dp.
  static int daysPerLine(double width, double textScale) =>
      textScale > largeTextScale ||
          (width - 2 * gutter) / 7 < CalendarDayCell.minExtent
      ? 4
      : 7;

  @override
  State<ArcCalendarView> createState() => _ArcCalendarViewState();
}

class _ArcCalendarViewState extends State<ArcCalendarView> {
  final _controller = ScrollController();

  /// The first block below the scroll origin. Fixed for the life of the
  /// view, so a refresh (or midnight) never moves what the user is looking
  /// at.
  final _centerKey = GlobalKey(debugLabel: 'calendar-initial-week');

  late ArcCalendar _calendar;
  late final int _initialWeek;

  @override
  void initState() {
    super.initState();
    _calendar = ArcCalendar.of(widget.journey);
    _initialWeek = _calendar.initialWeek;
    // One jump after the first layout, never an animation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
  }

  @override
  void didUpdateWidget(ArcCalendarView old) {
    super.didUpdateWidget(old);
    if (!identical(old.journey, widget.journey)) {
      _calendar = ArcCalendar.of(widget.journey);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The initial week sits at the top. When it and the weeks after it are
  /// shorter than the view (Week 13 of a completed Arc), show the weeks
  /// before it in the space left instead of a blank.
  void _fillViewport() {
    if (!mounted || !_controller.hasClients) return;
    final sliver = _centerKey.currentContext?.findRenderObject();
    if (sliver is! RenderSliver) return;
    final position = _controller.position;
    final gap =
        position.viewportDimension - (sliver.geometry?.scrollExtent ?? 0);
    if (gap > 0 && position.pixels == 0) {
      position.jumpTo(math.max(position.minScrollExtent, -gap));
    }
  }

  void _openReview(int week) => context.push(
    widget.historical
        ? AppRoutes.arcReview(widget.journey.session.id, week)
        : AppRoutes.activeReview(week),
  );

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final joinDay = widget.journey.session.joinDayNumber;
    final blocks = _calendar.blocks;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, ArcCalendarView.maxWidth);
        final perLine = ArcCalendarView.daysPerLine(width, textScale);
        final cell = ((width - 2 * ArcCalendarView.gutter) / perLine)
            .floorToDouble();
        Widget block(CalendarWeek week) => Center(
          child: SizedBox(
            width: width,
            child: _WeekBlock(
              block: week,
              cellWidth: cell,
              joinDay: joinDay,
              onOpenReview: week.isReviewable
                  ? () => _openReview(week.number)
                  : null,
            ),
          ),
        );
        final before = blocks.sublist(0, _initialWeek - 1).reversed.toList();
        final after = blocks.sublist(_initialWeek - 1);
        return CustomScrollView(
          controller: _controller,
          center: _centerKey,
          slivers: [
            // Weeks before the initial one, growing upwards from it.
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => block(before[index]),
                childCount: before.length,
              ),
            ),
            SliverPadding(
              key: _centerKey,
              padding: const EdgeInsets.only(bottom: WinterSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => block(after[index]),
                  childCount: after.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One Arc week: its heading, any chapter that starts in it, and its days
/// with pause rows where pauses fall. A focus group read in order.
class _WeekBlock extends StatelessWidget {
  const _WeekBlock({
    required this.block,
    required this.cellWidth,
    required this.joinDay,
    required this.onOpenReview,
  });

  final CalendarWeek block;
  final double cellWidth;
  final int? joinDay;
  final VoidCallback? onOpenReview;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    var run = <CalendarDay>[];
    void flush() {
      if (run.isEmpty) return;
      final days = run;
      rows.add(
        Wrap(
          children: [
            for (final day in days)
              CalendarDayCell(
                day: day,
                width: cellWidth,
                onTap: day.isInteractive
                    ? () => DayDetailSheet.show(
                        context,
                        day.journeyDay,
                        joinDay: joinDay,
                      )
                    : null,
              ),
          ],
        ),
      );
      run = [];
    }

    for (final entry in block.entries) {
      switch (entry) {
        case CalendarDayEntry(:final day):
          run.add(day);
        case CalendarPauseEntry(:final pause):
          flush();
          rows.add(_PauseRow(text: calendarPauseText(pause)));
      }
    }
    flush();

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ArcCalendarView.gutter,
          vertical: WinterSpacing.xs,
        ),
        child: DecoratedBox(
          // An opaque surface: every contrast is measured against it.
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(WinterRadii.button),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WeekHeading(block: block, onTap: onOpenReview),
                for (final chapter in block.chapters)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WinterSpacing.sm,
                      0,
                      WinterSpacing.sm,
                      WinterSpacing.xs,
                    ),
                    // Its own node, read after the heading (not folded
                    // into the block's label ahead of it).
                    child: Semantics(
                      container: true,
                      child: Text(
                        calendarChapterLine(chapter),
                        style: text.bodySmall?.copyWith(
                          color: colors.accentSecondary,
                        ),
                      ),
                    ),
                  ),
                ...rows,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Week 3 · 15–21 Oct · 2 of 3 days full ›": a button opening the week's
/// review when it can be opened, plain text otherwise.
class _WeekHeading extends StatelessWidget {
  const _WeekHeading({required this.block, required this.onTap});

  final CalendarWeek block;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: onTap == null ? colors.textSecondary : colors.textPrimary,
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CalendarDayCell.minExtent),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WinterSpacing.sm,
          vertical: WinterSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(child: Text(calendarWeekHeading(block), style: style)),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      header: true,
      button: onTap != null,
      label: calendarWeekHeadingLabel(block),
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(WinterRadii.button),
                focusColor: colors.accent.withValues(alpha: 0.35),
                child: content,
              ),
            ),
    );
  }
}

/// A pause between two challenge days: text only, not a day, not tappable.
/// Its accessibility label is the same sentence.
class _PauseRow extends StatelessWidget {
  const _PauseRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WinterSpacing.sm,
          vertical: WinterSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline_rounded, color: colors.fog),
            const SizedBox(width: WinterSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
