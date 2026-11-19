import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/arc_calendar.dart';
import '../../../domain/journey/journey_day.dart';
import '../calendar_labels.dart';
import 'journey_day_style.dart';

/// The outline colour of a calendar glyph in [state]: the state's Journey
/// colour ([JourneyDayStyle.color]), except where that is the low-contrast
/// `outline` token (upcoming, before joining, not reached), which becomes
/// `textSecondary` so every outline reaches 3:1 against the calendar's
/// `surface` (spec § 8.3, A12). Always drawn at full opacity.
Color calendarOutlineColor(JourneyDayState state, WinterColors colors) {
  final color = state.color(colors);
  return color == colors.outline ? colors.textSecondary : color;
}

/// How much a calendar glyph's fill is dimmed: the Journey's
/// [JourneyDayStyle.opacity], or none with the platform's high contrast.
/// Only the fill: the day number, the outline and the label never are.
double calendarFillOpacity(
  JourneyDayState state, {
  required bool highContrast,
}) => highContrast ? 1 : state.opacity;

/// One day of the Arc Consistency Calendar: its Arc day number above its
/// state glyph. Every cell of a line is the same size; the whole cell is
/// the touch target (at least 48 × 48 dp).
///
/// Read-only: [onTap] opens the existing day detail or before-joining
/// note. Without one (upcoming and not-reached days) the cell is not a
/// button and is not focusable.
class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.day,
    required this.width,
    this.onTap,
  });

  final CalendarDay day;
  final double width;
  final VoidCallback? onTap;

  /// The minimum touch target (Android's 48 dp).
  static const double minExtent = 48;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final journeyDay = day.journeyDay;
    final today = journeyDay.isToday;
    final number = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: today ? colors.snow : colors.textPrimary,
      fontWeight: today ? FontWeight.w900 : FontWeight.w700,
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: calendarDayLabel(journeyDay),
      // The tap is repeated here: the excluded child's own action is not
      // exposed to assistive technologies.
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: math.max(width, minExtent),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(WinterRadii.button),
            focusColor: colors.accent.withValues(alpha: 0.35),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minExtent),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Always shown, never dimmed, even under an icon.
                    Text(
                      '${day.dayNumber}',
                      maxLines: 1,
                      softWrap: false,
                      style: number,
                    ),
                    const SizedBox(height: 2),
                    CalendarGlyph(state: day.state, isToday: today),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A day's state as a small glyph, from the same [JourneyDayStyle] as the
/// Journey's markers: shape (circle, or rounded square for a Minimum Day),
/// fill (none, half, full), icon (star, flame, dash) and a dashed outline
/// before joining. Unlike a Journey marker it is the same size in every
/// state, and only its fill is dimmed.
///
/// Today, whatever its state, also gets the Journey's 3 dp `snow` border
/// and a static glow. The state is never replaced by "today".
class CalendarGlyph extends StatelessWidget {
  const CalendarGlyph({super.key, required this.state, required this.isToday});

  final JourneyDayState state;
  final bool isToday;

  static const double size = 26;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final color = state.color(colors);
    final outline = isToday ? colors.snow : calendarOutlineColor(state, colors);
    final fill = calendarFillOpacity(
      state,
      highContrast: MediaQuery.highContrastOf(context),
    );
    final radius = state.square
        ? BorderRadius.circular(size * 0.3)
        : BorderRadius.circular(size);
    final icon = state.icon;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: switch (state.fill) {
            MarkerFill.full => color.withValues(alpha: fill),
            MarkerFill.half => null,
            MarkerFill.none =>
              isToday ? colors.accent.withValues(alpha: 0.35 * fill) : null,
          },
          gradient: state.fill == MarkerFill.half
              ? LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color.withValues(alpha: 0.55 * fill),
                    color.withValues(alpha: 0.55 * fill),
                    color.withValues(alpha: 0),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 0.5, 1],
                )
              : null,
          // A dashed outline is painted instead (below).
          border: state.dashed
              ? null
              : Border.all(color: outline, width: isToday ? 3 : 1.5),
          boxShadow: [
            if (state.glows || isToday)
              BoxShadow(
                color: (isToday ? colors.accentSecondary : color).withValues(
                  alpha: 0.5,
                ),
                blurRadius: isToday ? 12 : 8,
              ),
          ],
        ),
        child: CustomPaint(
          painter: state.dashed ? DashedOutlinePainter(outline) : null,
          child: icon == null
              ? null
              : Center(
                  child: Icon(
                    icon,
                    size: size * 0.6,
                    color: state.fill == MarkerFill.full
                        ? colors.background
                        : outline,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A dashed circle outline at full opacity, for days before the user
/// joined.
class DashedOutlinePainter extends CustomPainter {
  const DashedOutlinePainter(this.color);

  final Color color;

  static const _dashes = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    const sweep = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect.deflate(0.75), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(DashedOutlinePainter old) => old.color != color;
}
