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

  /// A newly persisted achievement is being revealed.
  static Future<void> achievementUnlocked() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  /// A reflection was saved.
  static Future<void> reflectionSaved() => HapticFeedback.lightImpact();

  /// A setup habit card was picked up, or dropped, by a drag. Gesture
  /// feedback only: the drop's write follows, and its failure has its own
  /// message.
  static Future<void> reorderGrip() => HapticFeedback.lightImpact();
}
