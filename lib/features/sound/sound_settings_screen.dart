import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/feedback/feedback_preferences.dart';
import '../../shared/widgets/failure_view.dart';
import '../../shared/widgets/loading_view.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'sound_settings_controller.dart';

/// The wording of Sound & Feedback (ARC_CONTROL_SPEC § 8.4, § 9.12). The
/// set names are pending the owner's Gate G decision.
abstract final class SoundCopy {
  static const title = 'Sound & Feedback';
  static const switchTitle = 'Completion sounds';
  static const switchSubtitle = 'A short sound when you complete a habit.';
  static const heading = 'Sound';
  static const turnOn = 'Turn on sounds to choose one.';
  static const help =
      "Sounds follow your phone's sound settings. They stay quiet on silent "
      'and Do Not Disturb.';
  static const saveFailed = "Couldn't save.";

  static String name(SoundTheme theme) => switch (theme) {
    SoundTheme.iceCrystal => 'Ice Crystal',
    SoundTheme.summitSpark => 'Summit Spark',
    SoundTheme.warmEmber => 'Warm Ember',
  };

  /// The preview's spoken label, e.g. "Play Ice Crystal".
  static String play(SoundTheme theme) => 'Play ${name(theme)}';
}

/// Opens Sound & Feedback from a header (Today, Arc History).
class SoundSettingsButton extends StatelessWidget {
  const SoundSettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: SoundCopy.title,
    icon: const Icon(Icons.volume_up_outlined),
    onPressed: () => context.push(AppRoutes.soundSettings),
  );
}

/// Sound & Feedback (`/settings/sound`): completion sounds on or off, and
/// which of the three sets plays. App-level, reachable in every state.
///
/// Every change is stored at once and read back; a failed write shows
/// "Couldn't save." and the stored value. A preview plays through the same
/// engine as a completion (so never while sounds are off) and a preview
/// that can't play is simply silent. Haptics have no switch here.
class SoundSettingsScreen extends ConsumerStatefulWidget {
  const SoundSettingsScreen({super.key});

  @override
  ConsumerState<SoundSettingsScreen> createState() =>
      _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends ConsumerState<SoundSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Loads the sounds (if on) so a preview can play straight away.
    unawaited(ref.read(completionFeedbackProvider).warmUp());
  }

  /// Stores [change]; true when it was stored.
  Future<bool> _save(
    FeedbackPreferences Function(FeedbackPreferences current) change,
  ) async {
    final result = await ref.read(soundSettingsProvider.notifier).save(change);
    if (!mounted) return false;
    if (result is ActionFailure) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(SoundCopy.saveFailed)));
      return false;
    }
    return true;
  }

  Future<void> _setEnabled(bool on) async {
    final saved = await _save(
      (p) => FeedbackPreferences(soundsEnabled: on, soundTheme: p.soundTheme),
    );
    if (saved && on) {
      unawaited(ref.read(completionFeedbackProvider).warmUp());
    }
  }

  /// Selecting a set stores it, then plays it once.
  Future<void> _choose(SoundTheme theme) async {
    final saved = await _save(
      (p) => FeedbackPreferences(
        soundsEnabled: p.soundsEnabled,
        soundTheme: theme,
      ),
    );
    if (saved) _preview(theme);
  }

  void _preview(SoundTheme theme) =>
      unawaited(ref.read(completionFeedbackProvider).preview(theme));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(soundSettingsProvider);
    // Keep showing the stored state while a save re-reads it.
    final value = settings.hasError ? null : settings.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text(SoundCopy.title),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: switch (settings) {
            _ when value != null => _content(context, value),
            AsyncError(:final error, :final stackTrace) => FailureView(
              failure: toAppFailure(error, stackTrace),
              onRetry: () => ref.invalidate(soundSettingsProvider),
            ),
            _ => const LoadingView(),
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, FeedbackPreferences preferences) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final on = preferences.soundsEnabled;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WinterSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WinterCard(
                padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
                child: SwitchListTile(
                  key: const ValueKey('sound-switch'),
                  value: on,
                  onChanged: _setEnabled,
                  title: Text(SoundCopy.switchTitle, style: text.titleMedium),
                  subtitle: const Text(SoundCopy.switchSubtitle),
                ),
              ),
              const SizedBox(height: WinterSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WinterSpacing.xs,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    SoundCopy.heading.toUpperCase(),
                    style: text.labelLarge?.copyWith(
                      color: colors.accentSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              if (!on)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WinterSpacing.xs,
                    WinterSpacing.xs,
                    WinterSpacing.xs,
                    0,
                  ),
                  child: Text(SoundCopy.turnOn, style: text.bodyMedium),
                ),
              const SizedBox(height: WinterSpacing.sm),
              WinterCard(
                padding: const EdgeInsets.symmetric(vertical: WinterSpacing.xs),
                child: Semantics(
                  label: SoundCopy.heading,
                  child: RadioGroup<SoundTheme>(
                    groupValue: preferences.soundTheme,
                    onChanged: (theme) {
                      if (on && theme != null) unawaited(_choose(theme));
                    },
                    child: Column(
                      children: [
                        for (final theme in SoundTheme.values)
                          _ThemeRow(
                            theme: theme,
                            enabled: on,
                            onPreview: () => _preview(theme),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WinterSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WinterSpacing.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.do_not_disturb_on_outlined,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: WinterSpacing.sm),
                    Expanded(
                      child: Text(SoundCopy.help, style: text.bodyMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One set: its radio and its preview. The preview is a separate control
/// (never merged into the radio), beside the name, or under it above 1.3×
/// text so the name keeps its width.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    required this.theme,
    required this.enabled,
    required this.onPreview,
  });

  final SoundTheme theme;
  final bool enabled;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final name = SoundCopy.name(theme);
    final radio = RadioListTile<SoundTheme>(
      key: ValueKey('sound-${theme.name}'),
      value: theme,
      enabled: enabled,
      title: Text(name),
    );
    // One node, "Play Ice Crystal", enabled or not: never merged into the
    // radio, and announced the same in both layouts.
    Widget announced(Widget button) => Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: SoundCopy.play(theme),
      onTap: enabled ? onPreview : null,
      excludeSemantics: true,
      child: button,
    );
    if (!stacked) {
      return Row(
        children: [
          Expanded(child: radio),
          announced(
            IconButton(
              key: ValueKey('preview-${theme.name}'),
              tooltip: SoundCopy.play(theme),
              onPressed: enabled ? onPreview : null,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ),
          const SizedBox(width: WinterSpacing.xs),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        radio,
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 56,
            bottom: WinterSpacing.xs,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: announced(
              TextButton.icon(
                key: ValueKey('preview-${theme.name}'),
                onPressed: enabled ? onPreview : null,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
