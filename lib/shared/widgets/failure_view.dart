import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/app_failure.dart';
import '../formatting/failure_messages.dart';

/// Full-screen failure state with a retry action.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WinterSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colors.warning),
            const SizedBox(height: WinterSpacing.md),
            Text(
              userMessageFor(failure),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: WinterSpacing.lg),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
