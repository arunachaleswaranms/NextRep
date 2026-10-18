import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/winter_tokens.dart';
import '../../domain/update/installed_app.dart';
import '../../domain/update/official_source.dart';
import '../../domain/update/update_checker.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'about_controller.dart';

/// About NextRep: what it is, the installed version and build, a manual
/// update check (Android), privacy, the official source and open-source
/// licenses.
///
/// Opening, rebuilding or leaving this screen contacts nothing. Only the
/// "Check for updates" button reads GitHub's latest release, once per tap;
/// only "View official release" and "Open on GitHub" open the browser.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _browserProblem =
      "Couldn't open a browser. Visit "
      '${OfficialSource.repositoryLabel}/releases in your browser.';

  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Uri page,
  ) async {
    final opened = await ref.read(externalLinksProvider).open(page);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(_browserProblem)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedAppProvider);
    final updatesOffered = ref.watch(releaseFeedProvider) != null;
    // Watched here, by the screen itself, so the check (and its result)
    // lives exactly as long as About is open, even while its card is
    // scrolled out of the list.
    final check = ref.watch(updateCheckControllerProvider);
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'ABOUT NEXTREP',
                  style: text.labelLarge?.copyWith(
                    color: colors.accentSecondary,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: WinterSpacing.md),
              const _Identity(),
              const _SectionLabel('YOUR VERSION'),
              _VersionCard(installed: installed),
              const _SectionLabel('UPDATES'),
              if (updatesOffered)
                _UpdatesCard(
                  state: check,
                  canCheck: installed.value?.releaseVersion != null,
                  onCheck: () =>
                      ref.read(updateCheckControllerProvider.notifier).check(),
                  onOpen: (page) => _open(context, ref, page),
                )
              else
                const WinterCard(
                  child: _Note(
                    icon: Icons.android_rounded,
                    text:
                        'NextRep releases are published for Android only, so '
                        "this device doesn't check for updates.",
                  ),
                ),
              const _SectionLabel('PRIVACY'),
              _PrivacyCard(updatesOffered: updatesOffered),
              const _SectionLabel('OFFICIAL SOURCE'),
              WinterCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      OfficialSource.repositoryLabel,
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: WinterSpacing.xs),
                    Text(
                      'Official NextRep releases are published only on this '
                      "repository's Releases page.",
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: WinterSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _open(context, ref, OfficialSource.repositoryPage),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open on GitHub'),
                    ),
                    const SizedBox(height: WinterSpacing.xs),
                    // Flutter's own page, built into the app: offline.
                    TextButton.icon(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'NextRep',
                        applicationVersion: installed.value?.version,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Open-source licenses'),
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

/// NEXTREP, its line and what it is for.
class _Identity extends StatelessWidget {
  const _Identity();

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.landscape_rounded,
                    size: 40,
                    color: colors.accentSecondary,
                  ),
                ),
                const SizedBox(width: WinterSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXTREP',
                        style: text.headlineSmall?.copyWith(letterSpacing: 4),
                      ),
                      Text(
                        'Every rep counts.',
                        style: text.titleSmall?.copyWith(
                          color: colors.accentSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WinterSpacing.md),
          Text(
            'Your Winter Arc companion for building better habits, one day '
            'at a time.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: WinterSpacing.sm),
          Text(
            'Run a 92-day Winter Arc: check off daily habits, earn XP, keep '
            'your streaks and Perfect Days, and reflect in your Journal.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// "Version 1.2.0 · Build 3", as the platform reports the installed app.
class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.installed});

  final AsyncValue<InstalledApp> installed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return WinterCard(
      child: switch (installed) {
        AsyncData(:final value) => MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${value.version}', style: text.titleMedium),
              Text('Build ${value.buildNumber}', style: text.bodyMedium),
            ],
          ),
        ),
        AsyncError() => Text(
          'Version information is unavailable.',
          style: text.bodyMedium,
        ),
        _ => Text('Reading version…', style: text.bodyMedium),
      },
    );
  }
}

/// The manual check, its result, and how to update safely.
class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({
    required this.state,
    required this.canCheck,
    required this.onCheck,
    required this.onOpen,
  });

  final UpdateCheckState state;

  /// False until the installed version is known (or if it can't be
  /// compared).
  final bool canCheck;
  final VoidCallback onCheck;
  final void Function(Uri page) onOpen;

  @override
  Widget build(BuildContext context) {
    final running = state is UpdateCheckRunning;
    final result = switch (state) {
      UpdateCheckFinished(:final result) => result,
      _ => null,
    };
    return WinterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Announced when it changes, so a screen reader hears the result.
          Semantics(liveRegion: true, child: _CheckStatus(state: state)),
          const SizedBox(height: WinterSpacing.md),
          if (result case UpdateAvailable(:final releasePage)) ...[
            FilledButton.icon(
              onPressed: () => onOpen(releasePage),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('View official release'),
            ),
            const SizedBox(height: WinterSpacing.sm),
          ],
          OutlinedButton.icon(
            onPressed: running || !canCheck ? null : onCheck,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(running ? 'Checking…' : 'Check for updates'),
          ),
          const SizedBox(height: WinterSpacing.md),
          const _Note(
            icon: Icons.new_releases_outlined,
            text:
                'Updates are published on the official NextRep GitHub '
                'Releases page.',
          ),
          const SizedBox(height: WinterSpacing.sm),
          const _Note(
            icon: Icons.system_update_rounded,
            text:
                'Install a newer signed APK over your current app to keep '
                'your data.',
          ),
          const SizedBox(height: WinterSpacing.sm),
          const _Note(
            icon: Icons.warning_amber_rounded,
            text: "Don't uninstall NextRep to update.",
          ),
          const SizedBox(height: WinterSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.dataBackup),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Back up your data'),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the check found, in words. Never a raw error.
class _CheckStatus extends StatelessWidget {
  const _CheckStatus({required this.state});

  final UpdateCheckState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final (icon, color, title, detail) = switch (state) {
      UpdateCheckIdle() => (
        Icons.cloud_off_rounded,
        colors.textSecondary,
        null,
        'Only checks GitHub when you tap.',
      ),
      UpdateCheckRunning() => (
        Icons.sync_rounded,
        colors.accentSecondary,
        'Checking for updates…',
        'Reading the latest release from GitHub.',
      ),
      UpdateCheckFinished(:final result) => switch (result) {
        UpToDate(:final latest) => (
          Icons.check_circle_rounded,
          colors.success,
          "You're using the latest published version.",
          'Latest published: ${latest.tag}',
        ),
        UpdateAvailable(:final installed, :final latest) => (
          Icons.system_update_rounded,
          colors.accentSecondary,
          'NextRep ${latest.tag} is available.',
          'Installed: ${installed.tag} · Available: ${latest.tag}',
        ),
        ReleaseNotReady(:final installed, :final latest) => (
          Icons.hourglass_top_rounded,
          colors.warning,
          'A newer release is listed, but its Android download is not '
              'ready yet.',
          'Listed: ${latest.tag} · Installed: ${installed.tag}. Please '
              'check again later.',
        ),
        NewerBuildInstalled(:final installed, :final latest) => (
          Icons.info_outline_rounded,
          colors.accentSecondary,
          'This build is newer than the latest published release.',
          'Installed: ${installed.tag} · Latest published: ${latest.tag}',
        ),
        NoPublishedRelease() => (
          Icons.info_outline_rounded,
          colors.textSecondary,
          'GitHub did not return a published NextRep release.',
          'Please try again later.',
        ),
        CheckNetworkFailure() => (
          Icons.wifi_off_rounded,
          colors.warning,
          "Couldn't check for updates.",
          'Check your connection and try again.',
        ),
        CheckRateLimited() => (
          Icons.hourglass_top_rounded,
          colors.warning,
          'GitHub is temporarily limiting update checks.',
          'Please try again later.',
        ),
        CheckServiceUnavailable() => (
          Icons.cloud_off_rounded,
          colors.warning,
          "GitHub couldn't answer the update check.",
          'Please try again later.',
        ),
        CheckInvalidRelease() => (
          Icons.error_outline_rounded,
          colors.warning,
          "Couldn't verify the latest release information.",
          'Please try again later.',
        ),
      },
    };
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 24, color: color)),
          const SizedBox(width: WinterSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title, style: text.titleSmall),
                Text(detail, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Local-first, and exactly when the network is used.
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.updatesOffered});

  final bool updatesOffered;

  @override
  Widget build(BuildContext context) => WinterCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Note(
          icon: Icons.phone_android_rounded,
          text:
              'NextRep works offline. Your habits, progress, Journal, Focus '
              'Guard and Hydration data stay on your device. No account, no '
              'analytics, no tracking.',
        ),
        if (updatesOffered) ...[
          const SizedBox(height: WinterSpacing.sm),
          const _Note(
            icon: Icons.cloud_outlined,
            text:
                'Only when you tap Check for updates, NextRep makes a single '
                'HTTPS request to GitHub to read the latest public release '
                'information. It does not send your NextRep data. GitHub '
                'receives the usual details of any web request, such as your '
                'IP address. Nothing is checked automatically.',
          ),
        ],
        const SizedBox(height: WinterSpacing.sm),
        const _Note(
          icon: Icons.open_in_new_rounded,
          text:
              "GitHub pages open in your browser, where GitHub's own privacy "
              'practices apply.',
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: WinterSpacing.lg,
      bottom: WinterSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: context.winter.accentSecondary, letterSpacing: 2),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 18, color: colors.textSecondary),
        ),
        const SizedBox(width: WinterSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
