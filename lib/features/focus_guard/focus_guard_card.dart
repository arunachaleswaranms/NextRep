import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../domain/focus_guard/focus_guard_meter.dart';
import '../../domain/focus_guard/focus_guard_service.dart';
import '../../domain/focus_guard/today_usage.dart';
import '../../shared/widgets/winter_card.dart';
import 'focus_guard_controller.dart';

/// Focus Guard on Today: today's combined time in the chosen apps against
/// the budget, or a way to set it up. Tapping opens Focus Guard's settings.
///
/// Omitted where Focus Guard is unsupported (iOS) and until the first read
/// completes, so nothing stale or invented is ever shown: a measurement
/// that fails shows why, never "0 min". Re-read on resume, at midnight and
/// after settings change; never polled.
class FocusGuardCard extends ConsumerStatefulWidget {
  const FocusGuardCard({super.key});

  @override
  ConsumerState<FocusGuardCard> createState() => _FocusGuardCardState();
}

class _FocusGuardCardState extends ConsumerState<FocusGuardCard> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from another app (or system settings): measure again.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(focusGuardTodayProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _open() => context.push(AppRoutes.focusGuard);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(focusGuardTodayProvider);
    return switch (today) {
      AsyncData(:final value) => _forToday(value),
      AsyncError() => _Message(
        icon: Icons.shield_outlined,
        title: 'Focus Guard',
        message: "Today's time couldn't be checked right now.",
        onTap: _open,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _forToday(FocusGuardToday today) {
    final status = today.status;
    if (!status.supported) return const SizedBox.shrink();
    if (!status.settings.enabled) {
      return _Message(
        icon: Icons.shield_outlined,
        title: 'Focus Guard',
        message: 'Stay aware of time spent in selected apps.',
        onTap: _open,
      );
    }
    if (!status.hasApps) {
      return _Message(
        icon: Icons.shield_outlined,
        title: 'Focus Guard',
        message: 'Choose the apps to keep an eye on.',
        onTap: _open,
      );
    }
    return switch (today.usage) {
      UsageMeasured(:final total) => _Meter(
        meter: FocusGuardMeter(
          used: total,
          budgetMinutes: status.settings.dailyBudgetMinutes,
        ),
        nudgesAllowed: status.nudgesAllowed,
        onTap: _open,
      ),
      UsageUnavailable(reason: UsageUnavailableReason.accessRequired) =>
        _Message(
          icon: Icons.lock_outline_rounded,
          title: 'Focus Guard',
          message:
              "Usage Access is off, so today's time can't be measured. "
              'Tap to allow it.',
          onTap: _open,
        ),
      _ => _Message(
        icon: Icons.shield_outlined,
        title: 'Focus Guard',
        message: "Today's time couldn't be read right now.",
        onTap: _open,
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title. $message',
      excludeSemantics: true,
      onTap: onTap,
      child: WinterCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: colors.accentSecondary),
            const SizedBox(width: WinterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(message, style: text.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.meter,
    required this.nudgesAllowed,
    required this.onTap,
  });

  final FocusGuardMeter meter;
  final bool nudgesAllowed;
  final VoidCallback onTap;

  static String stateLabel(FocusGuardShield shield) => switch (shield) {
    FocusGuardShield.strong => 'Shield strong',
    FocusGuardShield.nearLimit => "Near today's limit",
    FocusGuardShield.reached => 'Budget reached',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final shield = meter.shield;
    final accent = switch (shield) {
      FocusGuardShield.strong => colors.accentSecondary,
      FocusGuardShield.nearLimit => colors.warning,
      FocusGuardShield.reached => colors.recovery,
    };
    final amount = '${meter.usedMinutes} / ${meter.budgetMinutes} min';
    final detail = meter.reached
        ? 'Budget reached. Tomorrow is a fresh day.'
        : '${meter.remainingMinutes} min remaining';
    final label = stateLabel(shield);
    // Once reached, [detail] already says so.
    final state = meter.reached ? detail : '$detail. $label.';
    return Semantics(
      button: true,
      label:
          'Focus Guard. ${meter.usedMinutes} of ${meter.budgetMinutes} '
          'minutes used today. $state'
          '${nudgesAllowed ? '' : ' Notifications are off.'}',
      hint: 'Opens Focus Guard settings',
      excludeSemantics: true,
      onTap: onTap,
      child: WinterCard(
        onTap: onTap,
        highlighted: shield != FocusGuardShield.strong,
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'FOCUS GUARD',
                    style: text.labelLarge?.copyWith(
                      color: colors.accentSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                Icon(
                  shield == FocusGuardShield.reached
                      ? Icons.shield_moon_outlined
                      : Icons.shield_outlined,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: WinterSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    style: text.labelLarge?.copyWith(color: accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(amount, style: text.headlineSmall),
            const SizedBox(height: WinterSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(WinterRadii.pill),
              child: LinearProgressIndicator(
                value: meter.fraction,
                minHeight: 6,
                color: accent,
                backgroundColor: colors.glassBorder,
              ),
            ),
            const SizedBox(height: WinterSpacing.sm),
            Text(detail, style: text.bodyMedium),
            if (!nudgesAllowed) ...[
              const SizedBox(height: WinterSpacing.xs),
              Text(
                "Notifications are off, so Focus Guard can't send its "
                'reminder.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
