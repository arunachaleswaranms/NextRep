import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import 'setup_labels.dart';

/// "Save for Later" from Habit Setup, Review Setup or Confirm & Start.
///
/// Every setup change was already committed when it was made, so this
/// writes nothing, starts nothing and schedules nothing: it confirms (a
/// snackbar, which screen readers announce as a live region) and opens the
/// saved-setup hub, replacing the setup screens. Safe to repeat, and
/// available with zero habits.
void saveForLater(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(SetupLabels.saved), Text(SetupLabels.savedDetail)],
        ),
      ),
    );
  context.go(AppRoutes.savedSetup);
}

/// Back from a setup screen pushed over another one; when it was opened
/// directly (a restored location, a deep link) there is nothing beneath,
/// so it goes to [fallback] instead of leaving the app.
void setupBack(BuildContext context, {required String fallback}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// The width setup screens keep their content to (spec § 9: 600 dp), and
/// the side padding that centres it in [maxWidth].
abstract final class SetupLayout {
  static const maxContentWidth = 600.0;

  static double side(double maxWidth) =>
      maxWidth > maxContentWidth + 2 * WinterSpacing.lg
      ? (maxWidth - maxContentWidth) / 2
      : WinterSpacing.lg;

  /// Above 1.3× text, side-by-side rows stack.
  static bool largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.3;
}
