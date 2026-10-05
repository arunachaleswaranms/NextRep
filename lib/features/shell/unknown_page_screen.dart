import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../shared/widgets/winter_background.dart';

/// Shown for a location the router doesn't know: a way back home, without
/// any technical detail.
class UnknownPageScreen extends StatelessWidget {
  const UnknownPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WinterSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.landscape_outlined,
                    size: 48,
                    color: colors.warning,
                  ),
                  const SizedBox(height: WinterSpacing.md),
                  Text(
                    "That page isn't available.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: WinterSpacing.lg),
                  FilledButton(
                    // /today resolves to the right home for the arcs on the
                    // device (setup, summary or onboarding).
                    onPressed: () => context.go(AppRoutes.today),
                    child: const Text('Go home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
