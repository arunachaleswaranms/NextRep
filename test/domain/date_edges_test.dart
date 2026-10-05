import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

/// Release qualification of calendar edges that a device can't safely be
/// put through: a time-zone change after starting, and DST changes inside
/// a season. Day numbers and participation come from stored calendar dates
/// only, never from the start instant or the current UTC offset.
void main() {
  WinterArcSession seasonal({LocalDate? joined, DateTime? startedAt}) =>
      WinterArcSession(
        id: 1,
        kind: ArcKind.seasonalWinter,
        startDate: LocalDate(2026, 10, 1),
        endDate: LocalDate(2026, 12, 31),
        participationStartDate: joined ?? LocalDate(2026, 10, 15),
        status: WinterArcStatus.active,
        createdAt: DateTime.utc(2026, 9, 20, 8),
        startedAt: startedAt ?? DateTime.utc(2026, 10, 15, 8),
      );

  test('a time-zone change that moves the start instant to another local '
      'date does not renumber days or move the join date', () {
    // Started 23:30 UTC on 14 Oct: already 15 Oct in Asia, still 14 Oct in
    // the Americas. The stored join date decides, wherever the phone is.
    final arc = seasonal(startedAt: DateTime.utc(2026, 10, 14, 23, 30));
    expect(arc.participationStartDate, LocalDate(2026, 10, 15));
    expect(arc.dayNumberOf(LocalDate(2026, 10, 15)), 15);
    expect(arc.isParticipatingOn(LocalDate(2026, 10, 14)), isFalse);
    expect(arc.isParticipatingOn(LocalDate(2026, 10, 15)), isTrue);
  });

  test('a rolling arc counts from its stored Day 1, not from startedAt', () {
    final day1 = LocalDate(2026, 3, 28);
    final arc = WinterArcSession(
      id: 2,
      kind: ArcKind.rolling92,
      startDate: day1,
      endDate: WinterArcRules.endDateFor(day1),
      participationStartDate: day1,
      status: WinterArcStatus.active,
      createdAt: DateTime.utc(2026, 3, 27, 23),
      startedAt: DateTime.utc(2026, 3, 27, 23, 30), // 27 Mar in UTC
    );
    expect(arc.dayNumberOf(day1), 1);
    // Across the EU spring DST change (29 Mar 2026).
    expect(arc.dayNumberOf(LocalDate(2026, 3, 30)), 3);
    expect(arc.dayNumberOf(arc.endDate), WinterArcRules.lengthInDays);
  });

  test('the season keeps 92 days across both autumn DST changes', () {
    final arc = seasonal(joined: LocalDate(2026, 10, 1));
    // EU clocks go back on 25 Oct 2026, US clocks on 1 Nov 2026.
    expect(arc.dayNumberOf(LocalDate(2026, 10, 25)), 25);
    expect(arc.dayNumberOf(LocalDate(2026, 10, 26)), 26);
    expect(arc.dayNumberOf(LocalDate(2026, 11, 1)), 32);
    expect(arc.dayNumberOf(LocalDate(2026, 11, 2)), 33);
    expect(arc.dayNumberOf(LocalDate(2026, 12, 31)), 92);
    expect(
      arc.participatingDatesThrough(LocalDate(2026, 12, 31)),
      hasLength(92),
    );
  });

  test('wall-clock times on either side of a DST change map to the dates '
      'a user sees', () {
    // Whatever the device's zone, the local calendar date of a local
    // wall-clock time is the date the user reads on the phone.
    for (final (time, date) in [
      (DateTime(2026, 10, 25, 0, 30), LocalDate(2026, 10, 25)),
      (DateTime(2026, 10, 25, 23, 59), LocalDate(2026, 10, 25)),
      (DateTime(2026, 11, 1, 1, 30), LocalDate(2026, 11, 1)),
      (DateTime(2026, 11, 2, 0, 0, 1), LocalDate(2026, 11, 2)),
    ]) {
      expect(LocalDate.fromDateTime(time), date);
    }
  });
}
