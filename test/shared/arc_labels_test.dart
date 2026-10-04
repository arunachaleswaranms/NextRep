import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/shared/formatting/arc_labels.dart';

WinterArcSession _arc(LocalDate start) => WinterArcSession(
  id: 1,
  startDate: start,
  endDate: WinterArcRules.endDateFor(start),
  status: WinterArcStatus.completed,
  createdAt: DateTime(2026),
);

void main() {
  test('an arc names its year once, or both years when it spans two', () {
    expect(arcDateRange(_arc(LocalDate(2026, 7, 1))), '1 Jul – 30 Sep 2026');
    expect(
      arcDateRange(_arc(LocalDate(2026, 10, 4))),
      '4 Oct 2026 – 3 Jan 2027',
    );
  });
}
