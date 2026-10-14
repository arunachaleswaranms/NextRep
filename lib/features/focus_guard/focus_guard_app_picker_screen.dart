import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/focus_guard/focus_guard_platform.dart';
import '../../domain/focus_guard/focus_guard_settings.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import 'focus_guard_controller.dart';

/// Chooses the apps Focus Guard measures: apps with a launcher entry,
/// searchable, several at once, up to [FocusGuardRules.maxSelectedApps].
/// Nothing is pre-selected or suggested; nothing is saved until Save. A
/// chosen app that is no longer installed is listed so it can be removed.
class FocusGuardAppPickerScreen extends ConsumerStatefulWidget {
  const FocusGuardAppPickerScreen({super.key});

  @override
  ConsumerState<FocusGuardAppPickerScreen> createState() =>
      _FocusGuardAppPickerScreenState();
}

class _FocusGuardAppPickerScreenState
    extends ConsumerState<FocusGuardAppPickerScreen> {
  final _search = TextEditingController();

  /// The selection being edited, in the order it will be saved. Null until
  /// the stored selection has loaded.
  List<String>? _selected;
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String package, bool on) {
    final selected = _selected!;
    setState(() {
      if (on) {
        if (!selected.contains(package) &&
            selected.length < FocusGuardRules.maxSelectedApps) {
          selected.add(package);
        }
      } else {
        selected.remove(package);
      }
    });
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    final result = await ref
        .read(focusGuardSettingsProvider.notifier)
        .setSelectedApps(List.of(selected));
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess():
        Navigator.of(context).pop();
      case ActionFailure(:final failure):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(userMessageFor(failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(focusGuardPickableAppsProvider);
    final settings = ref.watch(focusGuardSettingsProvider);
    _selected ??= settings.value == null
        ? null
        : List.of(settings.value!.status.settings.selectedPackages);
    final ready = _selected != null && apps.hasValue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose apps'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: ready && !_saving ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch ((apps, settings)) {
            (AsyncError(:final error, :final stackTrace), _) ||
            (_, AsyncError(:final error, :final stackTrace)) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () {
                ref.invalidate(focusGuardPickableAppsProvider);
                ref.invalidate(focusGuardSettingsProvider);
              },
            ),
            _ when ready => _content(context, apps.value!),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<LaunchableAppCandidate> apps) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final selected = _selected!;
    final installed = {for (final app in apps) app.packageName};
    final missing = [
      for (final package in selected)
        if (!installed.contains(package)) package,
    ];
    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? apps
        : [
            for (final app in apps)
              if (app.label.toLowerCase().contains(query) ||
                  app.packageName.toLowerCase().contains(query))
                app,
          ];
    final full = selected.length >= FocusGuardRules.maxSelectedApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WinterSpacing.md,
            WinterSpacing.sm,
            WinterSpacing.md,
            WinterSpacing.xs,
          ),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search apps',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WinterSpacing.md,
            vertical: WinterSpacing.xs,
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(
              full
                  ? '${selected.length} chosen · the most Focus Guard can '
                        'watch'
                  : '${selected.length} chosen · up to '
                        '${FocusGuardRules.maxSelectedApps}',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: WinterSpacing.lg),
            children: [
              if (missing.isNotEmpty) ...[
                _Header(title: 'No longer installed'),
                for (final package in missing)
                  CheckboxListTile(
                    value: true,
                    onChanged: (on) => _toggle(package, on ?? false),
                    title: Text(package),
                    subtitle: const Text('Not installed'),
                  ),
                _Header(title: 'Installed apps'),
              ],
              if (apps.isEmpty)
                const _Empty(message: 'No apps to show.')
              else if (shown.isEmpty)
                const _Empty(message: 'No apps match your search.')
              else
                for (final app in shown)
                  CheckboxListTile(
                    value: selected.contains(app.packageName),
                    onChanged: !selected.contains(app.packageName) && full
                        ? null
                        : (on) => _toggle(app.packageName, on ?? false),
                    title: Text(app.label),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WinterSpacing.md,
      WinterSpacing.md,
      WinterSpacing.md,
      WinterSpacing.xs,
    ),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(WinterSpacing.lg),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}
