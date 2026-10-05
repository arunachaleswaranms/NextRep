import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/winter_tokens.dart';
import '../../core/errors/action_result.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/backup/backup_document.dart';
import '../../domain/backup/backup_validator.dart';
import '../../domain/winter_arc/winter_arc_session.dart';
import '../../shared/formatting/arc_labels.dart';
import '../../shared/formatting/failure_messages.dart';
import '../../shared/widgets/winter_background.dart';
import '../../shared/widgets/winter_card.dart';
import 'backup_controller.dart';

/// Data & Backup: export everything to a file the user keeps, or replace
/// the data on this device from such a file.
///
/// Every destructive step is confirmed first: a restore shows what the
/// backup holds, warns that it replaces (never merges) the data here, and
/// asks again when there is data to lose.
class DataBackupScreen extends ConsumerWidget {
  const DataBackupScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('Export Backup'),
        content: const Text(
          'This backup contains your private NextRep history and '
          'reflections. Store it somewhere you trust.\n\n'
          'The file is not encrypted: anyone who can open it can read your '
          'Journal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Location'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    final result = await ref.read(backupControllerProvider.notifier).export();
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess(value: true):
        _snack(context, 'Backup saved.');
      case ActionSuccess():
        break; // cancelled in the save dialog
      case ActionFailure(:final failure):
        _snack(context, _exportMessage(failure));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(backupControllerProvider.notifier);
    final picked = await controller.pick();
    if (!context.mounted) return;
    switch (picked) {
      case ActionFailure(:final failure):
        await _showProblem(context, failure);
        return;
      case ActionSuccess(value: BackupPickCancelled()):
        return;
      case ActionSuccess(value: final BackupPicked picked):
        final confirmed =
            await _confirmRestore(context, picked.backup) &&
            context.mounted &&
            (picked.current.isEmpty ||
                await _confirmReplace(context, picked.current));
        if (!confirmed || !context.mounted) return;
        final result = await controller.restore(picked.backup);
        // On success the app reloads from the restored data and this
        // screen is gone.
        if (result case ActionFailure(:final failure) when context.mounted) {
          await _showProblem(context, failure, restoring: true);
        }
    }
  }

  Future<bool> _confirmRestore(
    BuildContext context,
    ValidatedBackup backup,
  ) async {
    final summary = backup.summary;
    final exported = DateFormat('d MMM y, HH:mm')
        .format(backup.document.exportedAt.toLocal());
    final unfinished = summary.unfinishedArc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        return AlertDialog(
          icon: const Icon(Icons.settings_backup_restore_rounded),
          title: const Text('Restore Backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Fact('Exported', exported),
                _Fact('Arcs', '${summary.arcCount}'),
                _Fact('Completed Arcs', '${summary.completedArcs}'),
                if (unfinished != null)
                  _Fact(
                    unfinished.status == WinterArcStatus.active
                        ? 'Active Arc'
                        : 'Arc in setup',
                    unfinished.status == WinterArcStatus.active
                        ? arcDateRange(unfinished)
                        : 'not started yet',
                  ),
                _Fact('Reflections', '${summary.reflectionCount}'),
                _Fact('Achievements', '${summary.achievementCount}'),
                const SizedBox(height: WinterSpacing.md),
                Text(
                  'This will replace the NextRep data currently stored on '
                  'this device.\n\nIt cannot be automatically merged with '
                  'your current Arcs. Reminders will be off after restoring.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// The second confirmation, when restoring would replace existing data.
  Future<bool> _confirmReplace(
    BuildContext context,
    BackupSummary current,
  ) async {
    final arcs = current.arcCount == 1 ? '1 Arc' : '${current.arcCount} Arcs';
    final reflections = current.reflectionCount == 1
        ? '1 reflection'
        : '${current.reflectionCount} reflections';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.winter;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: colors.danger),
          title: const Text('Replace current data?'),
          content: Text(
            'This device has $arcs and $reflections. They will be '
            'permanently replaced by the backup.\n\nIf you might need them, '
            'cancel and export a backup first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: colors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace Data'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _showProblem(
    BuildContext context,
    AppFailure failure, {
    bool restoring = false,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.error_outline_rounded),
      // Only a problem with the file itself is blamed on the file.
      title: Text(
        restoring
            ? "Couldn't restore"
            : failure is BackupFailure
            ? "Can't use this file"
            : "Couldn't open the file",
      ),
      content: Text(
        restoring && failure is! BackupFailure
            ? 'The restore did not complete, so nothing was changed. Your '
                  'current data is exactly as it was.'
            : userMessageFor(failure),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  static String _exportMessage(AppFailure failure) => switch (failure) {
    PersistenceFailure() => "Couldn't read your data for the backup.",
    // The export checks itself before it is saved.
    BackupFailure() =>
      "Some of your data couldn't be checked for a backup, so nothing was "
          'saved. If the device date was changed recently, set it to the '
          'correct date and try again.',
    _ => "Couldn't save the backup. Nothing was changed.",
  };

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(backupControllerProvider);
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    final busy = activity != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & Backup'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: WinterBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(WinterSpacing.lg),
            children: [
              Text(
                'DATA & BACKUP',
                style: text.labelLarge?.copyWith(
                  color: colors.accentSecondary,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: WinterSpacing.md),
              _Action(
                icon: Icons.upload_file_rounded,
                title: 'Export Backup',
                subtitle:
                    'Save all Arcs, progress, achievements and Journal '
                    'entries.',
                busy: activity == BackupActivity.exporting,
                onTap: busy ? null : () => _export(context, ref),
              ),
              const SizedBox(height: WinterSpacing.sm),
              _Action(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Restore Backup',
                subtitle: 'Replace local NextRep data from a backup.',
                busy:
                    activity == BackupActivity.reading ||
                    activity == BackupActivity.restoring,
                accent: colors.warning,
                onTap: busy ? null : () => _restore(context, ref),
              ),
              const SizedBox(height: WinterSpacing.lg),
              _Note(
                icon: Icons.cloud_off_rounded,
                text:
                    'Backups are stored wherever you choose. NextRep does not '
                    'upload them.',
              ),
              const SizedBox(height: WinterSpacing.sm),
              _Note(
                icon: Icons.lock_open_rounded,
                text:
                    'A backup includes your reflections and is not encrypted. '
                    'The backup includes a checksum so accidental corruption '
                    'can be detected.',
              ),
              const SizedBox(height: WinterSpacing.sm),
              _Note(
                icon: Icons.swap_horiz_rounded,
                text:
                    'Restoring replaces everything on this device. Backups '
                    "can't be merged.",
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.winter;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$title. $subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: WinterCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 28, color: accent ?? colors.accentSecondary),
            const SizedBox(width: WinterSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: WinterSpacing.xs),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
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
        Icon(icon, size: 18, color: colors.textSecondary),
        const SizedBox(width: WinterSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// One line of backup metadata: a label and its value.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: WinterSpacing.xs),
      child: Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            const SizedBox(width: WinterSpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: text.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
