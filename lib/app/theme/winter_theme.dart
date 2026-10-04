import 'package:flutter/material.dart';

import 'winter_tokens.dart';

/// Builds the app's dark Winter Arc theme from the semantic tokens.
ThemeData buildWinterTheme([WinterColors colors = WinterColors.night]) {
  final scheme = ColorScheme.dark(
    primary: colors.accent,
    onPrimary: colors.textPrimary,
    secondary: colors.accentSecondary,
    onSecondary: colors.background,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerHighest: colors.surfaceElevated,
    outline: colors.outline,
    error: colors.danger,
    onError: colors.textPrimary,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    extensions: [colors],
  );

  final text = base.textTheme.apply(
    bodyColor: colors.textPrimary,
    displayColor: colors.textPrimary,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(color: colors.textSecondary),
      labelLarge: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.textPrimary,
        disabledBackgroundColor: colors.surfaceElevated,
        disabledForegroundColor: colors.textSecondary,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinterRadii.button),
        ),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.glassBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinterRadii.button),
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.backgroundTop,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.skyTop,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.accentSecondary.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.accentSecondary
              : colors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      dragHandleColor: colors.textSecondary.withValues(alpha: 0.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.textPrimary
            : colors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.surfaceElevated,
      ),
      trackOutlineColor: WidgetStatePropertyAll(colors.outline),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.surfaceElevated,
      contentTextStyle: text.bodyMedium?.copyWith(color: colors.textPrimary),
      actionTextColor: colors.accentSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WinterRadii.button),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accentSecondary,
      linearTrackColor: colors.surfaceElevated,
      circularTrackColor: colors.surfaceElevated,
    ),
  );
}
