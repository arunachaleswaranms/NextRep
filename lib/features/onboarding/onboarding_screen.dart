import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';

/// First launch: what Winter Arc is, in one screen. "Let's Begin" leads to
/// choosing an Arc (Rolling or Seasonal); nothing is stored until one is
/// chosen.
///
/// The explanation scrolls when it doesn't fit; "Let's Begin" is always on
/// screen.
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The explanation scrolls when it doesn't fit (large text,
                // small or landscape screens); the call to action stays put.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                Icons.landscape_rounded,
                                size: 48,
                                color: colors.accentSecondary,
                              ),
                            ),
                            const SizedBox(height: WinterSpacing.md),
                            Text(
                              'WINTER ARC',
                              style: text.labelLarge?.copyWith(
                                color: colors.accentSecondary,
                                letterSpacing: 4,
                              ),
                            ),
                            const SizedBox(height: WinterSpacing.sm),
                            Semantics(
                              header: true,
                              child: Text(
                                '${WinterArcRules.lengthInDays} days to a '
                                'better you.',
                                style: text.displaySmall,
                              ),
                            ),
                            const SizedBox(height: WinterSpacing.md),
                            Text(
                              'Check off a few daily habits. Every day you '
                              'show up earns XP and moves you further up the '
                              'mountain.',
                              style: text.bodyLarge?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: WinterSpacing.lg),
                            const _Point(
                              icon: Icons.tune_rounded,
                              title: 'Your habits',
                              body: 'Start from templates or create your own.',
                            ),
                            const _Point(
                              icon: Icons.calendar_month_rounded,
                              title: 'Your timing',
                              body:
                                  'Begin any day, or join the Seasonal Winter '
                                  'Arc (October 1 – December 31).',
                            ),
                            const _Point(
                              icon: Icons.phone_android_rounded,
                              title: 'Private by design',
                              body:
                                  'Everything stays on this device. No '
                                  'account.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: WinterSpacing.md),
                PrimaryButton(
                  label: "Let's Begin",
                  onPressed: () => context.push(AppRoutes.newArc),
                ),
                const SizedBox(height: WinterSpacing.xs),
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

/// One line of what the app is about: an icon, a short title and a
/// sentence.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.md),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: colors.accentSecondary),
            const SizedBox(width: WinterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  Text(body, style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
