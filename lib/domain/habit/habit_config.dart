import '../../core/time/local_date.dart';
import '../progress/day_mode.dart';
import 'habit.dart';

/// The part of a habit's configuration that can change over the arc.
final class HabitConfig {
  const HabitConfig({
    required this.target,
    required this.minimumTarget,
    required this.enabled,
  });

  /// Target on a normal day.
  final int target;

  /// Target on a Minimum Day.
  final int minimumTarget;

  /// Whether the habit is tracked (and counts towards the day) at all.
  final bool enabled;

  int targetFor(DayMode mode) => switch (mode) {
    DayMode.normal => target,
    DayMode.minimum => minimumTarget,
  };

  HabitConfig copyWith({int? target, int? minimumTarget, bool? enabled}) =>
      HabitConfig(
        target: target ?? this.target,
        minimumTarget: minimumTarget ?? this.minimumTarget,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is HabitConfig &&
      other.target == target &&
      other.minimumTarget == minimumTarget &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(target, minimumTarget, enabled);

  @override
  String toString() =>
      'HabitConfig(target: $target, minimum: $minimumTarget, '
      'enabled: $enabled)';
}

/// A configuration change that applies from [effectiveFrom] onwards, until a
/// later revision of the same habit replaces it.
final class HabitRevision {
  const HabitRevision({
    required this.habitId,
    required this.effectiveFrom,
    required this.config,
    required this.createdAt,
  });

  final String habitId;
  final LocalDate effectiveFrom;
  final HabitConfig config;
  final DateTime createdAt;
}

/// A habit as it applies on one date, in one day mode.
final class PlannedHabit {
  const PlannedHabit({
    required this.habit,
    required this.config,
    required this.target,
  });

  final Habit habit;
  final HabitConfig config;

  /// Effective target for the date: normal or minimum, depending on mode.
  final int target;
}

/// A session's habits plus every dated configuration change.
///
/// This is the history-safe view of habit configuration: the configuration
/// on a date is the latest revision effective on or before that date, or the
/// habit's baseline if there is none. Revisions are only ever written for
/// the current day, so the result for a past date never changes.
final class HabitHistory {
  HabitHistory({
    required List<Habit> habits,
    List<HabitRevision> revisions = const [],
  }) : habits = List.unmodifiable(
         [...habits]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
       ),
       _revisions = _index(revisions);

  /// Every habit of the session, in display order.
  final List<Habit> habits;

  /// Per habit, revisions sorted by [HabitRevision.effectiveFrom].
  final Map<String, List<HabitRevision>> _revisions;

  static Map<String, List<HabitRevision>> _index(List<HabitRevision> all) {
    final byHabit = <String, List<HabitRevision>>{};
    for (final revision in all) {
      byHabit.putIfAbsent(revision.habitId, () => []).add(revision);
    }
    for (final list in byHabit.values) {
      list.sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    }
    return byHabit;
  }

  List<HabitRevision> get revisions => [
    for (final list in _revisions.values) ...list,
  ];

  Habit? habit(String habitId) {
    for (final habit in habits) {
      if (habit.id == habitId) return habit;
    }
    return null;
  }

  /// The configuration of [habit] in effect on [date].
  HabitConfig configOn(Habit habit, LocalDate date) {
    final revisions = _revisions[habit.id];
    if (revisions != null) {
      for (final revision in revisions.reversed) {
        if (!revision.effectiveFrom.isAfter(date)) return revision.config;
      }
    }
    return habit.baseline;
  }

  /// The habits enabled on [date], in display order, with the target that
  /// applies in [mode].
  List<PlannedHabit> planFor(LocalDate date, DayMode mode) => [
    for (final habit in habits)
      if (configOn(habit, date) case final config when config.enabled)
        PlannedHabit(
          habit: habit,
          config: config,
          target: config.targetFor(mode),
        ),
  ];

  /// This history with [revision] added, replacing any revision of the same
  /// habit and date.
  HabitHistory withRevision(HabitRevision revision) => HabitHistory(
    habits: habits,
    revisions: [
      for (final r in revisions)
        if (r.habitId != revision.habitId ||
            r.effectiveFrom != revision.effectiveFrom)
          r,
      revision,
    ],
  );

  /// This history with [habitId] renamed.
  HabitHistory withTitle(String habitId, String title) => HabitHistory(
    habits: [
      for (final h in habits) h.id == habitId ? h.copyWith(title: title) : h,
    ],
    revisions: revisions,
  );
}
