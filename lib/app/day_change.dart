import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/time/clock.dart';

/// Calls [onDayChanged] just after each local midnight while it runs.
///
/// The app keeps it running only in the foreground, so a screen left open
/// overnight (or an arc that ends at midnight) moves to the new day without
/// a tap or a resume. It is restarted on every resume, which also covers a
/// clock or time-zone change made while the app was away.
///
/// The next midnight is computed from [clock] each time, so a DST change
/// never shifts it by an hour.
final class DayChangeTicker {
  DayChangeTicker({required this.clock, required this.onDayChanged});

  final Clock clock;
  final VoidCallback onDayChanged;

  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  /// (Re)arms the timer for the next local midnight.
  void start() {
    _timer?.cancel();
    _timer = Timer(untilNextDay(clock.now()), () {
      onDayChanged();
      start();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// The wait from [now] to one second past the next local midnight (the
  /// second of margin keeps the new date unambiguous).
  @visibleForTesting
  static Duration untilNextDay(DateTime now) {
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final wait = next.difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }
}
