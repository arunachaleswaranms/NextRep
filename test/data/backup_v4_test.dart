import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/habit/habit_edit.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/seasonal_backup.dart';

typedef Json = Map<String, dynamic>;

/// Genuine older files: Phase 5's encoder (format 1) and v1.1's (format 2).
Uint8List _v1Fixture() =>
    File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync();
Uint8List _v2Fixture() =>
    File('test/fixtures/v1_1_backup_v2.nextrep').readAsBytesSync();

Json _json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Json;

/// [bytes] after [change], with a valid checksum again (so only the rule
/// under test can reject it).
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

Json _data(Json json) => json['data'] as Json;
Json _arc(Json json, int i) => (_data(json)['arcs'] as List)[i] as Json;

ValidatedBackup _read(Uint8List bytes) =>
    BackupValidator.validate(BackupCodec.decode(bytes));

Matcher _rejectedAs(BackupProblem problem, [String? detail]) => throwsA(
  isA<BackupFailure>()
      .having((f) => f.problem, 'problem', problem)
      .having((f) => f.message, 'message', contains(detail ?? '')),
);

/// What a v1.2 (format-3) writer produced for the same data: format 4
/// without its additions. (No genuine format-3 file is committed; formats 1
/// and 2 below are genuine.)
Uint8List _asFormat3(Uint8List v4) => _mutate(v4, (json) {
  json['formatVersion'] = 3;
  _data(json).remove('feedback');
  for (final arc in _data(json)['arcs'] as List) {
    (arc as Json)
      ..remove('closedOn')
      ..remove('freezes');
  }
});

/// Every row of every table, for "nothing changed" checks.
Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          row.data,
      ],
  };
}

// ---------------------------------------------------------------------
// What Phases 12E2 and 12F will store, written directly: nothing in the
// app creates a freeze or ends an arc in Phase 12E1.

/// Freeze on [app]'s today: an open interval from tomorrow.
Future<void> _freeze(TestApp app, int sessionId) => app.db
    .into(app.db.arcFreezes)
    .insert(
      ArcFreezesCompanion.insert(
        sessionId: sessionId,
        frozenFrom: app.clock.today().addDays(1),
        requestedAt: app.clock.now(),
      ),
    );

/// Resume today: closes the open interval and moves the end date later by
/// the paused dates, in one transaction.
Future<void> _resume(TestApp app, int sessionId) =>
    app.db.transaction(() async {
      final db = app.db;
      final open =
          await (db.select(db.arcFreezes)..where(
                (f) => f.sessionId.equals(sessionId) & f.resumedOn.isNull(),
              ))
              .getSingle();
      final today = app.clock.today();
      await (db.update(db.arcFreezes)..where(
            (f) =>
                f.sessionId.equals(sessionId) &
                f.frozenFrom.equals(open.frozenFrom.toIsoString()),
          ))
          .write(
            ArcFreezesCompanion(
              resumedOn: Value(today),
              resumedAt: Value(app.clock.now()),
            ),
          );
      final session = await (db.select(
        db.winterArcSessions,
      )..where((s) => s.id.equals(sessionId))).getSingle();
      await (db.update(
        db.winterArcSessions,
      )..where((s) => s.id.equals(sessionId))).write(
        WinterArcSessionsCompanion(
          endDate: Value(
            session.endDate.addDays(open.frozenFrom.daysUntil(today)),
          ),
        ),
      );
    });

/// A device with an ended arc and a paused arc, all synthetic:
///
/// * Arc 1 (rolling, from Wed 1 Jul 2026): Day 1 completed; paused 2–4
///   Jul; Day 2 (5 Jul) completed; on 6 Jul (Day 3) Water's goal raised
///   for 7 Jul, nothing logged; then ended with `closedOn` 5 Jul. Its
///   revision of 7 Jul is after `closedOn`.
/// * Arc 2 (rolling, from 6 Jul, reusing Arc 1's setup): Day 1 completed
///   with a reflection; paused 7–8 Jul; Day 2 (9 Jul) completed; paused 10
///   Jul; Day 3 (11 Jul) completed, Water's goal raised for 12 Jul, and a
///   freeze from 12 Jul (open).
/// * Sounds off, Warm Ember; daily reminder on; Focus Guard on.
///
/// Leaves the clock on 11 Jul 2026 at 21:00: the freeze is scheduled.
Future<TestApp> _lifecycleSource({bool withFeedback = true}) async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 7, 1, 8)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  void at(int day, int hour) =>
      app.clock.current = DateTime(2026, 7, day, hour);

  await app.winterArc.beginSetup();
  final first = await app.winterArc.startWinterArc();
  await completeAll(app);
  await app.achievements.sync();
  at(1, 20);
  await _freeze(app, first.id);
  at(5, 9);
  await _resume(app, first.id);
  await completeAll(app);
  at(6, 9);
  await app.tracking.editHabit(
    habitId: 'water',
    edit: const HabitEdit(target: 10, minimumTarget: 4),
    date: app.clock.today(),
  );
  final loaded = (await app.sessions.sessionById(first.id))!;
  await app.sessions.updateSession(
    loaded.copyWith(
      status: WinterArcStatus.ended,
      closedOn: LocalDate(2026, 7, 5),
    ),
  );

  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  final second = await app.winterArc.startWinterArc();
  await completeAll(app);
  await app.achievements.sync();
  await app.reflections.save(
    sessionId: second.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(mood: Mood.good, win: 'Synthetic win'),
  );
  at(6, 20);
  await _freeze(app, second.id);
  at(9, 9);
  await _resume(app, second.id);
  await completeAll(app);
  at(9, 20);
  await _freeze(app, second.id);
  at(11, 9);
  await _resume(app, second.id);
  await completeAll(app);
  await app.tracking.editHabit(
    habitId: 'water',
    edit: const HabitEdit(target: 12, minimumTarget: 4),
    date: app.clock.today(),
  );
  await _freeze(app, second.id);
  at(11, 21);

  if (withFeedback) {
    await DriftFeedbackPreferencesRepository(app.db).save(
      const FeedbackPreferences(
        soundsEnabled: false,
        soundTheme: SoundTheme.warmEmber,
      ),
      at: app.clock.now(),
    );
  }
  await app.reminders.update((p) => p.copyWith(dailyEnabled: true));
  await DriftFocusGuardSettingsRepository(app.db).save(
    FocusGuardSettings(
      enabled: true,
      dailyBudgetMinutes: 30,
      selectedPackages: const ['org.example.video'],
      lastNudgedOn: app.clock.today(),
    ),
    at: app.clock.now(),
  );
  return app;
}

/// A device with its own data, a feedback setting and everything on: what a
/// restore replaces.
Future<TestApp> _target({bool withFeedback = true}) async {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(DateTime(2026, 8, 1, 9)),
    scheduler: FakeReminderScheduler(granted: true),
  );
  await app.winterArc.beginSetup();
  await app.winterArc.startWinterArc();
  await completeAll(app);
  await app.reminders.update((p) => p.copyWith(dailyEnabled: true));
  if (withFeedback) {
    await DriftFeedbackPreferencesRepository(app.db).save(
      const FeedbackPreferences(
        soundsEnabled: true,
        soundTheme: SoundTheme.summitSpark,
      ),
      at: app.clock.now(),
    );
  }
  return app;
}

/// The arc tables of [db], each sorted canonically. The XP ledger's row id
/// is a local surrogate key (never exported), so it is left out.
Future<Map<String, List<String>>> _arcRows(AppDatabase db) async {
  final all = await _snapshot(db);
  List<String> canonical(String table) => [
    for (final row in all[table]!)
      jsonEncode(table == 'xp_transactions' ? ({...row}..remove('id')) : row),
  ]..sort();
  return {
    for (final table in [
      'winter_arc_sessions',
      'arc_freezes',
      'habits',
      'habit_revisions',
      'daily_habit_progress_entries',
      'day_modes',
      'xp_transactions',
      'achievement_unlocks',
      'daily_reflections',
    ])
      table: canonical(table),
  };
}

/// A format-4 export of plain v1.2-style data (no freeze, no ended arc, no
/// feedback row): its format-3 form is what v1.2.0 wrote.
late Uint8List _plainV4;

void main() {
  late TestApp source;
  late Uint8List scheduled; // exported on 11 Jul: the freeze is scheduled
  late Uint8List paused; // exported on 14 Jul: paused since 12 Jul

  setUpAll(() async {
    final plain = await seasonalSource();
    _plainV4 = (await plain.backup.export()).bytes;
    await plain.db.close();
    source = await _lifecycleSource();
    scheduled = (await source.backup.export()).bytes;
    source.clock.current = DateTime(2026, 7, 14, 9);
    paused = (await source.backup.export()).bytes;
  });
  tearDownAll(() => source.db.close());

  group('writing format 4', () {
    test('the app writes format 4 and reads 1, 2, 3 and 4', () {
      expect(BackupFormat.formatVersion, 4);
      expect(BackupFormat.readableVersions, {1, 2, 3, 4});
      final json = _json(paused);
      expect(json['formatVersion'], 4);
      expect(json['product'], 'NextRep');
      expect(
        BackupFormat.fileNameFor(LocalDate(2026, 7, 14)),
        'nextrep-backup-2026-07-14.nextrep',
      );
      expect(_data(json).keys.toSet(), {
        'arcs',
        'reminders',
        'focusGuard',
        'feedback',
      });
    });

    test('an ended arc: status, closedOn, its completed freeze and the '
        'revision waiting after closedOn', () {
      final arc = _arc(_json(paused), 0);
      expect(arc['status'], 'ended');
      expect(arc['closedOn'], '2026-07-05');
      expect(arc['endDate'], '2026-10-03', reason: 'start + 91 + 3 paused');
      expect(arc['freezes'], [
        {
          'frozenFrom': '2026-07-02',
          'resumedOn': '2026-07-05',
          'requestedAt': isA<String>(),
          'resumedAt': isA<String>(),
        },
      ]);
      expect(
        [for (final r in arc['habitRevisions'] as List) r['effectiveFrom']],
        ['2026-07-07'],
      );
    });

    test('a paused arc: several completed freezes and an open one, with a '
        'revision on a paused date', () {
      final arc = _arc(_json(paused), 1);
      expect(arc['status'], 'active');
      expect(arc['closedOn'], isNull);
      expect(
        [
          for (final f in arc['freezes'] as List)
            (f['frozenFrom'], f['resumedOn'], f['resumedAt'] == null),
        ],
        [
          ('2026-07-07', '2026-07-09', false),
          ('2026-07-10', '2026-07-11', false),
          ('2026-07-12', null, true),
        ],
      );
      expect(arc['endDate'], '2026-10-08', reason: 'start + 91 + 3 paused');
      expect(
        [for (final r in arc['habitRevisions'] as List) r['effectiveFrom']],
        ['2026-07-12'],
      );
    });

    test('a scheduled freeze starts the day after the export', () {
      final arc = _arc(_json(scheduled), 1);
      expect((arc['freezes'] as List).last['frozenFrom'], '2026-07-12');
      expect(_json(scheduled)['exportedAt'], startsWith('2026-07-11'));
    });

    test('sound settings are written as stored', () {
      expect(_data(_json(paused))['feedback'], {
        'soundsEnabled': false,
        'soundTheme': 'warmEmber',
      });
    });

    test(
      'an arc that was never paused has no freeze and no closedOn',
      () async {
        final app = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, 7, 1, 9)),
        );
        addTearDown(app.db.close);
        await app.winterArc.beginSetup();
        await app.winterArc.startWinterArc();
        final json = _json((await app.backup.export()).bytes);
        expect(_arc(json, 0)['freezes'], isEmpty);
        expect(_arc(json, 0)['closedOn'], isNull);
        expect(_data(json)['feedback'], isNull, reason: 'never changed');
      },
    );
  });

  group('restoring format 4', () {
    for (final (name, bytes) in [
      ('a scheduled freeze', () => scheduled),
      ('an open freeze', () => paused),
    ]) {
      test('$name: every row returns, as stored; settings off; sound as '
          'stored; nothing scheduled', () async {
        final target = await _target();
        addTearDown(target.db.close);
        final inspected = await target.backup.inspect(bytes());
        expect(inspected.summary.arcCount, 2);
        expect(inspected.summary.completedArcs, 0, reason: 'ended ≠ completed');
        expect(inspected.summary.unfinishedArc?.id, 2);
        await target.backup.restore(inspected);

        final fresh = TestApp(memoryDatabase(), target.clock);
        addTearDown(fresh.db.close);
        await fresh.backup.restore(await fresh.backup.inspect(bytes()));
        expect(
          await _arcRows(fresh.db),
          await _arcRows(source.db),
          reason: 'a fresh install keeps the ids: identical rows',
        );

        final arcs = await target.sessions.listSessions();
        final ended = arcs.firstWhere((s) => s.status == WinterArcStatus.ended);
        expect(ended.closedOn, LocalDate(2026, 7, 5));
        expect(ended.freezes, hasLength(1));
        final active = arcs.firstWhere(
          (s) => s.status == WinterArcStatus.active,
        );
        expect(active.freezes, hasLength(3));
        expect(active.hasOpenFreeze, isTrue);
        expect(WinterArcRules.problemWith(active), isNull);
        expect(WinterArcRules.problemWith(ended), isNull);

        expect(target.scheduler.pending, isEmpty);
        expect((await target.reminderStore.load()).anyEnabled, isFalse);
        final focusGuard = await DriftFocusGuardSettingsRepository(target.db)
            .load();
        expect(focusGuard.enabled, isFalse);
        expect(focusGuard.lastNudgedOn, isNull);
        expect(
          await DriftFeedbackPreferencesRepository(target.db).load(),
          const FeedbackPreferences(
            soundsEnabled: false,
            soundTheme: SoundTheme.warmEmber,
          ),
        );
      });
    }

    test(
      'round trip: an export of the restored data equals the original',
      () async {
        final target = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, 7, 14, 9)),
        );
        addTearDown(target.db.close);
        await target.backup.restore(await target.backup.inspect(paused));
        final again = (await target.backup.export()).bytes;
        final reminders = _data(_json(paused))['reminders'];
        expect(
          _data(_json(again))..remove('reminders'),
          _data(_json(paused))..remove('reminders'),
        );
        expect(
          _data(_json(again))['reminders'],
          reminders,
          reason: 'times kept (on/off is not part of a backup)',
        );
      },
    );

    test(
      'the restored paused arc is paused; its revision waits for resume',
      () async {
        final target = TestApp(
          memoryDatabase(),
          FakeClock(DateTime(2026, 7, 14, 9)),
        );
        addTearDown(target.db.close);
        await target.backup.restore(await target.backup.inspect(paused));
        final today = await target.tracking.today();
        expect(today.position, isA<ArcPaused>());
        expect(today.isTrackable, isFalse);
        final history = await target.tracking.history();
        expect(history.elapsedDates, [
          LocalDate(2026, 7, 6),
          LocalDate(2026, 7, 9),
          LocalDate(2026, 7, 11),
        ]);
        final water = history.records.habits.habit('water')!;
        expect(
          history.records.habits.configOn(water, LocalDate(2026, 7, 11)).target,
          10,
          reason: 'the lived day keeps its goal',
        );
        expect(
          history.records.habits.configOn(water, LocalDate(2026, 7, 30)).target,
          12,
          reason: 'applies from the first day after the pause',
        );
        final ended = await target.tracking.historyFor(
          (await target.sessions.latestCompletedSession())!.id,
        );
        expect(ended.elapsedDates, [
          LocalDate(2026, 7, 1),
          LocalDate(2026, 7, 5),
        ]);
      },
    );

    test(
      'sound settings absent (never changed) restore as the defaults',
      () async {
        final quiet = await _lifecycleSource(withFeedback: false);
        addTearDown(quiet.db.close);
        final bytes = (await quiet.backup.export()).bytes;
        expect(_data(_json(bytes))['feedback'], isNull);
        final target = await _target();
        addTearDown(target.db.close);
        await target.backup.restore(await target.backup.inspect(bytes));
        expect(await target.db.select(target.db.feedbackPrefs).get(), isEmpty);
        expect(
          await DriftFeedbackPreferencesRepository(target.db).load(),
          FeedbackPreferences.defaults,
        );
      },
    );

    test('inspecting and validating write nothing', () async {
      final target = await _target();
      addTearDown(target.db.close);
      final before = await _snapshot(target.db);
      for (final bytes in [paused, scheduled, _v1Fixture(), _v2Fixture()]) {
        await target.backup.inspect(bytes);
      }
      await expectLater(
        target.backup.inspect(_mutate(paused, (j) => j['formatVersion'] = 5)),
        throwsA(isA<BackupFailure>()),
      );
      expect(await _snapshot(target.db), before);
      expect(target.scheduler.pending, isNotEmpty, reason: 'untouched');
    });
  });

  group('older formats restore with no freeze, no closedOn, and keep the '
      'device\'s sound setting', () {
    for (final (name, bytes) in [
      ('format 1 (Phase 5)', _v1Fixture),
      ('format 2 (v1.1)', _v2Fixture),
      ('format 3 (v1.2)', () => _asFormat3(_plainV4)),
    ]) {
      test(name, () async {
        final target = await _target();
        addTearDown(target.db.close);
        final before = await target.db.select(target.db.feedbackPrefs).get();
        expect(before, hasLength(1));
        final backup = await target.backup.inspect(bytes());
        expect(backup.data.includesFeedback, isFalse);
        await target.backup.restore(backup);
        for (final s in await target.sessions.listSessions()) {
          expect(s.freezes, isEmpty);
          expect(s.closedOn, isNull);
          expect(s.status, isNot(WinterArcStatus.ended));
        }
        expect(await target.db.select(target.db.arcFreezes).get(), isEmpty);
        expect(await target.db.select(target.db.feedbackPrefs).get(), before);
      });
    }
  });

  group('rejected before anything is written', () {
    late TestApp target;
    late Map<String, List<Map<String, Object?>>> before;

    setUp(() async {
      target = await _target();
      before = await _snapshot(target.db);
    });
    tearDown(() async {
      expect(await _snapshot(target.db), before, reason: 'nothing written');
      await target.db.close();
    });

    Future<void> rejects(
      Uint8List bytes,
      BackupProblem problem, [
      String? detail,
    ]) async {
      await expectLater(
        () => target.backup.inspect(bytes),
        _rejectedAs(problem, detail),
      );
    }

    test('an unknown future format version', () async {
      for (final version in [5, 99]) {
        await rejects(
          _mutate(paused, (j) {
            j['formatVersion'] = version;
            j['data'] = {'futureLayout': true};
          }),
          BackupProblem.unsupportedVersion,
        );
      }
    });

    test('an unknown status, sound theme or field', () async {
      await rejects(
        _mutate(paused, (j) => _arc(j, 0)['status'] = 'paused'),
        BackupProblem.invalidData,
        'status: unknown value',
      );
      await rejects(
        _mutate(paused, (j) => _arc(j, 0)['status'] = 'Ended'),
        BackupProblem.invalidData,
        'unknown value',
      );
      for (final feedback in <Object?>[
        {'soundsEnabled': true, 'soundTheme': 'loudAlarm'},
        {'soundsEnabled': true, 'soundTheme': 'IceCrystal'},
        {'soundsEnabled': 'yes', 'soundTheme': 'iceCrystal'},
        {'soundsEnabled': true},
        {'soundsEnabled': true, 'soundTheme': 'iceCrystal', 'volume': 3},
        'iceCrystal',
      ]) {
        await rejects(
          _mutate(paused, (j) => _data(j)['feedback'] = feedback),
          BackupProblem.invalidData,
        );
      }
      await rejects(
        _mutate(paused, (j) {
          ((_arc(j, 1)['freezes'] as List).first as Json)['reason'] = 'ill';
        }),
        BackupProblem.invalidData,
        'unknown field',
      );
      await rejects(
        _mutate(paused, (j) => _arc(j, 1).remove('freezes')),
        BackupProblem.invalidData,
        'missing field',
      );
      await rejects(
        _mutate(paused, (j) => _data(j).remove('feedback')),
        BackupProblem.invalidData,
        'missing field',
      );
    });

    test('format-4 states are never read from an older format', () async {
      // A format-4 body relabelled 3: its new fields are unknown there.
      await rejects(
        _mutate(paused, (j) => j['formatVersion'] = 3),
        BackupProblem.invalidData,
        'unknown field',
      );
      // An ended arc can't be expressed in format 3 at all.
      await rejects(
        _mutate(_asFormat3(_plainV4), (j) => _arc(j, 0)['status'] = 'ended'),
        BackupProblem.invalidData,
        'status: unknown value',
      );
      for (final extra in ['closedOn', 'freezes']) {
        await rejects(
          _mutate(_asFormat3(_plainV4), (j) => _arc(j, 0)[extra] = null),
          BackupProblem.invalidData,
          'unknown field',
        );
      }
      await rejects(
        _mutate(_asFormat3(_plainV4), (j) => _data(j)['feedback'] = null),
        BackupProblem.invalidData,
        'unknown field',
      );
      // And a format-3 body is not silently read as format 4.
      await rejects(
        _mutate(_asFormat3(_plainV4), (j) => j['formatVersion'] = 4),
        BackupProblem.invalidData,
        'missing field',
      );
    });

    test('a corrupted checksum or a truncated file', () async {
      final json = _json(paused);
      (json['checksum'] as Json)['value'] = '0' * 64;
      await rejects(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
        BackupProblem.checksumMismatch,
      );
      await rejects(
        Uint8List.sublistView(paused, 0, paused.length ~/ 2),
        BackupProblem.unreadable,
      );
      final edited = jsonDecode(utf8.decode(paused)) as Json;
      _arc(edited, 0)['closedOn'] = '2026-07-01'; // checksum not updated
      await rejects(
        Uint8List.fromList(utf8.encode(jsonEncode(edited))),
        BackupProblem.checksumMismatch,
      );
    });

    test('duplicate arcs or freeze keys', () async {
      await rejects(
        _mutate(paused, (j) => _arc(j, 1)['id'] = _arc(j, 0)['id']),
        BackupProblem.invalidData,
        'duplicate arc id',
      );
      await rejects(
        _mutate(paused, (j) {
          final freezes = _arc(j, 1)['freezes'] as List;
          freezes.insert(1, {...freezes.first as Json});
        }),
        BackupProblem.invalidData,
        'pauses overlap',
      );
    });

    test('a reference to a habit the arc does not have', () async {
      await rejects(
        _mutate(paused, (j) {
          (((_arc(j, 1)['progress'] as List).first) as Json)['habitId'] =
              'not_a_habit';
        }),
        BackupProblem.invalidData,
        'unknown habit',
      );
    });

    test('a second unfinished arc', () async {
      await rejects(
        _mutate(paused, (j) {
          final ended = _arc(j, 0);
          ended['status'] = 'active';
          ended['closedOn'] = null;
        }),
        BackupProblem.invalidData,
      );
    });
  });

  group('format-4 validation rules', () {
    void rejected(String name, Uint8List Function() bytes, String detail) {
      test(name, () {
        expect(
          () => _read(bytes()),
          _rejectedAs(BackupProblem.invalidData, detail),
        );
      });
    }

    Uint8List withArc(
      int i,
      void Function(Json arc) change, {
      Uint8List? from,
    }) => _mutate(from ?? paused, (j) => change(_arc(j, i)));

    rejected(
      'ended without closedOn',
      () => withArc(0, (a) => a['closedOn'] = null),
      'an ended arc has a closing date',
    );
    rejected(
      'closedOn on an active arc',
      () => withArc(1, (a) => a['closedOn'] = '2026-07-06'),
      'only an ended arc has a closing date',
    );
    rejected(
      'closedOn on a completed arc',
      () => withArc(0, (a) => a['status'] = 'completed'),
      'only an ended arc has a closing date',
    );
    rejected(
      'closedOn on a paused date',
      () => withArc(0, (a) => a['closedOn'] = '2026-07-03'),
      'an ended arc closes on one of its challenge days',
    );
    rejected(
      'closedOn after the planned end',
      () => withArc(0, (a) => a['closedOn'] = '2026-10-04'),
      'an ended arc closes on one of its challenge days',
    );
    rejected(
      'closedOn after the export',
      () => withArc(0, (a) {
        // A later closing date, with the arc's own rows still valid.
        a['closedOn'] = '2026-07-20';
      }),
      'closedOn: after the export date',
    );
    rejected(
      'closedOn not a date',
      () => withArc(0, (a) => a['closedOn'] = '2026-13-01'),
      'closedOn: not a calendar date',
    );
    rejected(
      'an ended arc still paused',
      () => withArc(0, (a) {
        ((a['freezes'] as List).single as Json)
          ..['resumedOn'] = null
          ..['resumedAt'] = null;
        a['endDate'] = '2026-09-30';
      }),
      'only an active arc is paused',
    );
    rejected(
      'overlapping freezes',
      () => withArc(1, (a) {
        ((a['freezes'] as List)[1] as Json)['frozenFrom'] = '2026-07-08';
      }),
      'pauses overlap or are out of order',
    );
    rejected(
      'two open freezes',
      () => withArc(1, (a) {
        ((a['freezes'] as List)[1] as Json)
          ..['resumedOn'] = null
          ..['resumedAt'] = null;
      }),
      'only the last pause is open',
    );
    rejected(
      'a seasonal arc with a freeze',
      () => withArc(1, (a) => a['kind'] = 'seasonalWinter'),
      'a seasonal arc is not paused',
    );
    rejected(
      'an end date that ignores the paused dates',
      () => withArc(1, (a) => a['endDate'] = '2026-10-04'),
      'not a 92-day arc',
    );
    rejected(
      'activity on a paused date',
      () => withArc(1, (a) {
        ((a['progress'] as List).first as Json)['date'] = '2026-07-07';
      }),
      'date outside the arc',
    );
    rejected(
      'XP after closedOn',
      () => withArc(0, (a) {
        (a['xp'] as List).add({
          'sourceKey': 'perfect_day:2026-07-06',
          'reason': 'perfectDay',
          'amount': 30,
          'habitId': null,
          'date': '2026-07-06',
          'createdAt': '2026-07-06T18:00:00.000Z',
        });
      }),
      'date outside the arc',
    );
    rejected(
      'a freeze starting later than the day after the export',
      () => withArc(1, (a) {
        ((a['freezes'] as List).last as Json)['frozenFrom'] = '2026-07-17';
      }),
      'frozenFrom: after the export date',
    );
    rejected(
      'a resume after the export',
      () => withArc(0, (a) {
        ((a['freezes'] as List).single as Json)['resumedOn'] = '2026-07-20';
        a['endDate'] = '2026-10-18';
        a['closedOn'] = '2026-07-20';
      }),
      'after the export date',
    );
    rejected(
      'a revision before joining',
      () => withArc(1, (a) {
        ((a['habitRevisions'] as List).single as Json)['effectiveFrom'] =
            '2026-07-05';
      }),
      'effectiveFrom: date outside the arc',
    );

    test(
      'a revision on a paused date or after closedOn is accepted (F1-5)',
      () {
        final backup = _read(paused);
        final ended = backup.data.arcs[0];
        final active = backup.data.arcs[1];
        expect(ended.revisions.single.effectiveFrom, LocalDate(2026, 7, 7));
        expect(ended.session.isParticipatingOn(LocalDate(2026, 7, 7)), isFalse);
        expect(active.revisions.single.effectiveFrom, LocalDate(2026, 7, 12));
        expect(active.session.isFrozenOn(LocalDate(2026, 7, 12)), isTrue);
      },
    );
  });

  group('a failure inside the restore transaction', () {
    for (final table in ['arc_freezes', 'feedback_preferences']) {
      test('in $table: everything stays as it was; a retry succeeds', () async {
        final target = await _target();
        addTearDown(target.db.close);
        final before = await _snapshot(target.db);
        final pending = target.scheduler.pending;
        final backup = await target.backup.inspect(paused);
        await target.db.customStatement(
          'CREATE TEMP TRIGGER injected_failure BEFORE INSERT ON $table '
          "BEGIN SELECT RAISE(ABORT, 'injected'); END",
        );
        await expectLater(
          target.backup.restore(backup),
          throwsA(isA<PersistenceFailure>()),
        );
        expect(
          await _snapshot(target.db),
          before,
          reason: 'no partial session, freeze or feedback reset',
        );
        expect(target.scheduler.pending, pending);
        await target.db.customStatement('DROP TRIGGER injected_failure');
        await target.backup.restore(await target.backup.inspect(paused));
        expect(
          await target.db.select(target.db.arcFreezes).get(),
          hasLength(4),
        );
        expect(
          await target.db.select(target.db.feedbackPrefs).get(),
          hasLength(1),
        );
      });
    }
  });
}
