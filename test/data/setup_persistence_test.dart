import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';

/// Phase 12D, spec § 4.2 and addendum § L2 (R): a saved setup is the
/// `setup` session itself, so every committed change survives the app
/// being killed, Save for Later adds nothing, there is only ever one
/// draft, and a backup carries the setup (its habit ids, goals, on / off
/// state and chosen order) and restores it as a setup that opens the hub
/// and starts nothing. All data is synthetic.

typedef Json = Map<String, dynamic>;

Json _json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Json;

Uint8List _mutate(Uint8List bytes, void Function(Json json) change) {
  final json = _json(bytes);
  change(json);
  final body = {...json}..remove('checksum');
  json['checksum'] = {
    'algorithm': 'sha256',
    'value': BackupCodec.checksumOf(body),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

/// A format-4 export as a v1.2 (format 3) writer would have produced it.
Uint8List _asFormat3(Uint8List v4) => _mutate(v4, (json) {
  json['formatVersion'] = 3;
  (json['data'] as Json).remove('feedback');
  for (final arc in (json['data'] as Json)['arcs'] as List) {
    (arc as Json)
      ..remove('closedOn')
      ..remove('freezes');
  }
});

/// What a setup is, as compared across a restart or a restore.
Future<List<Object?>> _setupState(TestApp app) async {
  final setup = await app.winterArc.setup();
  final s = setup.session;
  return [
    s.id,
    s.kind,
    s.status,
    s.startDate,
    s.endDate,
    s.participationStartDate,
    s.startedAt,
    for (final h in setup.habits)
      (
        h.id,
        h.title,
        h.type,
        h.unit,
        h.iconKey,
        h.target,
        h.minimumTarget,
        h.enabled,
        h.sortOrder,
        h.createdAt.toUtc(),
      ),
  ];
}

Future<void> _expectSetupOnly(TestApp app) async {
  final all = await snapshotAll(app.db);
  for (final table in [
    'daily_habit_progress_entries',
    'day_modes',
    'xp_transactions',
    'achievement_unlocks',
    'daily_reflections',
    'habit_revisions',
  ]) {
    expect(all[table], isEmpty, reason: table);
  }
  final sessions = await app.sessions.listSessions();
  expect(
    sessions.where((s) => s.status == WinterArcStatus.setup),
    hasLength(1),
    reason: 'one draft',
  );
  expect(sessions.where((s) => s.status == WinterArcStatus.active), isEmpty);
}

const _pages = HabitDraft(
  title: 'Pages Before Bed, A Long Wrapping Name',
  type: HabitType.count,
  iconKey: 'reading',
  target: 30,
  minimumTarget: 10,
  unit: 'pages',
);

void main() {
  group('process death after each committed change (S1)', () {
    late Directory dir;
    late File file;
    final clock = FakeClock(DateTime(2026, 11, 2, 9));

    TestApp launch() => TestApp(AppDatabase(NativeDatabase(file)), clock);

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      dir = Directory.systemTemp.createTempSync('nextrep_12d_');
      file = File('${dir.path}/nextrep.sqlite');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('toggle, add a template, add a custom habit, edit, remove, reorder, '
        'Save for Later: each survives a relaunch', () async {
      var app = launch();
      await app.winterArc.beginSetup();
      Habit? custom;
      final steps = <String, Future<void> Function(TestApp)>{
        'toggle': (a) => a.winterArc.setHabitEnabled('water', enabled: false),
        'add template': (a) => a.winterArc.addTemplateHabit('reading'),
        'add custom': (a) async =>
            custom = await a.winterArc.addCustomHabit(_pages),
        'edit': (a) => a.winterArc.editSetupHabit(
          custom!.id,
          const HabitDraft(
            title: 'Pages',
            type: HabitType.count,
            iconKey: 'reading',
            target: 25,
            minimumTarget: 5,
            unit: 'pages',
          ),
        ),
        'remove': (a) => a.winterArc.deleteSetupHabit('english'),
        'reorder': (a) async => a.winterArc.reorderSetupHabits(
          [for (final h in await a.winterArc.setupHabits()) h.id].reversed
              .toList(),
        ),
        // Save for Later is navigation only: it has no write of its own.
        'save for later': (_) async {},
      };
      for (final MapEntry(key: step, value: change) in steps.entries) {
        await change(app);
        final expected = await _setupState(app);
        final rows = await snapshotAll(app.db);
        // Killed here: nothing is flushed on the way out.
        await app.db.close();
        app = launch();
        expect(await _setupState(app), expected, reason: step);
        expect(await snapshotAll(app.db), rows, reason: step);
        expect(
          AppRoutes.forSession(await app.winterArc.currentSession()),
          AppRoutes.savedSetup,
          reason: 'a setup reopens in the hub ($step)',
        );
        await _expectSetupOnly(app);
      }
      final habits = (await app.winterArc.setup()).habits;
      expect(habits.firstWhere((h) => h.id == custom!.id).target, 25);
      expect(habits.firstWhere((h) => h.id == 'water').enabled, isFalse);
      expect(habits.any((h) => h.id == 'english'), isFalse);
      expect([
        for (final (i, h) in habits.indexed) h.sortOrder == i,
      ], everyElement(isTrue));
      await app.db.close();
    });

    test('an empty setup and an all-off setup are saved and reopened as they '
        'were', () async {
      var app = launch();
      await app.winterArc.beginSetup();
      for (final h in await app.winterArc.setupHabits()) {
        await app.winterArc.setHabitEnabled(h.id, enabled: false);
      }
      var expected = await _setupState(app);
      await app.db.close();
      app = launch();
      expect(await _setupState(app), expected);
      expect((await app.winterArc.setup()).blocker, SetupBlocker.noneEnabled);
      for (final h in await app.winterArc.setupHabits()) {
        await app.winterArc.deleteSetupHabit(h.id);
      }
      expected = await _setupState(app);
      await app.db.close();
      app = launch();
      expect(await _setupState(app), expected);
      final empty = await app.winterArc.setup();
      expect(empty.habits, isEmpty, reason: 'no starter habits come back');
      expect(empty.blocker, SetupBlocker.noHabits);
      await app.db.close();
    });
  });

  group('one draft beside any history', () {
    late TestApp app;
    setUp(
      () => app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1))),
    );
    tearDown(() => app.db.close());

    test('two completed arcs and a draft: the hub is home, history is '
        'untouched, and no second draft can exist', () async {
      final first = await runFirstArc(app);
      await app.winterArc.startNewArc(NewArcBaseline.fresh);
      final second = await app.winterArc.startWinterArc();
      app.clock.current = DateTime(
        2026,
        10,
        1,
      ).add(const Duration(days: 93, hours: 9));
      await app.lifecycle.reconcile();
      final draft = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final history = [
        await snapshotOf(app.db, first.id),
        await snapshotOf(app.db, second.id),
      ];
      expect(
        AppRoutes.home(await app.lifecycle.resolve()),
        AppRoutes.savedSetup,
      );
      await app.winterArc.reorderSetupHabits(
        [for (final h in await app.winterArc.setupHabits()) h.id].reversed
            .toList(),
      );
      await expectLater(
        app.winterArc.startNewArc(NewArcBaseline.fresh),
        throwsA(anything),
      );
      expect(
        await app.winterArc.beginSetup(),
        isA<WinterArcSession>().having((s) => s.id, 'id', draft.id),
        reason: 'beginSetup returns the one draft',
      );
      expect(
        (await app.sessions.listSessions()).where(
          (s) => s.status == WinterArcStatus.setup,
        ),
        hasLength(1),
      );
      expect([
        await snapshotOf(app.db, first.id),
        await snapshotOf(app.db, second.id),
      ], history);
    });
  });

  group('Reuse last setup keeps the chosen order (O2; Restart, 12F, will '
      'copy the same way)', () {
    late TestApp app;
    setUp(
      () => app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1, 9))),
    );
    tearDown(() => app.db.close());

    test('reordered in setup, started, completed, reused', () async {
      await app.winterArc.beginSetup();
      await app.winterArc.addCustomHabit(_pages);
      await app.winterArc.setHabitEnabled('learning', enabled: false);
      final order = [for (final h in await app.winterArc.setupHabits()) h.id]
          .reversed
          .toList();
      await app.winterArc.reorderSetupHabits(order);
      final arc = await app.winterArc.startWinterArc(
        confirmedOn: app.clock.today(),
      );
      expect([
        for (final h in await app.habits.habitsForSession(arc.id)) h.id,
      ], order);
      app.clock.current = DateTime(2026, 10, 1, 9);
      await app.lifecycle.reconcile();
      final next = await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
      final reused = await app.habits.habitsForSession(next.id);
      expect([for (final h in reused) h.id], order);
      expect(reused.firstWhere((h) => h.id == 'learning').enabled, isFalse);
      // And the new setup can be reordered again.
      await app.winterArc.reorderSetupHabits(order.reversed.toList());
      expect([
        for (final h in await app.habits.habitsForSession(next.id)) h.id,
      ], order.reversed.toList());
    });
  });

  group('backup (S7): format 4 out, formats 1–4 in', () {
    TestApp fresh(DateTime now) {
      final app = TestApp(
        memoryDatabase(),
        FakeClock(now),
        scheduler: FakeReminderScheduler(granted: true),
      );
      addTearDown(app.db.close);
      return app;
    }

    /// 12 habits: edited custom goals, three off, in a chosen order.
    Future<TestApp> twelve() async {
      final app = fresh(DateTime(2026, 11, 2, 9));
      await app.winterArc.beginSetup();
      await app.winterArc.addCustomHabit(_pages);
      for (final id in ['reading', 'mobility', 'fruit', 'journal']) {
        await app.winterArc.addTemplateHabit(id);
      }
      final habits = await app.winterArc.setupHabits();
      expect(habits, hasLength(12));
      final custom = habits.firstWhere((h) => h.id.startsWith('custom_'));
      await app.winterArc.editSetupHabit(
        custom.id,
        const HabitDraft(
          title: 'Pages',
          type: HabitType.count,
          iconKey: 'reading',
          target: 40,
          minimumTarget: 12,
          unit: 'pages',
        ),
      );
      for (final id in ['water', 'reading', custom.id]) {
        await app.winterArc.setHabitEnabled(id, enabled: false);
      }
      final ids = [for (final h in habits) h.id];
      await app.winterArc.reorderSetupHabits([
        ...ids.skip(6),
        ...ids.take(6).toList().reversed,
      ]);
      await app.reminders.update(
        (p) => p.copyWith(
          dailyEnabled: true,
          dailyTime: const ReminderTime(7, 15),
        ),
      );
      return app;
    }

    Future<TestApp> restored(Uint8List bytes) async {
      final target = fresh(DateTime(2026, 11, 3, 9));
      await target.backup.restore(await target.backup.inspect(bytes));
      return target;
    }

    test('12 reordered habits round-trip exactly; the restore opens the hub '
        'and starts nothing', () async {
      final source = await twelve();
      final expected = await _setupState(source);
      final bytes = (await source.backup.export()).bytes;
      expect(_json(bytes)['formatVersion'], BackupFormat.formatVersion);
      expect(BackupFormat.formatVersion, 4);

      final target = await restored(bytes);
      expect(await _setupState(target), expected);
      expect(
        AppRoutes.home(await target.lifecycle.resolve()),
        AppRoutes.savedSetup,
      );
      await _expectSetupOnly(target);
      expect(target.scheduler.pending, isEmpty, reason: 'nothing scheduled');
      // A second round trip changes nothing either.
      final again = (await target.backup.export()).bytes;
      final third = await restored(again);
      expect(await _setupState(third), expected);
    });

    test('a format-3 file of the same setup restores the same order', () async {
      final source = await twelve();
      final expected = await _setupState(source);
      final target = await restored(
        _asFormat3((await source.backup.export()).bytes),
      );
      expect(await _setupState(target), expected);
    });

    test(
      'a saved Seasonal setup round-trips as Seasonal, in its season',
      () async {
        final source = fresh(DateTime(2026, 9, 12, 9));
        await source.winterArc.beginSetup(kind: ArcKind.seasonalWinter);
        await source.winterArc.reorderSetupHabits(
          [for (final h in await source.winterArc.setupHabits()) h.id].reversed
              .toList(),
        );
        final expected = await _setupState(source);
        final target = await restored((await source.backup.export()).bytes);
        expect(await _setupState(target), expected);
        final setup = await target.winterArc.setup();
        expect(setup.session.kind, ArcKind.seasonalWinter);
        await _expectSetupOnly(target);
      },
    );

    test('a zero-habit setup round-trips with zero habits', () async {
      final source = fresh(DateTime(2026, 11, 2, 9));
      await source.winterArc.beginSetup();
      for (final h in await source.winterArc.setupHabits()) {
        await source.winterArc.deleteSetupHabit(h.id);
      }
      final target = await restored((await source.backup.export()).bytes);
      final setup = await target.winterArc.setup();
      expect(setup.habits, isEmpty);
      expect(setup.canStart, isFalse);
      expect(
        AppRoutes.home(await target.lifecycle.resolve()),
        AppRoutes.savedSetup,
      );
    });

    for (final (name, path, format) in [
      ('format 1 (v1.0)', 'test/fixtures/phase5_backup_v1.nextrep', 1),
      ('format 2 (v1.1)', 'test/fixtures/v1_1_backup_v2.nextrep', 2),
    ]) {
      test(
        '$name: a stored order other than 0..n−1 is kept as stored',
        () async {
          // The genuine file, with its arcs' habits in reverse order.
          final bytes = _mutate(File(path).readAsBytesSync(), (json) {
            expect(json['formatVersion'], format);
            for (final arc in (json['data'] as Json)['arcs'] as List) {
              final habits = (arc as Json)['habits'] as List;
              for (final (i, h) in habits.indexed) {
                (h as Json)['sortOrder'] = 10 * (habits.length - i);
              }
            }
          });
          final source = _json(bytes);
          final target = await restored(bytes);
          for (final arc in (source['data'] as Json)['arcs'] as List) {
            final habits = (arc as Json)['habits'] as List;
            final sessions = await target.sessions.listSessions();
            final session = sessions.firstWhere(
              (s) => s.status.name == arc['status'],
            );
            expect(
              [
                for (final h in await target.habits.habitsForSession(
                  session.id,
                ))
                  h.id,
              ],
              [for (final h in habits.reversed) (h as Json)['id']],
            );
          }
        },
      );
    }
  });
}
