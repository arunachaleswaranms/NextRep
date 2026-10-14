import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/focus_guard/focus_guard_platform.dart';
import '../../domain/focus_guard/focus_guard_service.dart';
import '../../domain/focus_guard/focus_guard_settings.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'focus_guard_controller.dart';

/// "45 min", "1 h", "1 h 30 min".
String formatBudget(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

/// Focus Guard's settings: on / off, Usage Access, notifications, the apps
/// and their combined daily budget. Off by default; nothing here asks for a
/// permission or opens system settings except on the user's tap.
class FocusGuardSettingsScreen extends ConsumerStatefulWidget {
  const FocusGuardSettingsScreen({super.key});

  @override
  ConsumerState<FocusGuardSettingsScreen> createState() =>
      _FocusGuardSettingsScreenState();
}

class _FocusGuardSettingsScreenState
    extends ConsumerState<FocusGuardSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  FocusGuardSettingsController get _controller =>
      ref.read(focusGuardSettingsProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Usage Access or notifications may have changed in system settings.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool on) async {
    final result = await _controller.setEnabled(on);
    if (!mounted) return;
    final message = switch (result) {
      ActionSuccess(value: FocusGuardToggle.onWithoutNudges) =>
        "Focus Guard is on. Notifications are off, so it can measure but "
            "can't send its reminder.",
      ActionSuccess(value: FocusGuardToggle.needsUsageAccess) =>
        'Allow Usage Access first, so Focus Guard can measure.',
      ActionSuccess(value: FocusGuardToggle.needsApps) =>
        'Choose at least one app first.',
      ActionSuccess(value: FocusGuardToggle.unsupported) =>
        "Focus Guard isn't available on this device.",
      ActionSuccess() => null,
      ActionFailure(:final failure) => userMessageFor(failure),
    };
    if (message != null) _snack(message);
  }

  Future<void> _editBudget(int current) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => _BudgetDialog(initial: current),
    );
    if (minutes == null || minutes == current || !mounted) return;
    final result = await _controller.setDailyBudget(minutes);
    if (!mounted) return;
    if (result case ActionFailure(:final failure)) {
      _snack(userMessageFor(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(focusGuardSettingsProvider);
    // Keep showing the last state while a save re-reads.
    final value = settings.hasError ? null : settings.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Guard'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch (settings) {
            _ when value != null => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(focusGuardSettingsProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, FocusGuardSettingsView view) {
    final status = view.status;
    final settings = status.settings;
    if (!status.supported) {
      return ListView(
        padding: const EdgeInsets.all(WinterSpacing.md),
        children: const [
          _Intro(),
          SizedBox(height: WinterSpacing.md),
          _Notice(
            icon: Icons.info_outline_rounded,
            message: 'Focus Guard is available on Android.',
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.md),
      children: [
        const _Intro(),
        const SizedBox(height: WinterSpacing.md),
        _SwitchCard(status: status, onToggle: _toggle),
        const SizedBox(height: WinterSpacing.md),
        _Section(title: 'Usage Access'),
        _UsageAccessCard(
          granted: status.access == UsageAccess.granted,
          onOpen: _controller.openUsageAccessSettings,
        ),
        const SizedBox(height: WinterSpacing.md),
        _Section(title: 'Notifications'),
        _NotificationsCard(allowed: status.nudgesAllowed),
        const SizedBox(height: WinterSpacing.md),
        _Section(title: 'Apps'),
        _AppsCard(
          selected: settings.selectedPackages,
          labels: view.labels,
          onChoose: () => context.push(AppRoutes.focusGuardApps),
        ),
        const SizedBox(height: WinterSpacing.md),
        _Section(title: 'Daily budget'),
        _BudgetCard(
          minutes: settings.dailyBudgetMinutes,
          onEdit: () => _editBudget(settings.dailyBudgetMinutes),
        ),
        const SizedBox(height: WinterSpacing.md),
        const _HowItWorks(),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FOCUS GUARD',
            style: text.labelLarge?.copyWith(
              color: colors.accentSecondary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text(
            'Stay aware of time spent in selected apps.',
            style: text.titleMedium,
          ),
          const SizedBox(height: WinterSpacing.sm),
          Text(
            'Focus Guard sends a gentle reminder when your selected apps '
            'reach their combined daily budget.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: WinterSpacing.xs),
          Text('It does not block apps.', style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinterSpacing.xs,
      0,
      WinterSpacing.xs,
      WinterSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({required this.status, required this.onToggle});

  final FocusGuardStatus status;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settings = status.settings;
    final enabled = settings.enabled;
    final subtitle = switch (status) {
      _ when enabled && status.monitoring => 'On. Checking in the background.',
      _ when enabled && status.access != UsageAccess.granted =>
        'On, but paused: Usage Access is off.',
      _ when enabled => 'On, but paused: no apps are chosen.',
      _ when status.canEnable => 'Off.',
      _ =>
        'Allow Usage Access and choose at least one app to turn Focus Guard '
            'on.',
    };
    return WinterCard(
      padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
      child: SwitchListTile(
        value: enabled,
        // It can always be turned off; on needs what it measures with.
        onChanged: enabled || status.canEnable ? onToggle : null,
        title: Text('Focus Guard', style: text.titleMedium),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _UsageAccessCard extends StatelessWidget {
  const _UsageAccessCard({required this.granted, required this.onOpen});

  final bool granted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                granted
                    ? Icons.check_circle_outline_rounded
                    : Icons.lock_outline_rounded,
                color: granted ? colors.success : colors.warning,
              ),
              const SizedBox(width: WinterSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      granted ? 'Allowed' : 'Not allowed',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      granted
                          ? "Focus Guard can measure today's time in your "
                                'chosen apps.'
                          : 'Focus Guard needs Usage Access to measure time '
                                'in your chosen apps. Android shows it as a '
                                'switch in system settings.',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WinterSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                granted ? 'Manage Usage Access' : 'Allow Usage Access',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.allowed});

  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allowed
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: allowed ? colors.success : colors.warning,
          ),
          const SizedBox(width: WinterSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(allowed ? 'On' : 'Off', style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  allowed
                      ? 'Focus Guard can send its one reminder a day.'
                      : "Focus Guard can still measure, but can't send its "
                            'reminder. You can turn notifications on for '
                            'NextRep in system settings.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: WinterSpacing.xs),
                Text(
                  'Usage Access lets Focus Guard measure; notifications let '
                  'it remind you. They are separate.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppsCard extends StatelessWidget {
  const _AppsCard({
    required this.selected,
    required this.labels,
    required this.onChoose,
  });

  final List<String> selected;
  final Map<String, String>? labels;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WinterSpacing.md,
                WinterSpacing.sm,
                WinterSpacing.md,
                0,
              ),
              child: Text(
                'No apps chosen yet. Only the apps you choose are measured.',
                style: text.bodyMedium,
              ),
            ),
          for (final package in selected)
            ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: Text(labels?[package] ?? package),
              subtitle: labels != null && !labels!.containsKey(package)
                  ? Text(
                      'Not installed',
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    )
                  : null,
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.sm),
              child: TextButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.checklist_rounded),
                label: Text(selected.isEmpty ? 'Choose apps' : 'Edit apps'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.minutes, required this.onEdit});

  final int minutes;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = formatBudget(minutes);
    return WinterCard(
      padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
      // Read as one control: "Combined daily budget, 1 h".
      child: Semantics(
        container: true,
        button: true,
        label: 'Combined daily budget, $shown',
        onTap: onEdit,
        excludeSemantics: true,
        child: ListTile(
          onTap: onEdit,
          leading: const Icon(Icons.hourglass_bottom_rounded),
          title: const Text('Combined daily budget'),
          subtitle: const Text('Shared by all chosen apps.'),
          trailing: Text(shown, style: text.titleMedium),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line(String value) => Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.sm),
      child: Text(value, style: text.bodyMedium),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Section(title: 'How it works'),
        WinterCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(
                'Android checks usage in the background when it can. Checks '
                'are usually around 15 minutes apart, but your device may '
                'delay them.',
              ),
              line(
                'If NextRep is force-stopped, checks resume when you open it '
                'again.',
              ),
              line(
                'At most one reminder a day. Reaching the budget never '
                'affects your habits, XP or streaks.',
              ),
              Text(
                "Today's time is read from Android when needed. It is never "
                'stored as history or sent anywhere.',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => WinterCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.winter.textSecondary),
        const SizedBox(width: WinterSpacing.md),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}

/// Picks the combined daily budget: common choices, or any whole number of
/// minutes from 1 to 1440. Returns null if cancelled.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.initial});

  final int initial;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  static const _presets = [15, 30, 45, 60, 90, 120, 180, 240];

  late final _field = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_field.text.trim());

  void _submit() {
    final value = _value;
    if (value == null || !FocusGuardRules.isValidBudget(value)) {
      setState(
        () => _error =
            'Enter 1 to ${FocusGuardRules.maxDailyBudgetMinutes} '
            'minutes.',
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final current = _value;
    return AlertDialog(
      title: const Text('Combined daily budget'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('One budget, shared by all chosen apps.'),
          const SizedBox(height: WinterSpacing.md),
          Wrap(
            spacing: WinterSpacing.sm,
            runSpacing: WinterSpacing.sm,
            children: [
              for (final minutes in _presets)
                ChoiceChip(
                  label: Text(formatBudget(minutes)),
                  selected: current == minutes,
                  onSelected: (_) => setState(() {
                    _field.text = '$minutes';
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: WinterSpacing.md),
          TextField(
            controller: _field,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: 'Minutes per day',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
