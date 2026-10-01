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
