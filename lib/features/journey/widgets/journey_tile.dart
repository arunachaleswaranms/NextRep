import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/journey_day.dart';

/// Presentation of each [JourneyDayState]: label, colour and icon.
extension JourneyDayStyle on JourneyDayState {
  String get label => switch (this) {
    JourneyDayState.future => 'Upcoming',
    JourneyDayState.today => 'Today',
    JourneyDayState.perfect => 'Perfect',
    JourneyDayState.minimumComplete => 'Minimum complete',
    JourneyDayState.partial => 'Partial',
    JourneyDayState.minimumPartial => 'Minimum partial',
    JourneyDayState.missed => 'Missed',
  };

  Color color(WinterColors colors) => switch (this) {
    JourneyDayState.future => colors.surface,
    JourneyDayState.today => colors.accent,
    JourneyDayState.perfect => colors.celebration,
    JourneyDayState.minimumComplete => colors.recovery,
    JourneyDayState.partial => colors.accentSecondary,
    JourneyDayState.minimumPartial => colors.recovery,
    JourneyDayState.missed => colors.outline,
  };

  /// Whether the tile is filled (a strong outcome) or only tinted.
  bool get filled =>
      this == JourneyDayState.perfect ||
      this == JourneyDayState.minimumComplete;

  IconData? get icon => switch (this) {
    JourneyDayState.perfect => Icons.star_rounded,
    JourneyDayState.minimumComplete => Icons.local_fire_department_rounded,
    _ => null,
  };
}

/// One day on the Journey grid.
class JourneyTile extends StatelessWidget {
  const JourneyTile({super.key, required this.day, this.onTap});

  final JourneyDay day;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final state = day.state;
    final color = state.color(colors);
    final foreground = state.filled
        ? colors.background
        : day.isFuture
        ? colors.textSecondary
        : colors.textPrimary;
    return Semantics(
      button: onTap != null,
      label:
          'Day ${day.dayNumber}, ${state.label}${day.isToday ? ', today' : ''}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motion.standard,
        decoration: BoxDecoration(
          color: state.filled ? color : color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(WinterSpacing.sm + 2),
          border: Border.all(
            color: day.isToday
                ? colors.textPrimary
                : color.withValues(alpha: day.isFuture ? 0.4 : 0.7),
            width: day.isToday ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(WinterSpacing.sm + 2),
            onTap: onTap,
            child: Center(
              child: state.icon == null
                  ? Text(
                      '${day.dayNumber}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Icon(state.icon, size: 18, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
