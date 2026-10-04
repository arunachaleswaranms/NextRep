import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

WinterArcSession sessionStarting(LocalDate start) => WinterArcSession(
  id: 1,
  kind: ArcKind.rolling92,
  participationStartDate: start,
  startDate: start,
  endDate: WinterArcRules.endDateFor(start),
  status: WinterArcStatus.active,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  final oct1 = LocalDate(2026, 10, 1);
  final arc = sessionStarting(oct1);

  group('Winter Arc window', () {
    test('92 days starting Oct 1 ends exactly on Dec 31', () {
      expect(arc.endDate, LocalDate(2026, 12, 31));
      expect(arc.lengthInDays, 92);
    });

    test('a later start still spans 92 inclusive days', () {
      final late = sessionStarting(LocalDate(2026, 10, 15));
      expect(late.endDate, LocalDate(2027, 1, 14));
      expect(late.lengthInDays, WinterArcRules.lengthInDays);
    });
  });

  group('day calculation', () {
    ArcDayPosition on(int y, int m, int d) =>
        arc.positionOn(LocalDate(y, m, d));

    test('start date is Day 1', () {
      expect(
        on(2026, 10, 1),
        isA<ArcInProgress>().having((p) => p.dayNumber, 'day', 1),
      );
    });

    test('end date is Day 92', () {
      expect(
        on(2026, 12, 31),
        isA<ArcInProgress>().having((p) => p.dayNumber, 'day', 92),
      );
    });

    test('month boundaries', () {
      expect((on(2026, 10, 31) as ArcInProgress).dayNumber, 31);
      expect((on(2026, 11, 1) as ArcInProgress).dayNumber, 32);
      expect((on(2026, 12, 1) as ArcInProgress).dayNumber, 62);
    });

    test('across the DST change (Nov 1, 2026 in the US)', () {
      expect((on(2026, 11, 2) as ArcInProgress).dayNumber, 33);
    });

    test('before the start is not started', () {
      expect(
        on(2026, 9, 29),
        isA<ArcNotStarted>().having((p) => p.daysUntilStart, 'days', 2),
      );
    });

    test('the day after the end is finished', () {
      expect(on(2027, 1, 1), isA<ArcFinished>());
    });

    test('every day in the window maps to a unique 1..92 index', () {
      final days = [
        for (var i = 0; i < 92; i++)
          (arc.positionOn(oct1.addDays(i)) as ArcInProgress).dayNumber,
      ];
      expect(days, List.generate(92, (i) => i + 1));
    });

    test('day index changes at local midnight, not 24h after start time', () {
      final lateNight = LocalDate.fromDateTime(DateTime(2026, 10, 1, 23, 59));
      final justAfter = LocalDate.fromDateTime(DateTime(2026, 10, 2, 0, 0, 1));
      expect((arc.positionOn(lateNight) as ArcInProgress).dayNumber, 1);
      expect((arc.positionOn(justAfter) as ArcInProgress).dayNumber, 2);
    });
  });
}
