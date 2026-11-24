import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/reconciliation.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';

/// Phase 12H defect D-2 (found on the emulator): Restart on the date an Arc
/// was resumed, before anything was logged that day, was offered by the
/// Restart screen and then refused by its transaction ("Couldn't restart.
/// Nothing was changed."): the last lived day fell before the pause just
/// closed, and an ended Arc may not hold a pause after `closed_on`.
///
/// Now the resume date counts as lived on its own date (like Day 1), the
/// same `closed_on` a restart the next morning gives. Real Drift, the real
/// services, an injected clock. All data synthetic.

final _day1 = LocalDate(2027, 4, 1);
LocalDate _d(int n) => _day1.addDays(n - 1);

/// An Arc lived Days 1–[lived], paused from the next date for [paused]
/// dates, resumed. Leaves the clock on the resume date, 09:00.
Future<(TestApp, WinterArcSession)> _resumed({
  int lived = 12,
  int paused = 2,
}) async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2027, 4, 1, 9)));
  final arc = await startRolling(app, _day1);
  await liveDays(app, _d(1), _d(lived));
  at(app, _d(lived), hour: 21);
  await pauseServiceOf(app).pause(sessionId: arc.id, frozenFrom: _d(lived + 1));
  final resumeOn = _d(lived + 1 + paused);
  at(app, resumeOn);
  final resumed = await pauseServiceOf(app)
      .resume(sessionId: arc.id, on: resumeOn);
  return (app, resumed);
}

void main() {
  test('restart on the resume date with nothing logged: accepted, ended on '
      'the resume date, the pause kept, every other row identical', () async {
    final (app, arc) = await _resumed();
    addTearDown(app.db.close);
    final resumeOn = app.clock.today();
    final preview = await restartServiceOf(app).preview(arc.id);
    expect(preview.canRestart, isTrue);
    expect(preview.closedOn, resumeOn, reason: 'the screen shows Day 13');
    final before = await snapshotAll(app.db);
    final outcome = await restartNow(app, arc.id);
    expectOnlyRestart(
      before,
      await snapshotAll(app.db),
      oldId: arc.id,
      newId: outcome.started.id,
      closedOn: resumeOn,
      newHabits: before['habits']!.length,
    );
    final ended = outcome.ended;
    expect(ended.closedOn, resumeOn);
    expect(ended.dayNumberOf(resumeOn), 13);
    expect(ended.freezes, hasLength(1), reason: 'the closed pause is kept');
    expect(ended.freezes.single.resumedOn, resumeOn);
    final f = await expectArcReconciles(app, arc.id, context: 'ended');
    expect((f.elapsed, f.open), (13, 0), reason: 'the resume date once');

    // The export validates and restores row for row (F2-11).
    final bytes = (await app.backup.export()).bytes;
    final other = TestApp(memoryDatabase(), FakeClock(app.clock.now()));
    addTearDown(other.db.close);
    await other.backup.restore(await other.backup.inspect(bytes));
    await expectAllArcsReconcile(other, context: 'restored');
  });

  test('unchanged elsewhere: with activity on the resume date, and the day '
      'after with nothing logged, closed_on is the resume date too', () async {
    final (a, arcA) = await _resumed();
    addTearDown(a.db.close);
    await completeHabit(a, 'water');
    expect((await restartNow(a, arcA.id)).ended.closedOn, a.clock.today());

    final (b, arcB) = await _resumed();
    addTearDown(b.db.close);
    final resumeOn = b.clock.today();
    at(b, resumeOn.addDays(1));
    expect((await restartNow(b, arcB.id)).ended.closedOn, resumeOn);
  });

  test('whenever the Restart screen offers a restart, the transaction '
      'accepts it (pause after Days 1, 5, 30; 1, 2 or 4 paused dates; restart '
      '0–2 days after the resume, logged or not)', () async {
    var cases = 0;
    for (final lived in [1, 5, 30]) {
      for (final paused in [1, 2, 4]) {
        for (final later in [0, 1, 2]) {
          for (final logged in [false, true]) {
            final (app, arc) = await _resumed(lived: lived, paused: paused);
            final resumeOn = app.clock.today();
            at(app, resumeOn.addDays(later));
            await app.lifecycle.reconcile();
            if (logged) await completeHabit(app, 'water');
            final preview = await restartServiceOf(app).preview(arc.id);
            expect(preview.canRestart, isTrue);
            final outcome = await restartNow(app, arc.id);
            final closed = outcome.ended.closedOn!;
            expect(
              closed.isBefore(resumeOn),
              isFalse,
              reason: 'never before the pause it follows',
            );
            expect(outcome.ended.isFrozenOn(closed), isFalse);
            await app.db.close();
            cases++;
          }
        }
      }
    }
    expect(cases, 54);
  });
}
