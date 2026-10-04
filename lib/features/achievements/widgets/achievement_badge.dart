import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/winter_tokens.dart';
import '../../../domain/achievement/achievement.dart';

/// Icon and accent of each achievement.
extension AchievementVisuals on AchievementKey {
  IconData get icon => switch (this) {
    AchievementKey.firstRep => Icons.check_rounded,
    AchievementKey.firstPerfect => Icons.star_rounded,
    AchievementKey.streak3 => Icons.ac_unit_rounded,
    AchievementKey.streak7 => Icons.air_rounded,
    AchievementKey.perfect3 => Icons.auto_awesome_rounded,
    AchievementKey.minimumComplete => Icons.local_fire_department_rounded,
    AchievementKey.level2 => Icons.trending_up_rounded,
    AchievementKey.level3 => Icons.bolt_rounded,
    AchievementKey.halfway => Icons.nights_stay_rounded,
    AchievementKey.summit => Icons.landscape_rounded,
    AchievementKey.firstReflection => Icons.edit_note_rounded,
    AchievementKey.reflections7 => Icons.menu_book_rounded,
    AchievementKey.minimum3 => Icons.spa_rounded,
    AchievementKey.perfect10 => Icons.workspace_premium_rounded,
    AchievementKey.level5 => Icons.rocket_launch_rounded,
  };

  Color accent(WinterColors colors) => switch (this) {
    AchievementKey.firstRep => colors.accentSecondary,
    AchievementKey.firstPerfect ||
    AchievementKey.perfect3 ||
    AchievementKey.perfect10 => colors.celebration,
    AchievementKey.streak3 || AchievementKey.level2 => colors.accent,
    AchievementKey.streak7 ||
    AchievementKey.firstReflection ||
    AchievementKey.reflections7 => colors.auroraViolet,
    AchievementKey.minimumComplete ||
    AchievementKey.minimum3 => colors.recovery,
    AchievementKey.level3 ||
    AchievementKey.level5 ||
    AchievementKey.summit => colors.warmLight,
    AchievementKey.halfway => colors.auroraGreen,
  };
}

/// A collectible hexagonal badge. Unlocked badges glow in their accent;
/// locked ones are dark, outlined and show a small lock, so the state never
/// depends on colour alone. Decorative: callers provide the semantics.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.achievement,
    required this.unlocked,
    this.size = 64,
  });

  final AchievementKey achievement;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final accent = achievement.accent(colors);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _HexPainter(
                accent: accent,
                unlocked: unlocked,
                colors: colors,
              ),
            ),
            Icon(
              achievement.icon,
              size: size * 0.42,
              color: unlocked
                  ? colors.background
                  : colors.textSecondary.withValues(alpha: 0.55),
            ),
            if (!unlocked)
              Positioned(
                right: size * 0.06,
                bottom: size * 0.06,
                child: Container(
                  padding: EdgeInsets.all(size * 0.04),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.outline),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: size * 0.18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({
    required this.accent,
    required this.unlocked,
    required this.colors,
  });

  final Color accent;
  final bool unlocked;
  final WinterColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 * 0.92;
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0 ? hex.moveTo(point.dx, point.dy) : hex.lineTo(point.dx, point.dy);
    }
    hex.close();
    final bounds = Offset.zero & size;
    if (unlocked) {
      canvas.drawCircle(
        center,
        radius * 1.08,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..color = accent.withValues(alpha: 0.35),
      );
      canvas.drawPath(
        hex,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(accent, colors.snow, 0.35)!, accent],
          ).createShader(bounds),
      );
      canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.snow.withValues(alpha: 0.6),
      );
    } else {
      canvas.drawPath(hex, Paint()..color = colors.surface);
      canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = colors.outline,
      );
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.accent != accent || old.unlocked != unlocked || old.colors != colors;
}
