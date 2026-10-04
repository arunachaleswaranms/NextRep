import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/winter_background.dart';
import 'onboarding_controller.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  Future<void> _begin(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(onboardingControllerProvider.notifier)
        .begin();
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess():
        context.go(AppRoutes.habitSetup);
      case ActionFailure(:final failure):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(onboardingControllerProvider);
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
                  busy: busy,
                  onPressed: () => _begin(context, ref),
                ),
                const SizedBox(height: WinterSpacing.sm),
                // A returning user on a new device starts from a backup.
                Center(
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => context.push(AppRoutes.dataBackup),
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
