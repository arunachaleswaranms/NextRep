import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/insights/insight_snapshot.dart';
import '../../../domain/reflection/daily_reflection.dart';
import '../../journal/widgets/mood_style.dart';

/// A horizontal bar filled to [value] (`0.0..1.0`). Purely visual: the
/// number it shows is always written next to it, and callers give the row
/// its semantics.
class RatioBar extends StatelessWidget {
  const RatioBar({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return ExcludeSemantics(
      child: SizedBox(
        height: 8,
        width: double.infinity,
        child: CustomPaint(
          painter: _RatioBarPainter(
            value: value.clamp(0, 1).toDouble(),
            track: colors.glassBorder,
            fill: color ?? colors.accentSecondary,
          ),
        ),
      ),
    );
  }
}

class _RatioBarPainter extends CustomPainter {
  const _RatioBarPainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (value <= 0) return;
    // A small value stays visible as a dot rather than vanishing.
    final width = (size.width * value).clamp(size.height, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & Size(width, size.height), radius),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RatioBarPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// The mood of the most recent reflected days, oldest on the left, one row
/// per mood with its label always visible. The rows only place the dots:
/// there is no score and no trend line.
class MoodTimeline extends StatelessWidget {
  const MoodTimeline({super.key, required this.points});

  final List<MoodPoint> points;

  /// Row height at 1× text; it grows with the text scale so the labels
  /// never clip.
  static const _baseRowHeight = 26.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final rowHeight = MediaQuery.textScalerOf(context).scale(_baseRowHeight);
    final moods = Mood.values.reversed.toList(); // best on top
    final spoken = [
      for (final p in points) 'Day ${p.dayNumber}: ${p.mood.label}',
    ].join(', ');
    return Semantics(
      container: true,
      label: 'Recent moods, oldest first. $spoken',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final mood in moods)
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      Icon(mood.icon, size: 16, color: mood.colorOf(colors)),
                      const SizedBox(width: WinterSpacing.xs),
                      Text(mood.label, style: text.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: WinterSpacing.sm),
          Expanded(
            child: SizedBox(
              height: rowHeight * moods.length,
              child: CustomPaint(
                painter: _MoodTimelinePainter(
                  points: points,
                  rows: moods,
                  rowHeight: rowHeight,
                  grid: colors.glassBorder,
                  colorOf: (mood) => mood.colorOf(colors),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodTimelinePainter extends CustomPainter {
  const _MoodTimelinePainter({
    required this.points,
    required this.rows,
    required this.rowHeight,
    required this.grid,
    required this.colorOf,
  });

  final List<MoodPoint> points;
  final List<Mood> rows;
  final double rowHeight;
  final Color grid;
  final Color Function(Mood) colorOf;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    double rowY(Mood mood) => (rows.indexOf(mood) + 0.5) * rowHeight;
    for (final mood in rows) {
      final y = rowY(mood);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (points.isEmpty) return;
    const dot = 5.0;
    final step = points.length == 1
        ? 0.0
        : (size.width - dot * 2) / (points.length - 1);
    for (final (i, point) in points.indexed) {
      final x = points.length == 1 ? size.width / 2 : dot + step * i;
      canvas.drawCircle(
        Offset(x, rowY(point.mood)),
        dot,
        Paint()..color = colorOf(point.mood),
      );
    }
  }

  @override
  bool shouldRepaint(_MoodTimelinePainter old) =>
      old.points != points || old.grid != grid;
}
