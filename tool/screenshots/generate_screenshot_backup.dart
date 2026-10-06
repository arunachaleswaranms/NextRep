// Writes a synthetic NextRep backup for store screenshots: invented habits
// and reflections, no personal data. Restore it on a test device or
// emulator through Data & Backup > Restore Backup, then follow the capture
// steps in docs/STORE_METADATA.md#screenshots.
//
// Dev-time only. It is not a test and is not run by `flutter test` (which
// only looks in test/), and nothing here ships in the app. The data is made
// through the app's own services on an in-memory database, then exported
// with the real backup service, so the file passes the same validation as a
// user's export.
//
// The active arc ends on the capture date, so pass the device's date (it
// defaults to today):
//
//   SCREENSHOT_DATE=2026-10-06 flutter test tool/screenshots/generate_screenshot_backup.dart
//
// Output: build/screenshots/nextrep-screenshots-<date>.nextrep (git-ignored).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../../test/support/fakes.dart';

/// Invented reflections, used in turn.
const _reflections = [
  (Mood.good, 'Ran before work', 'Lights out earlier'),
  (Mood.excellent, 'Finished the chapter', ''),
  (Mood.okay, 'Short walk at lunch', 'Less screen time'),
  (Mood.good, 'Cooked at home', ''),
  (Mood.rough, 'Still showed up', 'Plan tomorrow tonight'),
  (Mood.excellent, 'New stretch routine', ''),
];

const _stretch = HabitDraft(
  title: 'Stretch',
  type: HabitType.duration,
  iconKey: 'walk',
  target: 10,
  minimumTarget: 5,
);

DateTime _captureDate() {
  final value = Platform.environment['SCREENSHOT_DATE'];
  final now = DateTime.now();
  return value == null
      ? DateTime(now.year, now.month, now.day)
      : DateTime.parse(value);
}

/// Logs [habitId] today as done: numeric habits to their goal, a clock-time
/// habit at [bedtime].
Future<void> _complete(
  TestApp app,
  String habitId, {
  NightTime? bedtime,
}) async {
  while (true) {
    final today = await app.tracking.today();
    final entry = today.entries.firstWhere((e) => e.habit.id == habitId);
    if (entry.progress.completed) return;
    final type = entry.habit.type;
    await app.tracking.perform(
      habitId: habitId,
      action: switch (type) {
        HabitType.timeBefore => HabitAction.setTime,
        HabitType.binary => HabitAction.complete,
        _ => HabitAction.increment,
      },
      date: today.date,
      time: type == HabitType.timeBefore ? bedtime ?? NightTime(23, 5) : null,
    );
    if (type == HabitType.timeBefore) return;
  }
}

/// A mixed day [index] of an arc: mostly Perfect Days, with a Minimum Day,
/// a partial day and a missed day in a steady rhythm.
Future<void> _liveDay(TestApp app, int arcId, int index) async {
  final today = await app.tracking.today();
  final ids = [for (final e in today.entries) e.habit.id];
  switch (index % 11) {
    case 9: // missed
      return;
    case 6: // partial, with a late night
      await _complete(app, ids.first);
      await _complete(app, 'sleep_before', bedtime: NightTime(0, 40));
    case 3: // a completed Minimum Day
      await app.tracking.activateMinimumDay(date: today.date);
      for (final id in ids) {
        await _complete(app, id);
      }
    default:
      for (final id in ids) {
        await _complete(app, id);
      }
  }
  if (index.isEven) {
    final (mood, win, improve) = _reflections[index ~/ 2 % _reflections.length];
    await app.reflections.save(
      sessionId: arcId,
      date: today.date,
      draft: ReflectionDraft(mood: mood, win: win, improvement: improve),
    );
  }
  await app.achievements.reconcile();
}

void main() {
  test('write the screenshot backup', () async {
    final capture = _captureDate();
    final db = memoryDatabase();
    addTearDown(db.close);
    final app = TestApp(db, FakeClock(DateTime(capture.year - 1, 10, 15, 8)));

    // Arc 1: last year's Seasonal Winter Arc, joined late on 15 October and
    // finished at the summit.
    final seasonal = await app.winterArc.beginSetup(
      kind: ArcKind.seasonalWinter,
    );
    await app.winterArc.setHabitEnabled('sleep_before', enabled: true);
    await app.winterArc.addCustomHabit(_stretch);
    await app.winterArc.startWinterArc();
    final seasonEnd = DateTime(capture.year - 1, 12, 31);
    var day = DateTime(capture.year - 1, 10, 15);
    for (var i = 0; !day.isAfter(seasonEnd); i++) {
      app.clock.current = DateTime(day.year, day.month, day.day, 20);
      await _liveDay(app, seasonal.id, i);
      day = DateTime(day.year, day.month, day.day + 1);
    }
    app.clock.current = DateTime(capture.year, 1, 1, 9);
    await app.lifecycle.reconcile();
    await app.achievements.reconcile();

    // Arc 2: a Rolling Arc on Day 20 on the capture date, with the same
    // habits. Today: 3 of 6 done, so the last three make a Perfect Day on
    // camera.
    final start = DateTime(capture.year, capture.month, capture.day - 19);
    app.clock.current = DateTime(start.year, start.month, start.day, 8);
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    final rolling = await app.winterArc.startWinterArc();
    for (var i = 0; i < 19; i++) {
      final d = DateTime(start.year, start.month, start.day + i, 20);
      app.clock.current = d;
      await _liveDay(app, rolling.id, i);
    }
    app.clock.current = DateTime(capture.year, capture.month, capture.day, 8);
    final today = await app.tracking.today();
    for (final entry in today.entries.take(3)) {
      await _complete(app, entry.habit.id);
    }
    await app.reflections.save(
      sessionId: rolling.id,
      date: today.date,
      draft: const ReflectionDraft(
        mood: Mood.good,
        win: 'Morning run in the frost',
        improvement: 'Pack the gym bag tonight',
      ),
    );
    await app.achievements.reconcile();

    final export = await app.backup.export();
    final date = capture.toIso8601String().substring(0, 10);
    final file = File('build/screenshots/nextrep-screenshots-$date.nextrep');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(export.bytes);
    // ignore: avoid_print
    print(
      'Wrote ${file.path}: ${export.summary.arcCount} arcs, '
      '${export.summary.reflectionCount} reflections, '
      '${export.bytes.length} bytes.',
    );
  });
}
