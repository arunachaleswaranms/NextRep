import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/arc_milestones.dart';
import '../../../domain/journey/journey_day.dart';
import '../../../domain/journey/journey_overview.dart';
import '../../../shared/formatting/arc_labels.dart';
import '../../../shared/winter_scene/cabin_layer.dart';
import '../../../shared/winter_scene/mountain_layer.dart';
import '../../../shared/winter_scene/scene_progress.dart';
import '../../../shared/winter_scene/sky_layer.dart';
import 'day_detail_sheet.dart';
import 'journey_marker.dart';

/// An entry of the path, bottom (Day 1) to top (the summit).
sealed class PathItem {
  const PathItem();
}

final class TrailheadItem extends PathItem {
  const TrailheadItem();
}

final class ChapterItem extends PathItem {
  const ChapterItem(this.chapter, this.days);

  final JourneyChapter chapter;

  /// The chapter's days, first day first.
  final List<JourneyDay> days;
}

final class DayItem extends PathItem {
  const DayItem(this.day);

  final JourneyDay day;
}

final class SummitItem extends PathItem {
  const SummitItem(this.day);

  /// The last day of the arc.
  final JourneyDay day;
}

/// Where everything sits on the path. Extents are fixed per item kind (and
/// grow with the text scale), so the list stays lazy and the scroll offset
/// of any day is known without building it.
final class JourneyPathLayout {
  JourneyPathLayout(List<JourneyDay> days, {double textScale = 1}) {
    final growth = (textScale - 1).clamp(0.0, 2.0);
    dayExtent = 72 + 16 * growth;
    chapterExtent = 104 + 44 * growth;
    items.add(const TrailheadItem());
    for (final chapter in JourneyChapter.values) {
      final inChapter = [
        for (final d in days)
          if (chapter.contains(d.dayNumber)) d,
      ];
      if (inChapter.isEmpty) continue;
      items.add(ChapterItem(chapter, inChapter));
      items.addAll(inChapter.map(DayItem.new));
    }
    if (days.isNotEmpty) items.add(SummitItem(days.last));
    var start = 0.0;
    for (final item in items) {
      starts.add(start);
      start += extentOf(item);
    }
    total = start;
  }

  static const double trailheadExtent = 112;
  static const double summitExtent = 236;
  late final double dayExtent;
  late final double chapterExtent;

  /// Bottom to top.
  final List<PathItem> items = [];

  /// Distance of each item's bottom edge from the bottom of the path.
  final List<double> starts = [];
  late final double total;

  double extentOf(PathItem item) => switch (item) {
    TrailheadItem() => trailheadExtent,
    ChapterItem() => chapterExtent,
    DayItem() => dayExtent,
    SummitItem() => summitExtent,
  };

  int indexOfDay(int dayNumber) => items.indexWhere(
    (item) => item is DayItem && item.day.dayNumber == dayNumber,
  );

  /// Height (from the bottom of the path) of the centre of [index].
  double centerOf(int index) => starts[index] + extentOf(items[index]) / 2;

  /// The scroll offset that centres [index] in a [viewport] tall view.
  double offsetToShow(int index, double viewport) =>
      (centerOf(index) - viewport / 2).clamp(
        0.0,
        math.max(0, total - viewport),
      );

  /// The path's horizontal position at height [y] for a [width] wide view.
  static double pathX(double y, double width) {
    final amplitude = (width / 2 - 76).clamp(24.0, 120.0);
    return width / 2 + amplitude * math.sin(y / 130 + 0.4);
  }
}

/// The 92 days as a winding trail up the mountain, Day 1 at the bottom and
/// the summit on top. Opens centred on today.
class JourneyPath extends StatefulWidget {
  const JourneyPath({super.key, required this.journey});

  final JourneyOverview journey;

  @override
  State<JourneyPath> createState() => _JourneyPathState();
}

class _JourneyPathState extends State<JourneyPath> {
  ScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final layout = JourneyPathLayout(journey.days, textScale: textScale);
    final todayIndex = journey.days.indexWhere((d) => d.isToday);
    // The walked trail ends at today's marker, or at the summit once over.
    final litUntil = todayIndex >= 0
        ? layout.centerOf(layout.indexOfDay(journey.days[todayIndex].dayNumber))
        : journey.days.every((d) => !d.isFuture)
        ? layout.total
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Created once, so refreshes keep the scroll position.
        _controller ??= ScrollController(
          initialScrollOffset: layout.offsetToShow(
            todayIndex >= 0
                ? layout.indexOfDay(journey.days[todayIndex].dayNumber)
                : litUntil > 0
                ? layout.items.length - 1
                : 0,
            constraints.maxHeight,
          ),
        );
        return ListView.builder(
          controller: _controller,
          reverse: true,
          itemCount: layout.items.length,
          itemExtentBuilder: (index, _) => layout.extentOf(layout.items[index]),
          itemBuilder: (context, index) {
            final item = layout.items[index];
            final slice = _PathSlice(
              start: layout.starts[index],
              extent: layout.extentOf(item),
              litUntil: litUntil,
              chapter: switch (item) {
                DayItem(:final day) => JourneyChapter.forDay(day.dayNumber),
                ChapterItem(:final chapter) => chapter,
                TrailheadItem() => JourneyChapter.frozenForest,
                SummitItem() => JourneyChapter.summitApproach,
              },
              seed: index,
            );
            return switch (item) {
              DayItem(:final day) => _DayRow(
                key: ValueKey(day.dayNumber),
                day: day,
                joinDay: journey.session.joinDayNumber,
                width: width,
                center: layout.centerOf(index),
                slice: slice,
              ),
              ChapterItem() => _ChapterRow(
                item: item,
                width: width,
                center: layout.centerOf(index),
                slice: slice,
              ),
              TrailheadItem() => _TrailheadRow(slice: slice),
              SummitItem(:final day) => _SummitRow(
                day: day,
                reached: litUntil >= layout.total,
                slice: slice,
              ),
            };
          },
        );
      },
    );
  }
}

/// The part of the trail behind one item.
final class _PathSlice {
  const _PathSlice({
    required this.start,
    required this.extent,
    required this.litUntil,
    required this.chapter,
    required this.seed,
  });

  final double start;
  final double extent;
  final double litUntil;
  final JourneyChapter chapter;
  final int seed;
}

class _SlicePainter extends CustomPainter {
  const _SlicePainter({
    required this.slice,
    required this.colors,
    this.toTop = 1,
  });

  final _PathSlice slice;
  final WinterColors colors;

  /// Share of the item's height (from the bottom) the trail runs through.
  final double toTop;

  @override
  void paint(Canvas canvas, Size size) {
    _decorate(canvas, size);
    final lit = Path();
    final unlit = <Offset>[];
    var litStarted = false;
    final top = size.height * (1 - toTop);
    for (var y = size.height; y >= top - 0.01; y -= 3) {
      final g = slice.start + size.height - y;
      final point = Offset(JourneyPathLayout.pathX(g, size.width), y);
      if (g <= slice.litUntil) {
        litStarted
            ? lit.lineTo(point.dx, point.dy)
            : lit.moveTo(point.dx, point.dy);
        litStarted = true;
      } else {
        unlit.add(point);
      }
    }
    final dash = Paint()
      ..color = colors.snow.withValues(alpha: 0.25)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < unlit.length; i += 3) {
      canvas.drawLine(unlit[i], unlit[i + 1], dash);
    }
    if (!litStarted) return;
    canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = colors.accentSecondary.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(colors.accentSecondary, colors.snow, 0.4)!,
    );
  }

  /// Sparse scenery at the far edge, away from the trail.
  void _decorate(Canvas canvas, Size size) {
    if (slice.seed.isOdd) return;
    final random = math.Random(slice.seed);
    final mid = slice.start + size.height / 2;
    final trailLeft = JourneyPathLayout.pathX(mid, size.width) < size.width / 2;
    final x = trailLeft
        ? size.width - 14 - random.nextDouble() * 16
        : 14 + random.nextDouble() * 16;
    final base = Offset(x, size.height * (0.55 + random.nextDouble() * 0.35));
    final body = Paint()..color = colors.mountainMid.withValues(alpha: 0.9);
    final snow = Paint()..color = colors.snow.withValues(alpha: 0.55);
    switch (slice.chapter) {
      case JourneyChapter.frozenForest || JourneyChapter.firstAscent:
        final h = 22 + random.nextDouble() * 14;
        for (var tier = 0; tier < 3; tier++) {
          final t = base.dy - h + tier * h * 0.3;
          final half = h * (0.14 + tier * 0.08);
          canvas.drawPath(
            Path()
              ..moveTo(base.dx, t)
              ..lineTo(base.dx + half, t + h * 0.45)
              ..lineTo(base.dx - half, t + h * 0.45)
              ..close(),
            body,
          );
        }
        canvas.drawCircle(Offset(base.dx, base.dy - h + 2), 1.6, snow);
      case JourneyChapter.ridge || JourneyChapter.highMountain:
        final w = 16 + random.nextDouble() * 12;
        final rock = Path()
          ..moveTo(base.dx - w / 2, base.dy)
          ..lineTo(base.dx - w * 0.2, base.dy - w * 0.7)
          ..lineTo(base.dx + w * 0.15, base.dy - w * 0.5)
          ..lineTo(base.dx + w / 2, base.dy)
          ..close();
        canvas.drawPath(rock, body);
        canvas.drawPath(
          Path()
            ..moveTo(base.dx - w * 0.28, base.dy - w * 0.55)
            ..lineTo(base.dx - w * 0.2, base.dy - w * 0.7)
            ..lineTo(base.dx + w * 0.15, base.dy - w * 0.5)
            ..close(),
          snow,
        );
      case JourneyChapter.auroraPass:
        final glint = Paint()
          ..color = colors.auroraGreen.withValues(alpha: 0.5)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          base - const Offset(4, 0),
          base + const Offset(4, 0),
          glint,
        );
        canvas.drawLine(
          base - const Offset(0, 4),
          base + const Offset(0, 4),
          glint,
        );
      case JourneyChapter.summitApproach:
        canvas.drawOval(
          Rect.fromCenter(center: base, width: 34, height: 9),
          Paint()..color = colors.snow.withValues(alpha: 0.18),
        );
    }
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.colors != colors ||
      old.toTop != toTop ||
      old.slice.start != slice.start ||
      old.slice.extent != slice.extent ||
      old.slice.litUntil != slice.litUntil;
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    super.key,
    required this.day,
    required this.joinDay,
    required this.width,
    required this.center,
    required this.slice,
  });

  final JourneyDay day;

  /// The day the user joined the arc, for the "before you joined" note.
  final int? joinDay;
  final double width;
  final double center;
  final _PathSlice slice;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final x = JourneyPathLayout.pathX(center, width);
    final labelRight = x < width / 2;
    const half = JourneyMarker.extent / 2;
    final milestone = ArcMilestone.values
        .where((m) => m.day == day.dayNumber)
        .firstOrNull;
    final reached = !day.isFuture;

    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: labelRight
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        ExcludeSemantics(
          child: Text(
            day.isToday
                ? 'TODAY · Day ${day.dayNumber}'
                : 'Day ${day.dayNumber} · '
                      '${DateFormat('d MMM').format(day.date.toLocalDateTime())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: day.isToday ? colors.snow : colors.textSecondary,
              fontWeight: day.isToday ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: day.isToday ? 1 : 0.2,
            ),
          ),
        ),
        if (milestone != null)
          TweenAnimationBuilder<double>(
            // A milestone lights up once the trail reaches it.
            tween: Tween(end: reached ? 1 : 0),
            duration: context.motion.celebration,
            builder: (context, glow, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.flag_rounded,
                  size: 14,
                  color: Color.lerp(
                    colors.textSecondary,
                    colors.warmLight,
                    glow,
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    milestoneTitle(milestone),
                    semanticsLabel:
                        'Milestone ${milestoneTitle(milestone)}'
                        '${reached ? ', reached' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Color.lerp(
                        colors.textSecondary,
                        colors.warmLight,
                        glow,
                      ),
                      shadows: [
                        Shadow(
                          color: colors.warmLight.withValues(alpha: 0.6 * glow),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SlicePainter(slice: slice, colors: colors),
            ),
          ),
        ),
        Positioned(
          left: x - half,
          top: slice.extent / 2 - half,
          child: JourneyMarker(
            day: day,
            onTap: day.isFuture
                ? null
                : () => DayDetailSheet.show(context, day, joinDay: joinDay),
          ),
        ),
        Positioned(
          left: labelRight ? x + half : 44,
          right: labelRight ? 44 : width - x + half,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: labelRight
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: label,
          ),
        ),
      ],
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.item,
    required this.width,
    required this.center,
    required this.slice,
  });

  final ChapterItem item;
  final double width;
  final double center;
  final _PathSlice slice;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final chapter = item.chapter;
    final started = item.days.any((d) => !d.isFuture);
    final full = item.days
        .where(
          (d) =>
              d.state == JourneyDayState.perfect ||
              d.state == JourneyDayState.minimumComplete,
        )
        .length;
    final cardOnRight = JourneyPathLayout.pathX(center, width) < width / 2;
    final status = started
        ? '$full of ${chapter.length} full days'
        : 'Starts on Day ${chapter.firstDay}';

    final card = Semantics(
      container: true,
      label:
          'Chapter ${chapter.index + 1}, ${chapterTitle(chapter)}, days '
          '${chapter.firstDay} to ${chapter.lastDay}. $status',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WinterSpacing.md,
          vertical: WinterSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.glass,
          borderRadius: BorderRadius.circular(WinterRadii.button),
          border: Border.all(
            color: started
                ? colors.accentSecondary.withValues(alpha: 0.5)
                : colors.glassBorder,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CHAPTER ${chapter.index + 1} · DAYS '
              '${chapter.firstDay}–${chapter.lastDay}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: started ? colors.accentSecondary : colors.textSecondary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              chapterTitle(chapter),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: started ? colors.textPrimary : colors.textSecondary,
              ),
            ),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SlicePainter(slice: slice, colors: colors),
            ),
          ),
        ),
        Positioned(
          left: cardOnRight ? width * 0.36 : WinterSpacing.md,
          right: cardOnRight ? WinterSpacing.md : width * 0.36,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: cardOnRight
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: card,
          ),
        ),
      ],
    );
  }
}

class _TrailheadRow extends StatelessWidget {
  const _TrailheadRow({required this.slice});

  final _PathSlice slice;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SlicePainter(slice: slice, colors: colors),
          ),
        ),
        // The trail starts right of centre, so the sign sits on the left.
        Align(
          alignment: const Alignment(-0.85, 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BASE CAMP',
                style: text.labelMedium?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 3,
                ),
              ),
              Text('The climb starts at Day 1.', style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummitRow extends StatelessWidget {
  const _SummitRow({
    required this.day,
    required this.reached,
    required this.slice,
  });

  final JourneyDay day;
  final bool reached;
  final _PathSlice slice;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final scene = reached
        ? SceneProgress.summit()
        : SceneProgress(dayNumber: ArcMilestone.summitShelter.day);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SlicePainter(slice: slice, colors: colors, toTop: 0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            WinterSpacing.md,
            WinterSpacing.md,
            48,
          ),
          child: Semantics(
            container: true,
            label: reached
                ? 'Summit, Day ${day.dayNumber}, reached'
                : 'Summit, Day ${day.dayNumber}',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WinterRadii.card),
                border: Border.all(
                  color: reached
                      ? colors.warmLight.withValues(alpha: 0.7)
                      : colors.glassBorder,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WinterRadii.card),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // A still picture of the summit: no ticker of its own.
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: SkyPainter(
                          colors: colors,
                          warmth: scene.warmth,
                        ),
                        foregroundPainter: MountainPainter(
                          scene: scene,
                          colors: colors,
                        ),
                        child: CustomPaint(
                          foregroundPainter: CampPainter(
                            scene: scene,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.background.withValues(alpha: 0),
                            colors.background.withValues(alpha: 0.8),
                          ],
                          stops: const [0.45, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(WinterSpacing.md),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SUMMIT',
                            style: text.labelLarge?.copyWith(
                              color: reached
                                  ? colors.warmLight
                                  : colors.textSecondary,
                              letterSpacing: 3,
                            ),
                          ),
                          Text(
                            reached
                                ? 'Reached'
                                : 'Day ${day.dayNumber} · '
                                      '${DateFormat('d MMMM').format(day.date.toLocalDateTime())}',
                            style: text.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
