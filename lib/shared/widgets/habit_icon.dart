import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// Placeholder icon for a habit, keyed by `Habit.iconKey`. Custom artwork
/// replaces the mapping later without changing the domain.
class HabitIcon extends StatelessWidget {
  const HabitIcon({super.key, required this.iconKey, this.active = false});

  final String iconKey;

  /// Tints the badge with the success colour (e.g. when completed).
  final bool active;

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
    final tint = active ? colors.success : colors.accent;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(WinterRadii.button),
      ),
      child: Icon(
        _icons[iconKey] ?? Icons.check_circle_outline_rounded,
        color: tint,
      ),
    );
  }
}
