import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../formatting/failure_messages.dart';

/// Full-screen failure state with a way forward: "Try again" for a failure
/// that may pass, or "Go home" when the arc on screen no longer exists
/// (e.g. a link to an arc that was deleted, or replaced by a restore).
/// A pushed screen also offers "Go back", so a failure is never a dead end.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  /// The arc this screen was opened for is not on the device.
  bool get _arcGone => switch (failure) {
    DomainFailure(rule: DomainRule.sessionNotFound) => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final router = GoRouter.maybeOf(context);
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final goHome = _arcGone && router != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WinterSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _arcGone ? Icons.landscape_outlined : Icons.error_outline_rounded,
              size: 48,
              color: colors.warning,
            ),
            const SizedBox(height: WinterSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                _arcGone
                    ? 'This Winter Arc is no longer on this device.'
                    : userMessageFor(failure),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: WinterSpacing.lg),
            if (goHome)
              FilledButton(
                // The redirect sends /today on to the right home when no
                // arc is running (setup, the latest summary or onboarding).
                onPressed: () => router.go(AppRoutes.today),
                child: const Text('Go home'),
              )
            else
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            if (canPop && !goHome) ...[
              const SizedBox(height: WinterSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
