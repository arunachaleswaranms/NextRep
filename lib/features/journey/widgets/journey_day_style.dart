import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/journey/journey_day.dart';

/// How a marker is filled, so states differ by more than colour.
enum MarkerFill { none, half, full }

/// Presentation of each [JourneyDayState]. Every state differs in colour,
/// shape, fill, icon and size, and has a label for screen readers.
extension JourneyDayStyle on JourneyDayState {
  String get label => switch (this) {
    JourneyDayState.notJoined => 'Before you joined',
    JourneyDayState.future => 'Upcoming',
    JourneyDayState.today => 'Today',
    JourneyDayState.perfect => 'Perfect',
    JourneyDayState.minimumComplete => 'Minimum complete',
    JourneyDayState.partial => 'Partial',
    JourneyDayState.minimumPartial => 'Minimum partial',
    JourneyDayState.missed => 'Missed',
  };

  Color color(WinterColors colors) => switch (this) {
    JourneyDayState.notJoined => colors.outline,
    JourneyDayState.future => colors.outline,
    JourneyDayState.today => colors.snow,
    JourneyDayState.perfect => colors.accentSecondary,
    JourneyDayState.minimumComplete => colors.recovery,
    JourneyDayState.partial => colors.accentSecondary,
    JourneyDayState.minimumPartial => colors.recovery,
    JourneyDayState.missed => colors.textSecondary,
  };

  /// Minimum Days are rounded squares; every other day is a circle.
  bool get square =>
      this == JourneyDayState.minimumComplete ||
      this == JourneyDayState.minimumPartial;

  MarkerFill get fill => switch (this) {
    JourneyDayState.perfect ||
    JourneyDayState.minimumComplete => MarkerFill.full,
    JourneyDayState.partial ||
    JourneyDayState.minimumPartial => MarkerFill.half,
    JourneyDayState.notJoined ||
    JourneyDayState.future ||
    JourneyDayState.today ||
    JourneyDayState.missed => MarkerFill.none,
  };

  /// Drawn with a dashed outline: neutral, outside the user's arc.
  bool get dashed => this == JourneyDayState.notJoined;

  /// Shown instead of the day number.
  IconData? get icon => switch (this) {
    JourneyDayState.perfect => Icons.star_rounded,
    JourneyDayState.minimumComplete => Icons.local_fire_department_rounded,
    JourneyDayState.missed => Icons.remove_rounded,
    _ => null,
  };

  /// Marker diameter.
  double get size => switch (this) {
    JourneyDayState.today => 52,
    JourneyDayState.perfect || JourneyDayState.minimumComplete => 40,
    JourneyDayState.partial || JourneyDayState.minimumPartial => 36,
    JourneyDayState.future || JourneyDayState.missed => 30,
    JourneyDayState.notJoined => 26,
  };

  /// Dimmed states.
  double get opacity => switch (this) {
    JourneyDayState.notJoined => 0.45,
    JourneyDayState.future => 0.55,
    JourneyDayState.missed => 0.7,
    _ => 1,
  };

  /// Lit with a soft glow.
  bool get glows =>
      this == JourneyDayState.perfect ||
      this == JourneyDayState.minimumComplete ||
      this == JourneyDayState.today;
}

/// What a screen reader says for a Journey day, e.g. "Day 15. Today. 60
/// percent complete.", "Day 24. Perfect Day." or "Day 8. Before you
/// joined this Seasonal Winter Arc." The state is always in words, never
/// only in the marker's colour or shape.
String journeyDayLabel(JourneyDay day) {
  final percent = day.record?.completion.percent ?? 0;
  final state = switch (day.state) {
    JourneyDayState.notJoined => 'Before you joined this Seasonal Winter Arc.',
    JourneyDayState.future => 'Upcoming.',
    JourneyDayState.today => '$percent percent complete.',
    JourneyDayState.perfect => 'Perfect Day.',
    JourneyDayState.minimumComplete => 'Minimum Day completed.',
    JourneyDayState.partial => 'Partial, $percent percent complete.',
    JourneyDayState.minimumPartial => 'Minimum Day, $percent percent complete.',
    JourneyDayState.missed => 'Missed.',
  };
  return 'Day ${day.dayNumber}. ${day.isToday ? 'Today. ' : ''}$state';
}
