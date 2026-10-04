import 'backup_document.dart';
import 'backup_validator.dart';

/// Persistence boundary for whole-database backup and restore.
///
/// Implementations throw `PersistenceFailure` on storage errors, without
/// any user data (reflection text, habit names) in the failure.
abstract interface class BackupStore {
  /// A consistent snapshot of every authoritative record, read in one
  /// transaction. Read-only.
  Future<BackupData> read();

  /// Replaces everything NextRep stores with [backup], all or nothing.
  ///
  /// Runs in one transaction: every app-owned row is deleted, the backup's
  /// rows are inserted, and the result is checked (row counts, at most one
  /// unfinished arc, no dangling references) before committing. Any
  /// failure rolls back, leaving the existing data exactly as it was.
  ///
  /// Arc ids are shifted past every id this database has used, so no
  /// restored arc reuses one (a fresh install keeps the backup's ids).
  /// Reminder times are restored with both reminders off.
  Future<void> replaceAll(ValidatedBackup backup);
}
