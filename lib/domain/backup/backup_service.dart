import 'dart:typed_data';

import '../../core/time/clock.dart';
import '../../core/utils/serial_queue.dart';
import '../reminder/reminder_scheduler.dart';
import 'backup_codec.dart';
import 'backup_document.dart';
import 'backup_store.dart';
import 'backup_validator.dart';

/// An encoded backup, ready for the user to save.
final class BackupExport {
  const BackupExport({
    required this.bytes,
    required this.fileName,
    required this.summary,
  });

  final Uint8List bytes;

  /// Suggested file name; it never contains user data.
  final String fileName;
  final BackupSummary summary;
}

/// What a restore did.
final class RestoreOutcome {
  const RestoreOutcome({required this.summary, required this.remindersCleared});

  final BackupSummary summary;

  /// False if pending notifications couldn't be cancelled. The data was
  /// restored either way, with reminders off; the app's next reminder
  /// reconciliation cancels them.
  final bool remindersCleared;
}

/// Backup and restore use cases.
///
/// * [export] only reads. The encoded file is decoded and validated again
///   before it is handed out, so a backup that couldn't be restored is
///   never offered for saving.
/// * [inspect] decodes and validates a file without touching the database.
/// * [restore] replaces all local data with a [ValidatedBackup], which only
///   [inspect] can produce: nothing unvalidated reaches storage. Restore is
///   a full replacement, never a merge. Reminders end up off and pending
///   notifications are cancelled, so a restore never schedules anything.
final class BackupService {
  BackupService({
    required this._store,
    required this._scheduler,
    required this._clock,
    required this._appVersion,
  });

  final BackupStore _store;
  final ReminderScheduler _scheduler;
  final Clock _clock;
  final String _appVersion;
  final _queue = SerialQueue();

  /// Encodes every arc, its history and the Journal as a backup file.
  Future<BackupExport> export() => _queue.run(() async {
    final now = _clock.now();
    final document = BackupDocument(
      exportedAt: now,
      appVersion: _appVersion,
      data: await _store.read(),
    );
    final bytes = BackupCodec.encode(document);
    final checked = BackupValidator.validate(BackupCodec.decode(bytes));
    return BackupExport(
      bytes: bytes,
      fileName: BackupFormat.fileNameFor(_clock.today()),
      summary: checked.summary,
    );
  });

  /// Checks [bytes] as a backup. Throws `BackupFailure` if it isn't one
  /// that can be restored. Never writes.
  Future<ValidatedBackup> inspect(Uint8List bytes) async =>
      BackupValidator.validate(BackupCodec.decode(bytes));

  /// What is stored on this device now, as a backup would count it.
  Future<BackupSummary> current() async =>
      BackupSummary.of(await _store.read());

  /// Replaces all local NextRep data with [backup].
  Future<RestoreOutcome> restore(ValidatedBackup backup) => _queue.run(
    () async {
      await _store.replaceAll(backup);
      var cleared = true;
      try {
        await _scheduler.cancelAll();
      } catch (_) {
        cleared = false;
      }
      return RestoreOutcome(summary: backup.summary, remindersCleared: cleared);
    },
  );
}
