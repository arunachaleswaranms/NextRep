import 'app_failure.dart';
import 'error_reporter.dart';

/// Outcome of a user-initiated action, returned to the UI so it can give
/// feedback. Failures are already reported when this is produced.
sealed class ActionResult<T> {
  const ActionResult();
}

final class ActionSuccess<T> extends ActionResult<T> {
  const ActionSuccess(this.value);

  final T value;
}

final class ActionFailure<T> extends ActionResult<T> {
  const ActionFailure(this.failure);

  final AppFailure failure;
}

/// Runs [body], reporting and capturing any failure instead of throwing.
Future<ActionResult<T>> runAction<T>(
  String context,
  Future<T> Function() body,
) async {
  try {
    return ActionSuccess(await body());
  } catch (error, stackTrace) {
    final failure = toAppFailure(error, stackTrace);
    ErrorReporter.report(failure, context: context);
    return ActionFailure(failure);
  }
}
