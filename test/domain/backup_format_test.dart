import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/backup/backup_document.dart';
import 'package:nextrep/domain/backup/backup_validator.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

typedef Json = Map<String, dynamic>;

/// Arc 1 completed (see [runFirstArc]) and Arc 2 running since 2 Oct with
/// a reflection, exported on 2 Oct 2026 at 21:00.
Future<Uint8List> _exported() async {
  final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
  addTearDown(app.db.close);
  await runFirstArc(app);
  await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
  app.clock.current = DateTime(2026, 10, 2, 20);
  final arc2 = await app.winterArc.startWinterArc();
  await completeAll(app);
  await app.reflections.save(
    sessionId: arc2.id,
    date: app.clock.today(),
    draft: const ReflectionDraft(
      mood: Mood.excellent,
      win: 'Private words',
      improvement: 'Sleep earlier',
    ),
  );
  await app.achievements.reconcile();
  app.clock.current = DateTime(2026, 10, 2, 21);
  return (await app.backup.export()).bytes;
}

Json _json(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Json;

/// Re-encodes [json] with a correct checksum, so a test reaches the rule
/// it is about rather than failing the checksum.
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

List<dynamic> _list(Json json, int arc, String key) =>
    _arc(json, arc)[key] as List;

ValidatedBackup _read(Uint8List bytes) =>
    BackupValidator.validate(BackupCodec.decode(bytes));

Matcher _rejectedAs(BackupProblem problem) =>
    throwsA(isA<BackupFailure>().having((f) => f.problem, 'problem', problem));

void main() {
  group('encoding', () {
    test('an empty dataset exports and reads back', () {
      final bytes = BackupCodec.encode(
        BackupDocument(
          exportedAt: DateTime.utc(2026, 10, 4, 9),
          appVersion: '1.0.0',
          data: BackupData.empty,
        ),
      );
      final backup = _read(bytes);
      expect(backup.summary.isEmpty, isTrue);
      expect(backup.data.reminders, isNull);
      expect(
        backup.document.exportedAt.isAtSameMomentAs(
          DateTime.utc(2026, 10, 4, 9),
        ),
        isTrue,
      );
      expect(backup.document.exportedAt.isUtc, isFalse, reason: 'local time');
      expect(_json(bytes)['product'], 'NextRep');
      expect(_json(bytes)['formatVersion'], 2);
    });

    test('encoding is deterministic and the checksum is SHA-256 of the '
        'canonical body', () async {
      final bytes = await _exported();
      final again = BackupCodec.encode(BackupCodec.decode(bytes));
      expect(again, bytes, reason: 'decode → encode reproduces every byte');

      final json = _json(bytes);
      final body = {...json}..remove('checksum');
      expect(
        (json['checksum'] as Json)['value'],
        sha256.convert(utf8.encode(BackupCodec.canonicalJson(body))).toString(),
      );
      // Canonical: sorted keys, no whitespace.
      final text = utf8.decode(bytes);
      expect(text.startsWith('{"appVersion":'), isTrue);
      expect(text.contains('\n'), isFalse);
    });

    test('canonical JSON sorts keys at every level and rejects doubles', () {
      expect(
        BackupCodec.canonicalJson({
          'b': [
            {'z': 1, 'a': null},
          ],
          'a': 'x',
        }),
        '{"a":"x","b":[{"a":null,"z":1}]}',
      );
      expect(() => BackupCodec.canonicalJson({'a': 1.5}), throwsArgumentError);
    });

    test(
      'the file uses domain names, not database tables or columns',
      () async {
        final text = utf8.decode(await _exported());
        for (final dbName in [
          'session_id',
          'winter_arc_sessions',
          'current_value',
          'xp_transactions',
          'daily_reflections',
          'icon_key',
        ]) {
          expect(text.contains(dbName), isFalse, reason: dbName);
        }
        final json = _json(await _exported());
        expect(_arc(json, 0).keys, containsAll(['habits', 'progress', 'xp']));
      },
    );

    test('a pretty-printed copy of a backup is still accepted', () async {
      final bytes = await _exported();
      final pretty = const JsonEncoder.withIndent('  ').convert(_json(bytes));
      expect(
        _read(Uint8List.fromList(utf8.encode(pretty))).summary.arcCount,
        2,
      );
    });

    test('the summary counts arcs, reflections and achievements', () async {
      final summary = _read(await _exported()).summary;
      expect(summary.arcCount, 2);
      expect(summary.completedArcs, 1);
      expect(summary.unfinishedArc?.id, 2);
      expect(summary.reflectionCount, 2);
      expect(summary.achievementCount, greaterThan(5));
    });
  });

  group('validation rejects', () {
    test('a wrong product identifier', () async {
      final bytes = _mutate(await _exported(), (j) => j['product'] = 'Other');
      expect(() => _read(bytes), _rejectedAs(BackupProblem.notNextRep));
      final missing = _mutate(await _exported(), (j) => j.remove('product'));
      expect(() => _read(missing), _rejectedAs(BackupProblem.notNextRep));
    });

    test(
      'an unsupported format version, before reading anything else',
      () async {
        for (final version in [3, 99, 0]) {
          final bytes = _mutate(await _exported(), (j) {
            j['formatVersion'] = version;
            j['data'] = {'futureLayout': true}; // never looked at
          });
          expect(
            () => _read(bytes),
            _rejectedAs(BackupProblem.unsupportedVersion),
          );
        }
        final text = _mutate(
          await _exported(),
          (j) => j['formatVersion'] = '1',
        );
        expect(() => _read(text), _rejectedAs(BackupProblem.invalidData));
      },
    );

    test('a checksum that does not match', () async {
      final json = _json(await _exported());
      _list(json, 1, 'progress').removeLast(); // edited, not re-signed
      final edited = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      expect(() => _read(edited), _rejectedAs(BackupProblem.checksumMismatch));

      final noChecksum = _json(await _exported())..remove('checksum');
      expect(
        () => _read(Uint8List.fromList(utf8.encode(jsonEncode(noChecksum)))),
        _rejectedAs(BackupProblem.checksumMismatch),
      );

      final bytes = await _exported();
      final flipped = Uint8List.fromList(bytes)
        ..[bytes.length ~/ 2] ^= 0x01; // one damaged byte
      expect(() => _read(flipped), throwsA(isA<BackupFailure>()));
    });

    test('malformed documents', () async {
      Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));
      expect(
        () => _read(text('not json')),
        _rejectedAs(BackupProblem.unreadable),
      );
      expect(
        () => _read(Uint8List.fromList([0xff, 0xfe, 0x00])),
        _rejectedAs(BackupProblem.unreadable),
      );
      expect(() => _read(text('[1,2]')), _rejectedAs(BackupProblem.unreadable));
      expect(() => _read(text('')), _rejectedAs(BackupProblem.unreadable));

      final bytes = await _exported();
      for (final change in <void Function(Json)>[
        (j) => _arc(j, 0).remove('habits'),
        (j) => _arc(j, 0)['surprise'] = 1,
        (j) => _arc(j, 0)['habits'] = 'none',
        (j) => (_list(j, 0, 'habits')[0] as Json)['target'] = '8',
        (j) => (_list(j, 0, 'progress')[0] as Json)['date'] = '01/07/2026',
        (j) => (_list(j, 0, 'progress')[0] as Json)['updatedAt'] = '2026-07-01',
        (j) => j['exportedAt'] = '2026-10-02T21:00:00', // not UTC
        (j) => (j['data'] as Json)['arcs'] = [1],
        (j) => _arc(j, 0)['status'] = 'paused',
      ]) {
        expect(
          () => _read(_mutate(bytes, change)),
          _rejectedAs(BackupProblem.invalidData),
        );
      }
    });

    test('an oversized document, before decoding it', () {
      final huge = Uint8List(BackupFormat.maxBytes + 1);
      expect(() => _read(huge), _rejectedAs(BackupProblem.tooLarge));
    });

    test('two unfinished arcs', () async {
      final bytes = _mutate(await _exported(), (j) {
        _arc(j, 0)['status'] = 'active';
      });
      expect(() => _read(bytes), _rejectedAs(BackupProblem.invalidData));
    });

    test(
      'orphan rows: progress, revisions and XP for an unknown habit',
      () async {
        final bytes = await _exported();
        for (final change in <void Function(Json)>[
          (j) => (_list(j, 0, 'progress')[0] as Json)['habitId'] = 'ghost',
          (j) =>
              (_list(j, 0, 'habitRevisions')[0] as Json)['habitId'] = 'ghost',
          (j) {
            final xp = _list(j, 0, 'xp').firstWhere(
              (x) => (x as Json)['reason'] == 'habitCompleted',
            ) as Json;
            xp['habitId'] = 'ghost';
            xp['sourceKey'] = 'habit_completed:ghost:${xp['date']}';
          },
          // A habit removed while its progress stays behind.
          (j) => _list(
            j,
            1,
            'habits',
          ).removeWhere((h) => (h as Json)['id'] == 'water'),
        ]) {
          expect(
            () => _read(_mutate(bytes, change)),
            _rejectedAs(BackupProblem.invalidData),
          );
        }
      },
    );

    test('a duplicate XP source key, or one that does not match', () async {
      final bytes = await _exported();
      final duplicate = _mutate(bytes, (j) {
        final xp = _list(j, 0, 'xp');
        xp.add({...xp.first as Json});
      });
      expect(() => _read(duplicate), _rejectedAs(BackupProblem.invalidData));
      final mismatch = _mutate(bytes, (j) {
        (_list(j, 0, 'xp').first as Json)['sourceKey'] = 'bonus:anything';
      });
      expect(() => _read(mismatch), _rejectedAs(BackupProblem.invalidData));
    });

    test('invalid targets', () async {
      final bytes = await _exported();
      Json habit(Json j, String id) =>
          _list(j, 0, 'habits').firstWhere((h) => (h as Json)['id'] == id)
              as Json;
      for (final change in <void Function(Json)>[
        (j) => habit(j, 'water')['target'] = 0,
        (j) => habit(j, 'water')['minimumTarget'] = 0,
        (j) => habit(j, 'water')['minimumTarget'] = 99, // above the target
        (j) => habit(j, 'water')['target'] = 51, // above the editing limit
        (j) => habit(j, 'no_junk_food')['target'] = 2, // binary
        (j) => (_list(j, 0, 'habitRevisions')[0] as Json)['target'] = -1,
        (j) => habit(j, 'water')['title'] = '   ',
        (j) =>
            habit(j, 'water')['sortOrder'] = habit(j, 'workout')['sortOrder'],
        (j) => _list(j, 0, 'habits').add({...habit(j, 'water')}),
      ]) {
        expect(
          () => _read(_mutate(bytes, change)),
          _rejectedAs(BackupProblem.invalidData),
        );
      }
    });

    test('invalid reflections', () async {
      final bytes = await _exported();
      Json reflection(Json j) => _list(j, 1, 'reflections').first as Json;
      for (final change in <void Function(Json)>[
        (j) => reflection(j)
          ..['mood'] = null
          ..['win'] = null
          ..['improvement'] = null,
        (j) => reflection(j)['win'] = 'x' * 241,
        (j) => reflection(j)['win'] = ' padded ',
        (j) => reflection(j)['mood'] = 'ecstatic',
        (j) => _list(j, 1, 'reflections').add({...reflection(j)}),
      ]) {
        expect(
          () => _read(_mutate(bytes, change)),
          _rejectedAs(BackupProblem.invalidData),
        );
      }
      // 240 emoji (grapheme clusters) is within the Journal's limit.
      final emoji = _mutate(bytes, (j) => reflection(j)['win'] = '❄️' * 240);
      expect(_read(emoji).summary.reflectionCount, 2);
    });

    test('an unknown achievement key, or a duplicate unlock', () async {
      final bytes = await _exported();
      final unknown = _mutate(bytes, (j) {
        (_list(j, 0, 'achievements').first as Json)['key'] = 'future_badge';
      });
      expect(() => _read(unknown), _rejectedAs(BackupProblem.invalidData));
      final duplicate = _mutate(bytes, (j) {
        final unlocks = _list(j, 0, 'achievements');
        unlocks.add({...unlocks.first as Json});
      });
      expect(() => _read(duplicate), _rejectedAs(BackupProblem.invalidData));
    });

    test('dates outside the arc, after the export, or impossible', () async {
      final bytes = await _exported();
      for (final change in <void Function(Json)>[
        // Before Day 1 / after Day 92 of Arc 1.
        (j) => (_list(j, 0, 'progress')[0] as Json)['date'] = '2026-06-30',
        (j) => (_list(j, 0, 'dayModes')[0] as Json)['date'] = '2026-10-01',
        (j) => (_list(j, 0, 'reflections')[0] as Json)['date'] = '2026-12-01',
        (j) =>
            (_list(j, 0, 'achievements')[0] as Json)['earnedOn'] = '2025-01-01',
        // Inside Arc 2, but days after the export on 2 Oct.
        (j) => (_list(j, 1, 'progress')[0] as Json)['date'] = '2026-10-20',
        (j) => (_list(j, 1, 'reflections')[0] as Json)['date'] = '2026-10-20',
        // An arc that starts after the export, or "completed" early.
        (j) => _arc(j, 1)
          ..['startDate'] = '2026-11-01'
          ..['endDate'] = '2027-01-31',
        (j) => _arc(j, 1)['status'] = 'completed',
        // Not a 92-day arc; not a calendar date.
        (j) => _arc(j, 0)['endDate'] = '2026-10-31',
        (j) => (_list(j, 0, 'progress')[0] as Json)['date'] = '2026-02-30',
        // A duplicate arc id.
        (j) => _arc(j, 1)['id'] = _arc(j, 0)['id'],
      ]) {
        expect(
          () => _read(_mutate(bytes, change)),
          _rejectedAs(BackupProblem.invalidData),
        );
      }
    });

    test('history on an arc still in setup', () async {
      final bytes = _mutate(await _exported(), (j) {
        _arc(j, 1)
          ..['status'] = 'setup'
          ..['startedAt'] = null;
      });
      expect(() => _read(bytes), _rejectedAs(BackupProblem.invalidData));
    });
  });

  test('a reflection at the Journal limit in multi-unit characters exports '
      'and restores', () async {
    final bytes = _mutate(await _exported(), (j) {
      // A family emoji with skin tones: one character, 15 UTF-16 units.
      (_list(j, 1, 'reflections').first as Json)['win'] =
          '👨🏽‍👩🏽‍👧🏽' * ReflectionRules.maxTextLength;
    });
    expect(_read(bytes).summary.reflectionCount, 2);
  });

  test('a deeply nested file is rejected cleanly', () {
    final deep = '${'[' * 100000}${']' * 100000}';
    final json =
        '{"product":"NextRep","formatVersion":1,"data":$deep,'
        '"checksum":{"algorithm":"sha256","value":"x"}}';
    expect(
      () => _read(Uint8List.fromList(utf8.encode(json))),
      throwsA(isA<BackupFailure>()),
    );
  });

  test('a rejection never quotes the file: no reflection text or habit '
      'names in the failure', () async {
    final bytes = await _exported();
    final failures = <BackupFailure>[];
    for (final change in <void Function(Json)>[
      (j) =>
          (_list(j, 1, 'reflections').first as Json)['win'] = ' Private words ',
      (j) => (_list(j, 0, 'habits').first as Json)['title'] = '   Strength',
      (j) =>
          (_list(j, 1, 'reflections').first as Json)['mood'] = 'Private words',
      (j) => (_list(j, 1, 'reflections').first as Json)['Private words'] = 1,
    ]) {
      try {
        _read(_mutate(bytes, change));
      } on BackupFailure catch (f) {
        failures.add(f);
      }
    }
    final notJson = Uint8List.fromList(utf8.encode('{"win": "Private words'));
    try {
      _read(notJson);
    } on BackupFailure catch (f) {
      failures.add(f);
    }
    expect(failures, hasLength(5));
    for (final f in failures) {
      expect(f.toString(), isNot(contains('Private')));
      expect(f.toString(), isNot(contains('Strength')));
    }
  });
}
