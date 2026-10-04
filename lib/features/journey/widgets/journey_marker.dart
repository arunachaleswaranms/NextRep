import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/journey_day.dart';
import 'journey_day_style.dart';

/// One day on the Journey path. Tappable (read-only detail) unless future.
class JourneyMarker extends StatelessWidget {
  const JourneyMarker({super.key, required this.day, this.onTap});

  final JourneyDay day;
  final VoidCallback? onTap;

  /// Width and height reserved for any marker (a 52 dp target).
  static const double extent = 56;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final state = day.state;
    final color = state.color(colors);
    final size = state.size;
    final radius = state.square
        ? BorderRadius.circular(size * 0.3)
        : BorderRadius.circular(size);
    final foreground = state.fill == MarkerFill.full
        ? colors.background
        : day.isFuture
        ? colors.textSecondary
        : colors.textPrimary;
    final textStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: foreground, fontWeight: FontWeight.w800);

    return Semantics(
      container: true,
      button: onTap != null,
      label:
          'Day ${day.dayNumber}, ${state.label}${day.isToday ? ', today' : ''}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: extent,
        child: Center(
          child: AnimatedOpacity(
            duration: context.motion.standard,
            opacity: state.opacity,
            child: AnimatedContainer(
              duration: context.motion.standard,
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: radius,
                color: switch (state.fill) {
                  MarkerFill.full => color,
                  MarkerFill.half => null,
                  MarkerFill.none =>
                    day.isToday
                        ? colors.accent.withValues(alpha: 0.35)
                        : colors.skyTop.withValues(alpha: 0.6),
                },
                gradient: state.fill == MarkerFill.half
                    ? LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          color.withValues(alpha: 0.55),
                          color.withValues(alpha: 0.55),
                          colors.skyTop.withValues(alpha: 0.7),
                          colors.skyTop.withValues(alpha: 0.7),
                        ],
                        stops: const [0, 0.5, 0.5, 1],
                      )
                    : null,
                border: Border.all(
                  color: day.isToday
                      ? colors.snow
                      : color.withValues(alpha: day.isFuture ? 0.6 : 0.9),
                  width: day.isToday ? 3 : 1.4,
                ),
                boxShadow: [
                  if (state.glows || day.isToday)
                    BoxShadow(
                      color: (day.isToday ? colors.accentSecondary : color)
                          .withValues(alpha: 0.5),
                      blurRadius: day.isToday ? 18 : 12,
                    ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  child: Center(
                    child: state.icon == null
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Text('${day.dayNumber}', style: textStyle),
                            ),
                          )
                        : Icon(state.icon, size: size * 0.5, color: foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
