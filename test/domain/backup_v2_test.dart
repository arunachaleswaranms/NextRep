import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/seasonal_backup.dart';

typedef Json = Map<String, dynamic>;

/// A genuine format-1 file, written by the Phase 5 encoder (synthetic
/// data): a completed rolling arc and a running one.
Uint8List _v1Fixture() =>
    File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync();

Json _json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Json;

Uint8List _resign(Json json) {
  final body = {...json}..remove('checksum');
  json['checksum'] = {
    'algorithm': 'sha256',
    'value': BackupCodec.checksumOf(body),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

Uint8List _mutate(Uint8List bytes, void Function(Json json) change) {
  final json = _json(bytes);
  change(json);
  return _resign(json);
}

Json _arc(Json json, int index) =>
    ((json['data'] as Json)['arcs'] as List)[index] as Json;

ValidatedBackup _read(Uint8List bytes) =>
    BackupValidator.validate(BackupCodec.decode(bytes));

Matcher _rejectedAs(BackupProblem problem) =>
    throwsA(isA<BackupFailure>().having((f) => f.problem, 'problem', problem));

void main() {
  late Uint8List v2;

  setUpAll(() async {
    final app = await seasonalSource();
    v2 = (await app.backup.export()).bytes;
    await app.db.close();
  });

  group('format 2', () {
    test('exports formatVersion 2 with arc kinds and participation', () {
      final json = _json(v2);
      expect(json['formatVersion'], 2);
      expect(BackupFormat.formatVersion, 2);
      final rolling = _arc(json, 0);
      final seasonal = _arc(json, 1);
      expect(rolling['kind'], 'rolling92');
      expect(rolling['participationStartDate'], rolling['startDate']);
      expect(seasonal['kind'], 'seasonalWinter');
      expect(seasonal['startDate'], '2026-10-01');
      expect(seasonal['endDate'], '2026-12-31');
      expect(seasonal['participationStartDate'], '2026-10-15');
    });

    test('rolling and seasonal arcs round-trip', () {
      final arcs = _read(v2).data.arcs;
      final rolling = arcs[0].session;
      expect(rolling.kind, ArcKind.rolling92);
      expect(rolling.participationStartDate, rolling.startDate);
      final seasonal = arcs[1].session;
      expect(seasonal.kind, ArcKind.seasonalWinter);
      expect(seasonal.status, WinterArcStatus.active);
      expect(seasonal.participationStartDate, LocalDate(2026, 10, 15));
      expect(seasonal.joinDayNumber, 15);
    });

    test('custom and timeBefore habits and their progress round-trip', () {
      final arc = _read(v2).data.arcs[1];
      final pages = arc.habits.singleWhere((h) => h.id == pagesId);
      expect(
        (pages.type, pages.title, pages.unit),
        (HabitType.count, 'Pages', 'pages'),
      );
      final sleep = arc.habits.singleWhere((h) => h.id == 'sleep_before');
      expect(sleep.type, HabitType.timeBefore);
      expect(sleep.target, NightTime(1, 0).value);
      expect(sleep.minimumTarget, sleep.target);
      final revision = arc.revisions.single;
      expect(revision.config.target, NightTime(0, 30).value);
      expect(revision.effectiveFrom, LocalDate(2026, 10, 16));
      final logs = {
        for (final p in arc.progress)
          if (p.progress.habitId == 'sleep_before')
            p.progress.date.day: (
              p.progress.currentValue,
              p.progress.completed,
            ),
      };
      // 15 Oct met its own goal (01:00); 16 Oct missed the new one (00:30).
      expect(logs, {
        15: (NightTime(0, 45).value, true),
        16: (NightTime(0, 45).value, false),
      });
    });

    test('encoding is deterministic, checksum included', () {
      final again = BackupCodec.encode(BackupCodec.decode(v2));
      expect(again, v2);
      final body = _json(v2)..remove('checksum');
      expect(
        (_json(v2)['checksum'] as Json)['value'],
        BackupCodec.checksumOf(body),
      );
    });
  });

  group('format 1 compatibility', () {
    test('a genuine Phase 5 file still imports', () {
      final fixture = _v1Fixture();
      expect(_json(fixture)['formatVersion'], 1);
      final backup = _read(fixture);
      expect(backup.data.arcs, hasLength(2));
      expect(backup.summary.completedArcs, 1);
      expect(backup.summary.reflectionCount, 2);
      expect(backup.data.reminders, isNotNull);
    });

    test('every format-1 arc is rolling92, joined on its start date', () {
      final arcs = _read(_v1Fixture()).data.arcs;
      for (final arc in arcs) {
        expect(arc.session.kind, ArcKind.rolling92);
        expect(arc.session.participationStartDate, arc.session.startDate);
        expect(WinterArcRules.problemWith(arc.session), isNull);
      }
      // The legacy done / not-done sleep habit comes back as it was.
      final sleep = arcs[0].habits.singleWhere((h) => h.id == 'sleep_on_time');
      expect(sleep.type, HabitType.binary);
    });

    test('a format-1 arc in setup keeps no participation date', () {
      final setup = _mutate(_v1Fixture(), (json) {
        final arcs = (json['data'] as Json)['arcs'] as List;
        final active = arcs[1] as Json;
        active['status'] = 'setup';
        active['startedAt'] = null;
        for (final key in [
          'habitRevisions',
          'dayModes',
          'progress',
          'xp',
          'achievements',
          'reflections',
        ]) {
          active[key] = <Object?>[];
        }
      });
      final arc = _read(setup).data.arcs[1].session;
      expect(arc.status, WinterArcStatus.setup);
      expect(arc.kind, ArcKind.rolling92);
      expect(arc.participationStartDate, isNull);
    });

    test('the checksum is checked over the format-1 file as written', () {
      final fixture = _v1Fixture();
      final json = _json(fixture);
      final body = {...json}..remove('checksum');
      expect((json['checksum'] as Json)['value'], BackupCodec.checksumOf(body));
      // Adding format-2 fields (even with a fresh checksum) doesn't make a
      // format-1 file valid: it isn't silently read as format 2.
      final withKind = _mutate(fixture, (json) {
        _arc(json, 0)['kind'] = 'rolling92';
      });
      expect(() => _read(withKind), _rejectedAs(BackupProblem.invalidData));
      // And adding them without re-signing breaks the checksum.
      final unsigned = _json(fixture);
      _arc(unsigned, 0)['participationStartDate'] = '2026-07-01';
      expect(
        () => _read(Uint8List.fromList(utf8.encode(jsonEncode(unsigned)))),
        _rejectedAs(BackupProblem.checksumMismatch),
      );
      // A clock-time habit never existed in format 1.
      final timeBefore = _mutate(fixture, (json) {
        final habit = (_arc(json, 0)['habits'] as List).first as Json;
        habit['type'] = 'timeBefore';
      });
      expect(() => _read(timeBefore), _rejectedAs(BackupProblem.invalidData));
    });

    test('a format-2 file must carry the format-2 fields', () {
      final missing = _mutate(v2, (json) => _arc(json, 0).remove('kind'));
      expect(() => _read(missing), _rejectedAs(BackupProblem.invalidData));
    });

    test('a future version is rejected', () {
      for (final version in [3, 4, 100]) {
        final future = _mutate(v2, (json) => json['formatVersion'] = version);
        expect(
          () => _read(future),
          _rejectedAs(BackupProblem.unsupportedVersion),
        );
      }
    });
  });

  group('format 2 validation', () {
    void rejects(void Function(Json json) change, {String? reason}) => expect(
      () => _read(_mutate(v2, change)),
      _rejectedAs(BackupProblem.invalidData),
      reason: reason,
    );

    test('malformed structure', () {
      rejects((json) => _arc(json, 1)['kind'] = 'summerArc');
      rejects((json) => _arc(json, 1)['participationStartDate'] = '15/10/2026');
      rejects((json) => _arc(json, 1)['extra'] = true);
    });

    test('seasonal dates must be one season', () {
      rejects((json) => _arc(json, 1)['startDate'] = '2026-10-02');
      rejects((json) => _arc(json, 1)['endDate'] = '2027-12-31');
      rejects(
        (json) => _arc(json, 0)['kind'] = 'seasonalWinter',
        reason: 'a 1 Jul – 30 Sep arc is not a season',
      );
    });

    test('participation dates must fit the kind and status', () {
      rejects((json) => _arc(json, 1)['participationStartDate'] = '2026-09-30');
      rejects((json) => _arc(json, 1)['participationStartDate'] = null);
      rejects((json) => _arc(json, 0)['participationStartDate'] = '2026-07-02');
      rejects(
        (json) => _arc(json, 1)['participationStartDate'] = '2026-10-17',
        reason: 'joined after the history it has',
      );
    });

    test(
      'timeBefore targets must be night times, the same on Minimum Days',
      () {
        Json sleep(Json json) => (_arc(json, 1)['habits'] as List)
            .cast<Json>()
            .singleWhere((h) => h['id'] == 'sleep_before');
        rejects((json) => sleep(json)['target'] = 720);
        rejects((json) => sleep(json)['minimumTarget'] = 1080);
        rejects((json) {
          final revision =
              (_arc(json, 1)['habitRevisions'] as List).single as Json;
          revision['target'] = 600;
          revision['minimumTarget'] = 600;
        });
      },
    );

    test('timeBefore progress must be a night time that agrees with the '
        'target of its own date', () {
      Json log(Json json, String date) =>
          (_arc(json, 1)['progress'] as List).cast<Json>().singleWhere(
            (p) => p['habitId'] == 'sleep_before' && p['date'] == date,
          );
      rejects((json) => log(json, '2026-10-15')['value'] = 700);
      rejects((json) => log(json, '2026-10-15')['completed'] = false);
      rejects((json) {
        log(json, '2026-10-16')
          ..['completed'] = true
          ..['completedAt'] = '2026-10-16T06:00:00.000Z';
      }, reason: '00:45 misses that day\'s 00:30 goal');
    });
  });
}
