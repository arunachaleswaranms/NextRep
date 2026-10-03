import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';

void main() {
  group('LocalDate', () {
    test('rejects invalid calendar dates', () {
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
      expect(LocalDate(2028, 2, 29).day, 29); // leap year
    });

    test('ISO round trip and zero padding', () {
      final date = LocalDate(2026, 3, 7);
      expect(date.toIsoString(), '2026-03-07');
      expect(LocalDate.parse('2026-03-07'), date);
      expect(() => LocalDate.parse('2026-3-7'), throwsFormatException);
    });

    test('addDays crosses month and year boundaries', () {
      expect(LocalDate(2026, 10, 31).addDays(1), LocalDate(2026, 11, 1));
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2026, 1, 1).addDays(-1), LocalDate(2025, 12, 31));
    });

    test('daysUntil is exact across DST transitions', () {
      // US/EU clocks change in late Oct / early Nov; calendar maths must not.
      expect(LocalDate(2026, 10, 24).daysUntil(LocalDate(2026, 10, 26)), 2);
      expect(LocalDate(2026, 10, 31).daysUntil(LocalDate(2026, 11, 2)), 2);
      expect(LocalDate(2026, 11, 2).daysUntil(LocalDate(2026, 10, 31)), -2);
    });

    test('fromDateTime takes the calendar date at any time of day', () {
      expect(
        LocalDate.fromDateTime(DateTime(2026, 10, 1, 23, 59, 59)),
        LocalDate(2026, 10, 1),
      );
      expect(
        LocalDate.fromDateTime(DateTime(2026, 10, 2)),
        LocalDate(2026, 10, 2),
      );
    });

    test('ordering and equality', () {
      final a = LocalDate(2026, 10, 1);
      final b = LocalDate(2026, 10, 2);
      expect(a.isBefore(b), isTrue);
      expect(b.isAfter(a), isTrue);
      expect(a, LocalDate(2026, 10, 1));
      expect({a, LocalDate(2026, 10, 1)}, hasLength(1));
    });
  });
}
