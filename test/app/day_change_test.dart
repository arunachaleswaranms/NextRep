import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/day_change.dart';

import '../support/fakes.dart';

void main() {
  group('DayChangeTicker.untilNextDay', () {
    test('waits until one second past the next local midnight', () {
      expect(
        DayChangeTicker.untilNextDay(DateTime(2026, 10, 5, 23, 59, 50)),
        const Duration(seconds: 11),
      );
      expect(
        DayChangeTicker.untilNextDay(DateTime(2026, 10, 5, 9)),
        const Duration(hours: 15, seconds: 1),
      );
    });

    test('crosses month and year ends', () {
      expect(
        DayChangeTicker.untilNextDay(DateTime(2026, 9, 30, 23, 59)),
        const Duration(minutes: 1, seconds: 1),
      );
      expect(
        DayChangeTicker.untilNextDay(DateTime(2026, 12, 31, 23, 59, 59)),
        const Duration(seconds: 2),
      );
    });

    test('at midnight itself it waits for the next one', () {
      expect(
        DayChangeTicker.untilNextDay(DateTime(2026, 10, 6)),
        const Duration(days: 1, seconds: 1),
      );
    });
  });

  // testWidgets runs in fake time: pump(duration) elapses the timers.
  testWidgets('fires once per midnight, re-arms itself, and stops', (
    tester,
  ) async {
    final clock = FakeClock(DateTime(2026, 10, 5, 23, 59, 50));
    var ticks = 0;
    final ticker = DayChangeTicker(clock: clock, onDayChanged: () => ticks++);
    ticker.start();
    expect(ticker.isRunning, isTrue);

    clock.advance(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    expect(ticks, 1);
    expect(ticker.isRunning, isTrue, reason: 're-armed for the next day');

    clock.advance(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(ticks, 2);

    ticker.stop();
    expect(ticker.isRunning, isFalse);
    clock.advance(const Duration(days: 2));
    await tester.pump(const Duration(days: 2));
    expect(ticks, 2, reason: 'stopped (backgrounded) tickers never fire');
  });

  testWidgets('restarting after the clock jumped (resume, time-zone change) '
      'aims at the new midnight', (tester) async {
    final clock = FakeClock(DateTime(2026, 10, 5, 9));
    var ticks = 0;
    final ticker = DayChangeTicker(clock: clock, onDayChanged: () => ticks++)
      ..start();
    // The device clock moves to 23:59:58 while the app is away.
    clock.current = DateTime(2026, 10, 5, 23, 59, 58);
    ticker.start();
    clock.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(ticks, 1);
    ticker.stop();
  });
}
