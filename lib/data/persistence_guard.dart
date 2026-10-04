import '../core/errors/app_failure.dart';

/// Runs a storage operation and converts unexpected exceptions into a
/// [PersistenceFailure] that names the operation. [AppFailure]s (e.g. a
/// domain rule raised inside a transaction) propagate unchanged.
Future<T> guardPersistence<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on AppFailure {
    rethrow;
  } catch (error, stackTrace) {
    throw PersistenceFailure(
      'Storage operation failed: $operation',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

/// Like [guardPersistence], for operations on private text (reflections).
///
/// Database errors can quote the failing statement together with its bound
/// values (`SqliteException.toString` does), which would put the user's
/// words into error reports. So the original error is not kept as the
/// cause: only its type is, and the stack trace.
Future<T> guardPrivatePersistence<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on AppFailure {
    rethrow;
  } catch (error, stackTrace) {
    throw PersistenceFailure(
      'Storage operation failed: $operation',
      cause: '${error.runtimeType} (details withheld: private data)',
      stackTrace: stackTrace,
    );
  }
}
