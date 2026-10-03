import 'local_date.dart';

/// Source of the current time.
///
/// Inject a [Clock] instead of calling `DateTime.now()` so that day
/// calculations and timestamps are deterministic under test.
abstract interface class Clock {
  /// The current local date and time.
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

extension ClockToday on Clock {
  /// The user's current local calendar date.
  LocalDate today() => LocalDate.fromDateTime(now());
}
