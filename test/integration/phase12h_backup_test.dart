import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/reconciliation.dart';
import '../support/restart_support.dart';
import '../support/review_db.dart';

/// Phase 12H backup qualification (brief § 7): a format-4 round trip of a
/// complex synthetic state built **only through the app's services**:
///
/// * an earlier completed Arc (goal revisions, a Minimum Day, a
///   reflection, achievements);
/// * an Arc ended early by Restart, with two closed pauses, Perfect,
///   Minimum and partial days, goal revisions and a reflection;
/// * and, respecting the one-open-session rule, either (A) the restarted
///   Arc, paused with an earlier closed pause, or (B) a saved, reordered
///   setup with a custom habit;
/// * daily, reflection and Hydration Coach reminders, Focus Guard with
///   two apps, and sounds off with Warm Ember.
///
/// It is restored over a device holding other data and other sound
/// settings. Every table is compared with the source, row for row; the
/// only differences allowed are the documented restore rules (every
/// reminder, Hydration Coach and Focus Guard off; apps and budget kept;
/// sound settings as stored). The restored Arcs reconcile on every screen
/// with the same figures as the source, the app's launch work awards no
/// XP or achievement, and an export of the restored data restores to the
/// same rows again. All data is synthetic.

const _video = 'org.example.video';
const _chat = 'org.example.chat';

LocalDate _d(int y, int m, int d) => LocalDate(y, m, d);

Future<void> _liveOn(TestApp app, LocalDate date, int habits) async {
  at(app, date, hour: 19);
  await app.lifecycle.reconcile();
  final today = await app.tracking.today();
  for (final e in today.entries.take(habits)) {
    await completeHabit(app, e.habit.id);
  }
  await app.achievements.reconcile();
}

/// The shared history: a completed 2026 Arc and an Arc ended by Restart
/// on 2 Apr 2027 with two closed pauses. Returns the restarted Arc.
Future<WinterArcSession> _history(TestApp app) async {
  await runFirstArc(app); // completed, closes 1 Oct 2026
  final arc = await startRolling(app, _d(2027, 3, 1));
  final pauses = pauseServiceOf(app);
  for (var n = 1; n <= 6; n++) {
    await _liveOn(app, _d(2027, 3, n), n.isEven ? 4 : 2);
  }
  at(app, _d(2027, 3, 6), hour: 20);
  await app.tracking.editHabit(
    habitId: 'water',
    edit: const HabitEdit(target: 10, minimumTarget: 4),
    date: app.clock.today(),
  );
  await pauses.pause(sessionId: arc.id, frozenFrom: _d(2027, 3, 7));
  at(app, _d(2027, 3, 10), hour: 8);
  await pauses.resume(sessionId: arc.id, on: _d(2027, 3, 10));
  at(app, _d(2027, 3, 10), hour: 19);
  await app.tracking.activateMinimumDay(date: app.clock.today());
  await completeAll(app);
  await app.reflections.save(
    sessionId: arc.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Back on track'),
  );
  await _liveOn(app, _d(2027, 3, 11), 4);
  at(app, _d(2027, 3, 11), hour: 21);
  await pauses.pause(sessionId: arc.id, frozenFrom: _d(2027, 3, 12));
  at(app, _d(2027, 3, 20), hour: 8);
  await pauses.resume(sessionId: arc.id, on: _d(2027, 3, 20));
  for (var d = 20; d <= 31; d++) {
    await _liveOn(app, _d(2027, 3, d), d % 3);
  }
  await _liveOn(app, _d(2027, 4, 1), 4);
  at(app, _d(2027, 4, 2), hour: 9);
  await completeHabit(app, 'water');
  final outcome = await restartNow(app, arc.id);
  expect(outcome.ended.closedOn, _d(2027, 4, 2));
  return outcome.started;
}

Future<void> _settings(TestApp app) async {
  await app.reminders.update(
    (p) => p.copyWith(
      dailyEnabled: true,
      reflectionEnabled: true,
      hydrationEnabled: true,
    ),
  );
  await DriftFocusGuardSettingsRepository(app.db).save(
    const FocusGuardSettings(
      enabled: true,
      dailyBudgetMinutes: 45,
      selectedPackages: [_video, _chat],
    ),
    at: app.clock.now(),
  );
  await DriftFeedbackPreferencesRepository(app.db).save(
    const FeedbackPreferences(
      soundsEnabled: false,
      soundTheme: SoundTheme.warmEmber,
    ),
    at: app.clock.now(),
  );
}

/// Source A: the restarted Arc lived, paused once and resumed, then paused
/// again (open) at export.
Future<TestApp> _sourcePaused() async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1, 8)));
  final fresh = await _history(app);
  await _liveOn(app, _d(2027, 4, 2), 3);
  await _liveOn(app, _d(2027, 4, 3), 5);
  at(app, _d(2027, 4, 3), hour: 21);
  final pauses = pauseServiceOf(app);
  await pauses.pause(sessionId: fresh.id, frozenFrom: _d(2027, 4, 4));
  at(app, _d(2027, 4, 6), hour: 8);
  await pauses.resume(sessionId: fresh.id, on: _d(2027, 4, 6));
  await _liveOn(app, _d(2027, 4, 6), 4);
  at(app, _d(2027, 4, 6), hour: 21);
  await pauses.pause(sessionId: fresh.id, frozenFrom: _d(2027, 4, 7));
  at(app, _d(2027, 4, 9), hour: 10);
  await _settings(app);
  return app;
}

/// Source B: the restarted Arc runs to completion, then a reordered setup
/// with a custom habit is saved.
Future<TestApp> _sourceSetup() async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1, 8)));
  final fresh = await _history(app);
  await _liveOn(app, _d(2027, 4, 3), 5);
  at(app, fresh.dateOfDay(93)!, hour: 9);
  await app.lifecycle.reconcile();
  await app.achievements.reconcile();
  expect(
    (await app.sessions.sessionById(fresh.id))!.status,
    WinterArcStatus.completed,
  );
  await app.winterArc.beginSetup();
  final custom = await app.winterArc.addCustomHabit(
    const HabitDraft(
      title: 'Stretch Breaks',
      type: HabitType.count,
      iconKey: 'star',
      target: 4,
      minimumTarget: 2,
      unit: 'breaks',
    ),
  );
  final ids = [for (final h in await app.winterArc.setupHabits()) h.id];
  await app.winterArc.reorderSetupHabits([
    custom.id,
    for (final id in ids.reversed)
      if (id != custom.id) id,
  ]);
  await _settings(app);
  return app;
}

/// A device holding other data and other sound settings.
Future<TestApp> _target(LocalDate today) async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(today.year, today.month, today.day, 9)),
  );
  await startRolling(app, today.addDays(-3));
  await _liveOn(app, today.addDays(-3), 4);
  at(app, today, hour: 9);
  await DriftFeedbackPreferencesRepository(app.db).save(
    const FeedbackPreferences(
      soundsEnabled: true,
      soundTheme: SoundTheme.summitSpark,
    ),
    at: app.clock.now(),
  );
  return app;
}

/// [snapshot] with the documented restore rules applied to the source:
/// every reminder and Hydration Coach off, Focus Guard off with its apps
/// and budget kept. The settings rows' bookkeeping timestamps
/// (`updated_at`, `selected_at`) are not in the backup format and are not
/// compared.
DbSnapshot _asRestored(DbSnapshot snapshot) => {
  for (final entry in snapshot.entries)
    entry.key: [
      for (final row in entry.value)
        switch (entry.key) {
          'reminder_preferences' => {
            ...row,
            'daily_enabled': 0,
            'reflection_enabled': 0,
            'hydration_enabled': 0,
            'updated_at': null,
          },
          'focus_guard_preferences' => {
            ...row,
            'enabled': 0,
            'updated_at': null,
            'last_nudged_on': null,
          },
          'feedback_preferences' => {...row, 'updated_at': null},
          // Not in the backup format: restore stamps it with the backup's
          // `exportedAt` (DriftBackupStore.replaceAll).
          'focus_guard_selected_apps' => {...row, 'selected_at': null},
          _ => row,
        },
    ],
};

/// [snapshot] in a comparable form: each table's rows as sorted JSON, with
/// every session id shifted by [offset] (restore numbers restored Arcs
/// after every id the device has used, `DriftBackupStore._idOffset`) and
/// the child tables' own auto-increment `id` left out. Everything else is
/// compared exactly.
Map<String, List<String>> _canonical(DbSnapshot snapshot, {int offset = 0}) => {
  for (final entry in snapshot.entries)
    entry.key: [
      for (final row in entry.value)
        jsonEncode(() {
          final r = Map<String, Object?>.of(row);
          if (entry.key == 'winter_arc_sessions') {
            r['id'] = (r['id']! as int) + offset;
          } else if (r.containsKey('session_id')) {
            r['session_id'] = (r['session_id']! as int) + offset;
            r.remove('id');
          }
          return r;
        }()),
    ]..sort(),
};

void main() {
  for (final (name, source) in [
    ('A: completed + ended + paused open Arc', _sourcePaused),
    ('B: completed + ended + completed + saved setup', _sourceSetup),
  ]) {
    test(
      'format-4 round trip, $name: every table as stored, settings off, '
      'sounds as stored, figures equal on every screen, nothing awarded',
      () async {
        final src = await source();
        addTearDown(src.db.close);
        final sourceRows = await snapshotAll(src.db);
        final sourceFigures = await expectAllArcsReconcile(src, context: 'src');

        final export = await src.backup.export();
        final json = jsonDecode(utf8.decode(export.bytes)) as Map;
        expect(json['formatVersion'], 4, reason: 'the app always writes 4');
        expect(BackupFormat.formatVersion, 4);

        final target = await _target(src.clock.today());
        addTearDown(target.db.close);
        final restored = await target.backup.restore(
          await target.backup.inspect(export.bytes),
        );
        expect(restored.remindersCleared, isTrue);
        final restoredRows = await snapshotAll(target.db);
        // The restore rules themselves, on the restored side (the
        // comparison below normalises them on both sides).
        final sourcePrefs = sourceRows['reminder_preferences']!.single;
        expect(
          (
            sourcePrefs['daily_enabled'],
            sourcePrefs['reflection_enabled'],
            sourcePrefs['hydration_enabled'],
          ),
          (1, 1, 1),
          reason: 'the source had every reminder on',
        );
        final prefs = restoredRows['reminder_preferences']!.single;
        expect(
          (
            prefs['daily_enabled'],
            prefs['reflection_enabled'],
            prefs['hydration_enabled'],
          ),
          (0, 0, 0),
          reason: 'a restore turns every reminder and Hydration Coach off',
        );
        for (final key in sourcePrefs.keys) {
          if (key.endsWith('_enabled') || key == 'updated_at') continue;
          expect(prefs[key], sourcePrefs[key], reason: 'reminder $key kept');
        }
        final offset =
            (restoredRows['winter_arc_sessions']!.first['id']! as int) -
            (sourceRows['winter_arc_sessions']!.first['id']! as int);
        expect(offset, greaterThan(0), reason: 'ids never reused');
        expect(
          _canonical(_asRestored(restoredRows)),
          _canonical(_asRestored(sourceRows), offset: offset),
          reason: 'every table as in the source, row for row',
        );
        final focus = await DriftFocusGuardSettingsRepository(target.db).load();
        expect(focus.enabled, isFalse, reason: 'Focus Guard off');
        expect(focus.dailyBudgetMinutes, 45, reason: 'budget kept');
        expect(focus.selectedPackages, [_video, _chat], reason: 'apps kept');
        expect(
          await DriftFeedbackPreferencesRepository(target.db).load(),
          const FeedbackPreferences(
            soundsEnabled: false,
            soundTheme: SoundTheme.warmEmber,
          ),
          reason: 'format 4 restores the stored sound settings',
        );
        expect(target.scheduler.pending, isEmpty, reason: 'nothing scheduled');

        // The same figures on every screen.
        final targetFigures = await expectAllArcsReconcile(
          target,
          context: 'restored',
        );
        expect(
          [for (final f in targetFigures) f.toString()],
          [for (final f in sourceFigures) f.toString()],
          reason: 'restored history reads exactly as the source',
        );

        // The app's launch work after a restore awards nothing.
        await target.lifecycle.reconcile();
        await target.achievements.reconcile();
        final afterLaunch = await snapshotAll(target.db);
        for (final table in [
          'xp_transactions',
          'achievement_unlocks',
          'daily_habit_progress_entries',
          'winter_arc_sessions',
          'arc_freezes',
        ]) {
          expect(
            afterLaunch[table],
            restoredRows[table],
            reason: '$table: no XP, unlock or lifecycle change after restore',
          );
        }

        // An export of the restored data restores to the same rows again.
        final again = await target.backup.export();
        final third = TestApp(memoryDatabase(), FakeClock(target.clock.now()));
        addTearDown(third.db.close);
        await third.backup.restore(await third.backup.inspect(again.bytes));
        expect(
          _canonical(_asRestored(await snapshotAll(third.db))),
          _canonical(_asRestored(afterLaunch)),
          reason: 'a second round trip changes nothing',
        );

        // B: the saved setup is the open session; the hub is home.
        final open = [
          for (final s in await target.sessions.listSessions())
            if (s.status.isUnfinished) s,
        ];
        expect(open, hasLength(1), reason: 'one open session');
        if (name.startsWith('B')) {
          expect(open.single.status, WinterArcStatus.setup);
          final setup = await target.winterArc.setup();
          expect(setup.habits.first.title, 'Stretch Breaks', reason: 'order');
        } else {
          expect(open.single.hasOpenFreeze, isTrue, reason: 'still paused');
        }
      },
    );
  }

  legacyFormats();
}

/// The genuine legacy files: format 1 (v1.0.0 era), format 2 (v1.1.0) and
/// format 3, written by NextRep v1.2.0's own services and exporter (tag
/// `v1.2.0`, Phase 12H qualification: a completed Arc, an active Arc with
/// a Minimum Day, a revision and a reflection, every reminder, Hydration
/// Coach and Focus Guard on). All synthetic.
const _legacy = [
  (1, 'test/fixtures/phase5_backup_v1.nextrep'),
  (2, 'test/fixtures/v1_1_backup_v2.nextrep'),
  (3, 'test/fixtures/v1_2_0_backup_v3.nextrep'),
];

void legacyFormats() {
  for (final (format, path) in _legacy) {
    test('format $format (genuine file) restores on v1.3: no pause, no '
        'closedOn, the device keeps its sound setting, every Arc reconciles, '
        'and launch work adds no XP', () async {
      final bytes = File(path).readAsBytesSync();
      final json = jsonDecode(utf8.decode(bytes)) as Map;
      expect(json['formatVersion'], format);
      final device = await _target(_d(2026, 11, 2));
      addTearDown(device.db.close);
      await device.backup.restore(await device.backup.inspect(bytes));
      final rows = await snapshotAll(device.db);
      expect(rows['arc_freezes'], isEmpty, reason: 'no pause before format 4');
      for (final s in rows['winter_arc_sessions']!) {
        expect(s['closed_on'], isNull);
        expect(s['status'], isNot('ended'));
      }
      expect(
        await DriftFeedbackPreferencesRepository(device.db).load(),
        const FeedbackPreferences(
          soundsEnabled: true,
          soundTheme: SoundTheme.summitSpark,
        ),
        reason: "formats 1–3 keep this device's sound setting",
      );
      expect(device.scheduler.pending, isEmpty, reason: 'nothing scheduled');
      final ledger = await xpRows(device.db);
      await device.lifecycle.reconcile();
      await device.achievements.reconcile();
      expect(await xpRows(device.db), ledger, reason: 'no XP awarded');
      await expectAllArcsReconcile(device, context: 'format $format');
    });
  }
}
