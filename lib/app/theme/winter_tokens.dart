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
    required this.recovery,
    required this.celebration,
    required this.glass,
    required this.glassBorder,
    required this.skyTop,
    required this.skyHorizon,
    required this.mountainFar,
    required this.mountainMid,
    required this.mountainNear,
    required this.snow,
    required this.fog,
    required this.auroraGreen,
    required this.auroraViolet,
    required this.warmLight,
    required this.ember,
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
    recovery: Color(0xFFFF9F5A),
    celebration: Color(0xFFFFD166),
    glass: Color(0xB3101A30),
    glassBorder: Color(0x3DA9C7FF),
    skyTop: Color(0xFF04070F),
    skyHorizon: Color(0xFF1C365E),
    mountainFar: Color(0xFF1E3157),
    mountainMid: Color(0xFF142342),
    mountainNear: Color(0xFF0A1326),
    snow: Color(0xFFE3EDFF),
    fog: Color(0xFF9DBDEB),
    auroraGreen: Color(0xFF4DF2C4),
    auroraViolet: Color(0xFF8A7CFF),
    warmLight: Color(0xFFFFB45C),
    ember: Color(0xFFFF7A3D),
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

  /// Warm accent for Minimum Day (recovery, not failure).
  final Color recovery;

  /// Perfect Day and level-up highlights.
  final Color celebration;

  // Winter scene and glass surfaces.

  /// Translucent glass surface for cards over the scene.
  final Color glass;

  /// Hairline border of glass surfaces.
  final Color glassBorder;

  /// Night sky at the zenith.
  final Color skyTop;

  /// Night sky at the horizon (cold blue glow).
  final Color skyHorizon;

  /// Distant mountain range.
  final Color mountainFar;

  /// Middle ridge.
  final Color mountainMid;

  /// Foreground hills and forest.
  final Color mountainNear;

  /// Snowcaps, snowfall and the frozen trail.
  final Color snow;

  /// Atmospheric fog (used translucent).
  final Color fog;

  /// Aurora, main band.
  final Color auroraGreen;

  /// Aurora, upper fringe.
  final Color auroraViolet;

  /// Warm amber light of camps and the summit shelter.
  final Color warmLight;

  /// Campfire embers.
  final Color ember;

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
    Color? recovery,
    Color? celebration,
    Color? glass,
    Color? glassBorder,
    Color? skyTop,
    Color? skyHorizon,
    Color? mountainFar,
    Color? mountainMid,
    Color? mountainNear,
    Color? snow,
    Color? fog,
    Color? auroraGreen,
    Color? auroraViolet,
    Color? warmLight,
    Color? ember,
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
    recovery: recovery ?? this.recovery,
    celebration: celebration ?? this.celebration,
    glass: glass ?? this.glass,
    glassBorder: glassBorder ?? this.glassBorder,
    skyTop: skyTop ?? this.skyTop,
    skyHorizon: skyHorizon ?? this.skyHorizon,
    mountainFar: mountainFar ?? this.mountainFar,
    mountainMid: mountainMid ?? this.mountainMid,
    mountainNear: mountainNear ?? this.mountainNear,
    snow: snow ?? this.snow,
    fog: fog ?? this.fog,
    auroraGreen: auroraGreen ?? this.auroraGreen,
    auroraViolet: auroraViolet ?? this.auroraViolet,
    warmLight: warmLight ?? this.warmLight,
    ember: ember ?? this.ember,
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
      recovery: Color.lerp(recovery, other.recovery, t)!,
      celebration: Color.lerp(celebration, other.celebration, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      skyTop: Color.lerp(skyTop, other.skyTop, t)!,
      skyHorizon: Color.lerp(skyHorizon, other.skyHorizon, t)!,
      mountainFar: Color.lerp(mountainFar, other.mountainFar, t)!,
      mountainMid: Color.lerp(mountainMid, other.mountainMid, t)!,
      mountainNear: Color.lerp(mountainNear, other.mountainNear, t)!,
      snow: Color.lerp(snow, other.snow, t)!,
      fog: Color.lerp(fog, other.fog, t)!,
      auroraGreen: Color.lerp(auroraGreen, other.auroraGreen, t)!,
      auroraViolet: Color.lerp(auroraViolet, other.auroraViolet, t)!,
      warmLight: Color.lerp(warmLight, other.warmLight, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
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

/// Habit accent colours, keyed by `Habit.iconKey`: colourful but
/// restrained, used for a habit's icon and progress.
abstract final class WinterHabitAccents {
  static const Map<String, Color> _byIconKey = {
    'workout': Color(0xFFFF8A6B),
    'water': Color(0xFF5CC8FF),
    'learning': Color(0xFFB4A2FF),
    'english': Color(0xFF4FD8C6),
    'no_junk_food': Color(0xFF86E3A6),
    'sleep': Color(0xFF8FA2FF),
    'meditation': Color(0xFFF59AC0),
    'journal': Color(0xFFFFC37A),
    'walk': Color(0xFF7FD4A0),
    'music': Color(0xFFE59BFF),
    'code': Color(0xFF7FB8FF),
    'nature': Color(0xFF9BD67F),
    'heart': Color(0xFFFF8FA3),
    'star': Color(0xFFFFD66B),
  };

  /// The accent of [iconKey], or the primary accent for unknown keys.
  static Color of(String iconKey) =>
      _byIconKey[iconKey] ?? WinterColors.night.accent;
}

/// Animation durations, in four semantic categories. Read them through
/// [WinterMotion] so they collapse to zero when the platform asks for
/// reduced motion.
abstract final class WinterDurations {
  /// Micro feedback: a check, a counter step (100–180 ms).
  static const Duration micro = Duration(milliseconds: 150);

  /// Standard state changes: progress, badges, colour (200–350 ms).
  static const Duration standard = Duration(milliseconds: 300);

  /// Celebrations: Perfect Day warmth, level up, badge reveal (400–700 ms).
  static const Duration celebration = Duration(milliseconds: 600);

  /// How long a celebration card stays up unless dismissed.
  static const Duration celebrationHold = Duration(milliseconds: 3200);

  /// One loop of the ambient scene (snowfall, aurora drift). Multi-second
  /// and seamless; never needed to understand anything.
  static const Duration ambientLoop = Duration(seconds: 24);
}

/// Motion settings for the current context.
final class WinterMotion {
  const WinterMotion._(this.reduced);

  factory WinterMotion.of(BuildContext context) =>
      WinterMotion._(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The user asked the platform to remove or reduce animations. State
  /// changes then apply immediately and ambient scene motion stops.
  final bool reduced;

  Duration get micro => reduced ? Duration.zero : WinterDurations.micro;
  Duration get standard => reduced ? Duration.zero : WinterDurations.standard;
  Duration get celebration =>
      reduced ? Duration.zero : WinterDurations.celebration;

  /// Whether looping ambient motion may run.
  bool get ambient => !reduced;
}

extension WinterThemeContext on BuildContext {
  WinterColors get winter => Theme.of(this).extension<WinterColors>()!;
  WinterMotion get motion => WinterMotion.of(this);
}
