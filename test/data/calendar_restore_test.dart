import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/journey/arc_calendar.dart';
import 'package:nextrep/domain/journey/journey_day.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/features/journey/calendar_labels.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';

/// Phase 12C: the Calendar of Arcs restored from a format-4 backup (spec
/// § 12.8 K5, K7; brief § 32): an ended and a paused Arc, written through
/// the app's own services and lifecycle rows, exported, restored into a
/// fresh database and shown on several dates (including behind the export
/// date). Every cell, heading and pause row equals the source's, the ended
/// Arc never shows today or a missed day after its last day, and reading
/// the calendars writes nothing. All data synthetic.

/// Everything the calendar shows for one Arc, as text.
List<String> fingerprint(ArcCalendar c) => [
  for (final b in c.blocks) ...[
    calendarWeekHeading(b),
    for (final e in b.entries)
      switch (e) {
        CalendarDayEntry(:final day) =>
          '${calendarDayLabel(day.journeyDay)}|${day.state.name}|'
              '${day.isToday}|${day.isInteractive}',
        CalendarPauseEntry(:final pause) => calendarPauseText(pause),
      },
  ],
];

void main() {
  test('format 4 with an ended and a paused Arc: calendars identical to the '
      'source, also behind the export date; nothing written', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final app = TestApp(db, FakeClock(DateTime(2026, 10, 1)));

    // Arc 1: Rolling from 1 Oct, lived 3 days, ended on Day 3.
    final start1 = LocalDate(2026, 10, 1);
    at(app, start1);
    await app.winterArc.startNewArc(NewArcBaseline.fresh);
    final first = await app.winterArc.startWinterArc();
    for (var d = 0; d < 3; d++) {
      at(app, start1.addDays(d));
      if (d != 1) await completeAll(app);
    }
    await endArc(app, first.id, start1.addDays(2));

    // Arc 2: Rolling from 12 Oct, lived 5 days, paused from 17 Oct.
    final start2 = LocalDate(2026, 10, 12);
    at(app, start2);
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    final second = await app.winterArc.startWinterArc();
    for (var d = 0; d < 5; d++) {
      at(app, start2.addDays(d));
      await completeAll(app);
    }
    await addFreeze(db, second.id, start2.addDays(5));
    at(app, start2.addDays(7));

    final exported = (await app.backup.export()).bytes;
    expect((jsonDecode(utf8.decode(exported)) as Map)['formatVersion'], 4);
    Future<TestApp> restored() async {
      final target = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 10, 19)),
      );
      addTearDown(target.db.close);
      await target.backup.restore(await target.backup.inspect(exported));
      return target;
    }

    Future<Map<WinterArcStatus, ArcCalendar>> calendars(
      TestApp from,
      LocalDate date,
    ) async {
      at(from, date);
      final before = await snapshotAll(from.db);
      final out = <WinterArcStatus, ArcCalendar>{};
      for (final s in await from.sessions.listSessions()) {
        out[s.status] = ArcCalendar.of(await from.tracking.journeyFor(s.id));
      }
      expect(await snapshotAll(from.db), before, reason: 'read-only');
      return out;
    }

    final target = await restored();
    for (final date in [
      start2.addDays(7), // the export date, inside the pause
      start2.addDays(30), // long after
      start2.addDays(3), // behind the export date, before the pause
      start1.addDays(1), // behind the ended Arc's last day
    ]) {
      final source = await calendars(app, date);
      final copy = await calendars(target, date);
      expect(copy.keys, unorderedEquals(source.keys));
      for (final status in source.keys) {
        expect(
          fingerprint(copy[status]!),
          fingerprint(source[status]!),
          reason: '$status on $date',
        );
      }
      final ended = copy[WinterArcStatus.ended]!;
      expect(ended.days, hasLength(92));
      expect(ended.days.where((d) => d.isToday), isEmpty, reason: '$date');
      for (final d in ended.days.skip(3)) {
        expect(d.state, JourneyDayState.notReached, reason: '$date');
      }
      expect(
        ended.blocks.where((b) => b.isReviewable).map((b) => b.number),
        date.isBefore(start1) ? isEmpty : [1],
      );
      final paused = copy[WinterArcStatus.active]!;
      expect(paused.days, hasLength(92));
      expect(paused.pauses, hasLength(1));
      expect(paused.pauses.single.afterDay, 5);
    }
    final atExport = await calendars(target, start2.addDays(7));
    expect(
      calendarPauseText(atExport[WinterArcStatus.active]!.pauses.single),
      'Paused since 17 Oct',
    );
    expect(atExport[WinterArcStatus.active]!.initialWeek, 1);
    expect(atExport[WinterArcStatus.ended]!.initialWeek, 1);
  });
}
