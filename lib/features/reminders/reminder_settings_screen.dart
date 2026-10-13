import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/reminder/reminder_preferences.dart';
import '../../domain/reminder/reminder_service.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'reminder_settings_controller.dart';

/// Optional local reminders: a daily nudge, an evening reflection prompt
/// and Hydration Coach. All are off until turned on here; permission is
/// asked for only then.
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState
    extends ConsumerState<ReminderSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Permission may have been changed in system settings meanwhile.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(reminderSettingsProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Saves [change], applied to the stored preferences rather than the ones
  /// on screen, so quick successive taps don't undo each other.
  Future<void> _save(
    ReminderPreferences Function(ReminderPreferences current) change,
  ) async {
    final result = await ref
        .read(reminderSettingsProvider.notifier)
        .save(change);
    if (!mounted) return;
    final message = switch (result) {
      ActionSuccess(value: ReminderUpdate.permissionDenied) =>
        "Notifications weren't allowed, so the reminder stays off. "
            'You can allow them in system settings at any time.',
      ActionSuccess(value: ReminderUpdate.savedNotScheduled) =>
        "Saved. Reminders couldn't be scheduled just now; NextRep will try "
            'again the next time it opens.',
      ActionSuccess() => null,
      ActionFailure(:final failure) => userMessageFor(failure),
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<ReminderTime?> _pickTime(
    ReminderTime current, {
    String? helpText,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: helpText,
    );
    // The screen may have closed while the picker was open.
    if (picked == null || !mounted) return null;
    return ReminderTime(picked.hour, picked.minute);
  }

  /// Picks Hydration Coach's start and then its end. Nothing is saved
  /// unless both are picked and they make a valid window.
  Future<void> _pickHydrationWindow(HydrationWindow current) async {
    final start = await _pickTime(current.start, helpText: 'Active from');
    if (start == null) return;
    final end = await _pickTime(current.end, helpText: 'Active until');
    if (end == null) return;
    final window = HydrationWindow.tryCreate(start, end);
    if (!mounted) return;
    if (window == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              userMessageFor(
                const DomainFailure(DomainRule.invalidHydrationWindow, ''),
              ),
            ),
          ),
        );
      return;
    }
    await _save((p) => p.copyWith(hydrationWindow: window));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(reminderSettingsProvider);
    // Keep showing the last state while a save re-reads.
    final value = settings.hasError ? null : settings.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch (settings) {
            _ when value != null => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(reminderSettingsProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ReminderSettingsView view) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final prefs = view.preferences;
    return ListView(
      padding: const EdgeInsets.all(WinterSpacing.md),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WinterSpacing.xs),
          child: Text(
            'Optional nudges, scheduled on this device only. Nothing is '
            'sent anywhere.',
            style: text.bodyMedium,
          ),
        ),
        const SizedBox(height: WinterSpacing.md),
        _ReminderCard(
          title: 'Daily reminder',
          description: '"Your Winter Arc is waiting." Opens Today.',
          enabled: prefs.dailyEnabled,
          time: prefs.dailyTime,
          onToggle: (on) => _save((p) => p.copyWith(dailyEnabled: on)),
          onPickTime: () async {
            final time = await _pickTime(prefs.dailyTime);
            if (time != null) await _save((p) => p.copyWith(dailyTime: time));
          },
        ),
        const SizedBox(height: WinterSpacing.sm),
        _ReminderCard(
          title: 'Evening reflection',
          description: '"How did today go?" Opens today\'s reflection.',
          enabled: prefs.reflectionEnabled,
          time: prefs.reflectionTime,
          onToggle: (on) => _save((p) => p.copyWith(reflectionEnabled: on)),
          onPickTime: () async {
            final time = await _pickTime(prefs.reflectionTime);
            if (time != null) {
              await _save((p) => p.copyWith(reflectionTime: time));
            }
          },
        ),
        const SizedBox(height: WinterSpacing.md),
        if (prefs.anyEnabled && !view.permissionGranted)
          _Notice(
            icon: Icons.notifications_off_outlined,
            color: colors.warning,
            message:
                'Notifications are turned off for NextRep in system '
                "settings, so reminders can't appear.",
          ),
        if (!view.arcActive)
          _Notice(
            icon: Icons.info_outline_rounded,
            color: colors.textSecondary,
            message: 'Reminders only arrive while a Winter Arc is running.',
          ),
        const SizedBox(height: WinterSpacing.md),
        _HydrationCard(
          preferences: prefs,
          availability: view.hydration,
          onToggle: (on) => _save((p) => p.copyWith(hydrationEnabled: on)),
          onMode: (mode) => _save((p) => p.copyWith(hydrationMode: mode)),
          onPickWindow: () => _pickHydrationWindow(prefs.hydrationWindow),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.title,
    required this.description,
    required this.enabled,
    required this.time,
    required this.onToggle,
    required this.onPickTime,
  });

  final String title;
  final String description;
  final bool enabled;
  final ReminderTime time;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = TimeOfDay(
      hour: time.hour,
      minute: time.minute,
    ).format(context);
    return WinterCard(
      padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onToggle,
            title: Text(title, style: text.titleMedium),
            subtitle: Text(description),
          ),
          // Read as one control: "Daily reminder time, 8:00 AM".
          Semantics(
            // Its own node, so it never absorbs the switch above it.
            container: true,
            button: true,
            enabled: enabled,
            label: '$title time, $shown',
            onTap: enabled ? onPickTime : null,
            excludeSemantics: true,
            child: ListTile(
              enabled: enabled,
              onTap: onPickTime,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Time'),
              trailing: Text(shown, style: text.titleMedium),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hydration Coach: on / off, how many nudges at most, and when.
///
/// It never asks for a Water goal: it paces against the Arc's own Water
/// target for the day, Minimum Day included. Checkpoint times aren't shown;
/// they move a little from day to day.
class _HydrationCard extends StatelessWidget {
  const _HydrationCard({
    required this.preferences,
    required this.availability,
    required this.onToggle,
    required this.onMode,
    required this.onPickWindow,
  });

  final ReminderPreferences preferences;
  final HydrationAvailability availability;
  final ValueChanged<bool> onToggle;
  final ValueChanged<HydrationMode> onMode;
  final VoidCallback onPickWindow;

  static String _modeLabel(HydrationMode mode) => switch (mode) {
    HydrationMode.gentle => 'Gentle',
    HydrationMode.balanced => 'Balanced',
    HydrationMode.supportive => 'Supportive',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final enabled = preferences.hydrationEnabled;
    final noWater = availability == HydrationAvailability.noBuiltInWater;
    final window = preferences.hydrationWindow;
    String format(ReminderTime t) =>
        TimeOfDay(hour: t.hour, minute: t.minute).format(context);
    final hours = '${format(window.start)} – ${format(window.end)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.xs,
            0,
            WinterSpacing.xs,
            WinterSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text('Hydration Coach', style: text.titleLarge),
          ),
        ),
        WinterCard(
          padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: enabled,
                // Without the built-in Water habit it could only be
                // switched off.
                onChanged: noWater && !enabled ? null : onToggle,
                title: Text('Hydration Coach', style: text.titleMedium),
                subtitle: const Text(
                  "NextRep checks your Water progress and only nudges you "
                  "when you're behind the day's pace.",
                ),
              ),
              if (noWater)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WinterSpacing.md,
                    0,
                    WinterSpacing.md,
                    WinterSpacing.sm,
                  ),
                  child: _Notice(
                    icon: Icons.water_drop_outlined,
                    color: colors.textSecondary,
                    message:
                        'Hydration Coach works with the built-in Water '
                        'habit in your active Arc.',
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WinterSpacing.md,
                  WinterSpacing.sm,
                  WinterSpacing.md,
                  0,
                ),
                child: Semantics(
                  header: true,
                  child: Text('Reminder style', style: text.titleSmall),
                ),
              ),
              RadioGroup<HydrationMode>(
                groupValue: preferences.hydrationMode,
                onChanged: (mode) {
                  if (mode != null && mode != preferences.hydrationMode) {
                    onMode(mode);
                  }
                },
                child: Column(
                  children: [
                    for (final mode in HydrationMode.values)
                      RadioListTile<HydrationMode>(
                        value: mode,
                        title: Text(_modeLabel(mode)),
                        subtitle: Text('Up to ${mode.maxNudges} nudges a day'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Read as one control: "Active hours, 8:00 AM – 8:00 PM".
              Semantics(
                container: true,
                button: true,
                label: 'Active hours, $hours',
                onTap: onPickWindow,
                excludeSemantics: true,
                child: ListTile(
                  onTap: onPickWindow,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Active hours'),
                  subtitle: Text(hours, style: text.titleMedium),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinterSpacing.xs,
      0,
      WinterSpacing.xs,
      WinterSpacing.sm,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: WinterSpacing.sm),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
