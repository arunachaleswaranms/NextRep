import 'package:flutter/material.dart';

/// Semantic colour tokens for the Winter Arc look.
///
/// Widgets read colours through `context.winter` and never use raw colour
/// literals, so the palette can evolve (glass cards, glows) in one place.
@immutable
class WinterColors extends ThemeExtension<WinterColors> {
  const WinterColors({
    required this.background,
    required this.backgroundTop,
    required this.surface,
    required this.surfaceElevated,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentSecondary,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const night = WinterColors(
    background: Color(0xFF070B18),
    backgroundTop: Color(0xFF0E1A33),
    surface: Color(0xFF111A2E),
    surfaceElevated: Color(0xFF1A2642),
    outline: Color(0xFF26355A),
    textPrimary: Color(0xFFF2F6FF),
    textSecondary: Color(0xFF8D9BB8),
    accent: Color(0xFF4C9BFF),
    accentSecondary: Color(0xFF3DE0FF),
    success: Color(0xFF3DDC97),
    warning: Color(0xFFFFB547),
    danger: Color(0xFFFF5C8A),
  );

  /// App background (deep navy / near-black).
  final Color background;

  /// Top of the background gradient.
  final Color backgroundTop;

  /// Cards and list rows.
  final Color surface;

  /// Surfaces raised above [surface] (sheets, pressed states).
  final Color surfaceElevated;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;

  /// Primary accent (bright winter blue).
  final Color accent;

  /// Secondary accent (cyan) used for progress.
  final Color accentSecondary;
  final Color success;
  final Color warning;
  final Color danger;

  @override
  WinterColors copyWith({
    Color? background,
    Color? backgroundTop,
    Color? surface,
    Color? surfaceElevated,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? accentSecondary,
    Color? success,
    Color? warning,
    Color? danger,
  }) => WinterColors(
    background: background ?? this.background,
    backgroundTop: backgroundTop ?? this.backgroundTop,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    outline: outline ?? this.outline,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    accentSecondary: accentSecondary ?? this.accentSecondary,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  WinterColors lerp(WinterColors? other, double t) {
    if (other == null) return this;
    return WinterColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Spacing scale (logical pixels).
abstract final class WinterSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Corner radii.
abstract final class WinterRadii {
  static const double card = 20;
  static const double button = 16;
  static const double pill = 999;
}

extension WinterThemeContext on BuildContext {
  WinterColors get winter => Theme.of(this).extension<WinterColors>()!;
}
