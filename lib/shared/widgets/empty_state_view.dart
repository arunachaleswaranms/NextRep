import 'package:flutter/material.dart';

import '../../app/theme/winter_tokens.dart';

/// An intentional "nothing here yet" state: a quiet icon, a title and a
/// line of guidance. Empty is a normal state, never styled as an error.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WinterSpacing.lg),
        child: MergeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: colors.textSecondary),
              const SizedBox(height: WinterSpacing.md),
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
              if (message case final message?) ...[
                const SizedBox(height: WinterSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
