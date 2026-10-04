import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// A habit's icon in its accent colour, keyed by `Habit.iconKey`. Custom
/// artwork can replace the mapping later without changing the domain.
class HabitIcon extends StatelessWidget {
  const HabitIcon({
    super.key,
    required this.iconKey,
    this.active = false,
    this.accent,
  });

  final String iconKey;

  /// Fills the badge (e.g. when completed) and adds a small check.
  final bool active;

  /// Defaults to the habit's accent from [WinterHabitAccents].
  final Color? accent;

  static const Map<String, IconData> _icons = {
    'workout': Icons.fitness_center_rounded,
    'water': Icons.water_drop_rounded,
    'learning': Icons.menu_book_rounded,
    'english': Icons.translate_rounded,
    'no_junk_food': Icons.no_food_rounded,
    'sleep': Icons.bedtime_rounded,
    'meditation': Icons.self_improvement_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final tint = accent ?? WinterHabitAccents.of(iconKey);
    return SizedBox.square(
      dimension: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: context.motion.standard,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: active ? 0.28 : 0.14),
              borderRadius: BorderRadius.circular(WinterRadii.button),
              border: Border.all(
                color: tint.withValues(alpha: active ? 0.8 : 0.3),
              ),
            ),
            child: Icon(
              _icons[iconKey] ?? Icons.check_circle_outline_rounded,
              color: tint,
            ),
          ),
          if (active)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: colors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
