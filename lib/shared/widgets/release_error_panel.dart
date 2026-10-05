import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// What a widget that failed to build shows in a release build, in place
/// of Flutter's error box: the app's night background, a quiet icon and the
/// generic message. It never shows the exception.
///
/// It may be built without a theme (the failure can be above it), so it
/// uses the token values directly.
class ReleaseErrorPanel extends StatelessWidget {
  const ReleaseErrorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = WinterColors.night;
    return ColoredBox(
      color: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(WinterSpacing.md),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.textSecondary,
                  size: 32,
                  semanticLabel: 'Error',
                ),
                const SizedBox(height: WinterSpacing.sm),
                Text(
                  'Something went wrong. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
