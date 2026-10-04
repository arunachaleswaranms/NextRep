import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';

/// First launch: what Winter Arc is. "Let's Begin" leads to choosing an
/// Arc (Rolling or Seasonal); nothing is stored until one is chosen.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: WinterBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 2),
                Icon(
                  Icons.ac_unit_rounded,
                  size: 56,
                  color: colors.accentSecondary,
                ),
                const SizedBox(height: WinterSpacing.lg),
                Text(
                  'WINTER ARC',
                  style: text.labelLarge?.copyWith(
                    color: colors.accentSecondary,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: WinterSpacing.sm),
                Text(
                  '${WinterArcRules.lengthInDays} days to a better you.',
                  style: text.displaySmall,
                ),
                const SizedBox(height: WinterSpacing.lg),
                for (final line in const [
                  'Small daily actions.',
                  'Real progress.',
                  'A stronger you.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
                    child: Text(
                      line,
                      style: text.titleMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const Spacer(flex: 3),
                PrimaryButton(
                  label: "Let's Begin",
                  onPressed: () => context.push(AppRoutes.newArc),
                ),
                const SizedBox(height: WinterSpacing.sm),
                // A returning user on a new device starts from a backup.
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push(AppRoutes.dataBackup),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded),
                    label: const Text('Restore from a backup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
