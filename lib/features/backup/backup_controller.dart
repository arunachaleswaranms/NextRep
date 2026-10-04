import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_restart.dart';
import '../../app/dependencies.dart';
import '../../core/errors/action_result.dart';
import '../../domain/backup/backup_document.dart';
import '../../domain/backup/backup_service.dart';
import '../../domain/backup/backup_validator.dart';

/// What the Data & Backup screen is busy with, if anything.
enum BackupActivity { exporting, reading, restoring }

/// The outcome of choosing a backup file to restore.
sealed class BackupPick {
  const BackupPick();
}

/// The user closed the picker.
final class BackupPickCancelled extends BackupPick {
  const BackupPickCancelled();
}

/// A valid backup, plus what is on the device now, for the confirmation.
final class BackupPicked extends BackupPick {
  const BackupPicked({required this.backup, required this.current});

  final ValidatedBackup backup;
  final BackupSummary current;
}

final backupControllerProvider =
    NotifierProvider.autoDispose<BackupController, BackupActivity?>(
      BackupController.new,
    );

/// Export and restore for the Data & Backup screen. One operation at a
/// time; the state says which one is running.
///
/// Nothing here is logged beyond the failure type and rule: never a path,
/// a backup's contents or a reflection.
class BackupController extends Notifier<BackupActivity?> {
  @override
  BackupActivity? build() => null;

  /// Encodes a backup and lets the user save it. The value is false when
  /// they cancelled the save dialog.
  Future<ActionResult<bool>> export() => _busy(BackupActivity.exporting, () {
    final service = ref.read(backupServiceProvider);
    final files = ref.read(backupFilesProvider);
    return runAction('backup', () async {
      final backup = await service.export();
      return files.save(backup.fileName, backup.bytes);
    });
  });

  /// Lets the user pick a backup and checks it fully. Never writes.
  Future<ActionResult<BackupPick>> pick() => _busy(BackupActivity.reading, () {
    final service = ref.read(backupServiceProvider);
    final files = ref.read(backupFilesProvider);
    return runAction<BackupPick>('backup', () async {
      final bytes = await files.pick();
      if (bytes == null) return const BackupPickCancelled();
      return BackupPicked(
        backup: await service.inspect(bytes),
        current: await service.current(),
      );
    });
  });

  /// Replaces all local data with [backup], then reloads the app from the
  /// restored data. Only call after the user confirmed.
  Future<ActionResult<RestoreOutcome>> restore(ValidatedBackup backup) =>
      _busy(BackupActivity.restoring, () async {
        final service = ref.read(backupServiceProvider);
        final epoch = ref.read(appEpochProvider.notifier);
        final result = await runAction('backup', () => service.restore(backup));
        if (result is ActionSuccess) {
          epoch.restart(
            notice:
                'Backup restored. Reminders are off; turn them on again '
                'in Reminders if you want them.',
          );
        }
        return result;
      });

  Future<ActionResult<T>> _busy<T>(
    BackupActivity activity,
    Future<ActionResult<T>> Function() body,
  ) async {
    state = activity;
    try {
      return await body();
    } finally {
      if (ref.mounted) state = null;
    }
  }
}
