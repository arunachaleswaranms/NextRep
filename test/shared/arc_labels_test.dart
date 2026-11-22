import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/shared/formatting/arc_labels.dart';

WinterArcSession _arc(LocalDate start) => WinterArcSession(
  id: 1,
  kind: ArcKind.rolling92,
  participationStartDate: start,
  startDate: start,
  endDate: WinterArcRules.endDateFor(start),
  status: WinterArcStatus.completed,
  createdAt: DateTime(2026),
);

void main() {
  test('an arc names its year once, or both years when it spans two', () {
    expect(
      arcDateRange(_arc(LocalDate(2026, 7, 1)), today: LocalDate(2027, 1, 1)),
      '1 Jul – 30 Sep 2026',
    );
    expect(
      arcDateRange(_arc(LocalDate(2026, 10, 4)), today: LocalDate(2027, 1, 1)),
      '4 Oct 2026 – 3 Jan 2027',
    );
  });

  group('R2: a pause in the date range', () {
    final start = LocalDate(2027, 3, 1);
    LocalDate d(int n) => start.addDays(n - 1);
    final at = DateTime(2027, 3, 1, 9);
    WinterArcSession rolling(List<ArcFreeze> freezes) => WinterArcSession(
      id: 1,
      kind: ArcKind.rolling92,
      participationStartDate: start,
      startDate: start,
      endDate: WinterArcRules.endDateFor(start)
          .addDays(ArcFreezeRules.closedPausedDays(freezes)),
      status: WinterArcStatus.active,
      createdAt: at,
      startedAt: at,
      freezes: freezes,
    );
    final open = ArcFreeze(frozenFrom: d(11), requestedAt: at);
    final closed = ArcFreeze(
      frozenFrom: d(11),
      resumedOn: d(20),
      requestedAt: at,
      resumedAt: at,
    );

    test('scheduled, in effect, rolled back, cancelled, resumed', () {
      expect(
        arcDateRange(rolling([open]), today: d(10)),
        '1 Mar 2027 – pause scheduled',
      );
      expect(
        arcDateRange(rolling([open]), today: d(11)),
        '1 Mar 2027 – paused',
      );
      expect(
        arcDateRange(rolling([open]), today: d(40)),
        '1 Mar 2027 – paused',
      );
      expect(
        arcDateRange(rolling([open]), today: d(8)),
        '1 Mar 2027 – pause scheduled',
        reason: 'the clock moved back before the pause',
      );
      expect(arcDateRange(rolling([]), today: d(10)), '1 Mar – 31 May 2027');
      for (final today in [d(15), d(30), d(200)]) {
        expect(
          arcDateRange(rolling([closed]), today: today),
          '1 Mar – 9 Jun 2027',
          reason: 'a closed pause keeps the range, also on $today',
        );
      }
      expect(
        arcHeading(rolling([open]), today: d(10)),
        'Winter Arc · 1 Mar 2027 – pause scheduled',
      );
    });

    test('a completed arc with a closed pause keeps its range', () {
      final done = rolling([closed])
          .copyWith(status: WinterArcStatus.completed);
      expect(arcDateRange(done, today: d(300)), '1 Mar – 9 Jun 2027');
    });
  });
}
