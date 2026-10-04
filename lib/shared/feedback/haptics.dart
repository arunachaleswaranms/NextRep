import 'package:flutter/services.dart';

/// Semantic haptic feedback. Call only after the triggering change has been
/// persisted; haptics never decide anything.
abstract final class Haptics {
  /// A habit was completed.
  static Future<void> habitCompleted() => HapticFeedback.lightImpact();

  /// Today just became a Perfect Day: a short double pulse.
  static Future<void> perfectDay() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.lightImpact();
  }

  /// A level boundary was crossed.
  static Future<void> levelUp() => HapticFeedback.mediumImpact();

  /// Minimum Day was confirmed.
  static Future<void> minimumDay() => HapticFeedback.selectionClick();
}
