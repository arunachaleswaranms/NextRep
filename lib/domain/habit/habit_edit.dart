import '../../core/errors/app_failure.dart';
import 'habit.dart';
import 'habit_config.dart';

/// A requested change to a habit after the arc has started. Null fields are
/// left unchanged.
final class HabitEdit {
  const HabitEdit({this.title, this.target, this.minimumTarget, this.enabled});

  final String? title;
  final int? target;
  final int? minimumTarget;
  final bool? enabled;
}

abstract final class HabitEditRules {
  static const int maxTitleLength = 40;

  /// Lower bound for a target, per type.
  static int minTargetFor(HabitType type) => switch (type) {
    HabitType.binary || HabitType.count || HabitType.duration => 1,
    HabitType.timeBefore => NightTime.minValue,
  };

  /// Upper bound for a target, per type.
  static int maxTargetFor(HabitType type) => switch (type) {
    HabitType.binary => 1,
    HabitType.count => 50,
    HabitType.duration => 300,
    HabitType.timeBefore => NightTime.maxValue,
  };

  /// Whether [config] is a valid configuration for a habit of [type]: a
  /// target within the type's limits and a Minimum Day target within
  /// `1..target`, equal to the target for a clock-time habit (Minimum Day
  /// doesn't loosen a clock time).
  static bool isValidConfig(HabitType type, HabitConfig config) {
    final target = config.target;
    if (target < minTargetFor(type) || target > maxTargetFor(type)) {
      return false;
    }
    if (type.isClockTime) return config.minimumTarget == target;
    return config.minimumTarget >= 1 && config.minimumTarget <= target;
  }

  /// Validates [edit] against [current] and returns the trimmed title (or
  /// null if unchanged) and the resulting configuration.
  ///
  /// [otherEnabledCount] is the number of other habits enabled today; the
  /// last enabled habit cannot be disabled.
  static ({String? title, HabitConfig config}) apply({
    required Habit habit,
    required HabitConfig current,
    required HabitEdit edit,
    required int otherEnabledCount,
  }) {
    String? title;
    if (edit.title != null) {
      title = edit.title!.trim();
      if (title.isEmpty || title.length > maxTitleLength) {
        throw DomainFailure(
          DomainRule.invalidHabitEdit,
          'Title must be 1..$maxTitleLength characters',
        );
      }
      if (title == habit.title) title = null;
    }

    var config = current.copyWith(
      target: edit.target,
      minimumTarget: edit.minimumTarget,
      enabled: edit.enabled,
    );
    // A clock-time habit keeps the same target on a Minimum Day.
    if (habit.type.isClockTime) {
      config = config.copyWith(minimumTarget: config.target);
    }
    final min = minTargetFor(habit.type);
    final max = maxTargetFor(habit.type);
    if (config.target < min || config.target > max) {
      throw DomainFailure(
        DomainRule.invalidHabitEdit,
        'Target must be $min..$max for "${habit.id}"',
      );
    }
    if (config.minimumTarget < 1 || config.minimumTarget > config.target) {
      throw DomainFailure(
        DomainRule.invalidHabitEdit,
        'Minimum target must be 1..${config.target} for "${habit.id}"',
      );
    }
    if (current.enabled && !config.enabled && otherEnabledCount == 0) {
      throw const DomainFailure(
        DomainRule.lastEnabledHabit,
        'At least one habit must stay enabled',
      );
    }
    return (title: title, config: config);
  }
}
