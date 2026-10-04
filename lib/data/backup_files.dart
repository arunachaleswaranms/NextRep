import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/errors/app_failure.dart';
import '../core/errors/error_reporter.dart';
import '../domain/backup/backup_document.dart';

/// Where backup files come from and go to: the system's own file UI.
///
/// The user picks the location every time; the app never gets broad
/// storage access and never uploads anything.
abstract interface class BackupFiles {
  /// Lets the user choose where to save [bytes] as [fileName]. Returns
  /// false if they cancelled.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Lets the user pick a backup file and returns its bytes, or null if
  /// they cancelled. Throws `BackupFailure` ([BackupProblem.tooLarge])
  /// without reading a file over [BackupFormat.maxBytes].
  Future<Uint8List?> pick();
}

/// [BackupFiles] through `file_picker`: the Storage Access Framework
/// document picker / "create document" on Android and the document picker
/// on iOS. Neither needs a storage permission.
final class SystemBackupFiles implements BackupFiles {
  const SystemBackupFiles();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: 'Save NextRep backup',
    );
    return saved != null;
  }

  @override
  Future<Uint8List?> pick() async {
    // Any file type: a custom extension has no MIME type the Android
    // picker could filter on. The content is checked, not the name.
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a backup');
    if (file == null) return null;
    try {
      final length = file.lengthSync() ?? await file.length();
      if (length == null || length > BackupFormat.maxBytes) {
        throw const BackupFailure(
          BackupProblem.tooLarge,
          'Picked file is over the size limit',
        );
      }
      return await file.readAsBytes();
    } finally {
      await _clearCopies();
    }
  }

  /// Android hands over a private copy in the app's cache. It holds the
  /// user's reflections, so it doesn't stay there. Best effort: a failure
  /// here must not hide the outcome of the pick, and the OS clears the
  /// cache eventually.
  static Future<void> _clearCopies() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (error, stackTrace) {
      ErrorReporter.report(
        toAppFailure(error, stackTrace),
        context: 'backup_files',
      );
    }
  }
}
