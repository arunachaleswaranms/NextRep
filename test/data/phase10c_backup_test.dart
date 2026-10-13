import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/backup/backup_document.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/seasonal_backup.dart';

/// Phase 10C keeps schema v5 and backup format 2: new template ids and new
/// achievement ids are ordinary values of the existing format.

Uint8List _v1Fixture() =>
    File('test/fixtures/phase5_backup_v1.nextrep').readAsBytesSync();

TestApp _empty(DateTime now) {
  final app = TestApp(
    memoryDatabase(),
    FakeClock(now),
    scheduler: FakeReminderScheduler(granted: true),
  );
  addTearDown(app.db.close);
  return app;
}

Future<void> _restoreInto(TestApp target, Uint8List bytes) async =>
    target.backup.restore(await target.backup.inspect(bytes));

Map<String, dynamic> _json(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  test('v1.1 data still reads on schema v6 and backup format 3', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 6);
    expect(BackupFormat.formatVersion, 3);
    expect(BackupFormat.readableVersions, containsAll([1, 2]));
  });

  test('a v1.0-era format-1 backup restores, keeps its unlocks, and is then '
      'backfilled from its own history', () async {
    final target = _empty(DateTime(2026, 10, 3, 10));
    await _restoreInto(target, _v1Fixture());
    final before = await target.db.select(target.db.achievementUnlocks).get();
    expect(before, isNotEmpty);

    final backfill = await target.achievements.backfillCatalog();
    final after = await target.db.select(target.db.achievementUnlocks).get();
    for (final row in before) {
      expect(after, contains(row), reason: row.achievementKey);
    }
    final added = [
      ...backfill.celebratable.unlocked,
      for (final list in backfill.historical.values) ...list,
    ];
    expect(after, hasLength(before.length + added.length));
    expect((await target.achievements.backfillCatalog()).isEmpty, isTrue);
  });

  test('a format-2 backup restores and needs no further backfill', () async {
    final source = await seasonalSource();
    addTearDown(source.db.close);
    await source.achievements.backfillCatalog();
    final target = _empty(source.clock.now());
    await _restoreInto(target, (await source.backup.export()).bytes);
    final before = await dumpOf(source.db);
    final after = await dumpOf(target.db);
    expect(after['achievements'], before['achievements']);
    expect((await target.achievements.backfillCatalog()).isEmpty, isTrue);
  });

  group('an arc with new templates and new unlocks', () {
    late TestApp source;
    late Uint8List bytes;

    setUp(() async {
      source = _empty(DateTime(2026, 10, 1, 9));
      await source.winterArc.beginSetup();
      await source.winterArc.addTemplateHabit('hair_care');
      await source.winterArc.addTemplateHabit('reading');
      final arc = await source.winterArc.startWinterArc();
      for (var day = 1; day <= 14; day++) {
        source.clock.current = DateTime(2026, 10, day, 9);
        await completeHabit(source, 'no_junk_food');
        await completeHabit(source, 'hair_care');
        await source.achievements.reconcile();
      }
      // A key from some newer version.
      await source.db
          .into(source.db.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              sessionId: arc.id,
              achievementKey: 'from_the_future',
              unlockedOn: arc.startDate,
              unlockedAt: DateTime(2026, 10, 1, 9),
            ),
          );
      bytes = (await source.backup.export()).bytes;
    });

    test('exports the current format carrying the new ids', () {
      final json = _json(bytes);
      expect(json['formatVersion'], 3);
      final arc = ((json['data'] as Map)['arcs'] as List).single as Map;
      final habitIds = [for (final h in arc['habits'] as List) h['id']];
      expect(habitIds, containsAll(['hair_care', 'reading']));
      final keys = [for (final a in arc['achievements'] as List) a['key']];
      expect(
        keys,
        containsAll(['no_junk_7', 'streak_14', 'day_14', 'streak_7']),
      );
      // Existing rule: a key this version doesn't know isn't exported.
      expect(keys, isNot(contains('from_the_future')));
    });

    test('restores every row; the new ids round-trip', () async {
      final target = _empty(source.clock.now());
      await _restoreInto(target, bytes);
      final before = await dumpOf(source.db);
      final after = await dumpOf(target.db);
      for (final table in before.keys) {
        if (table == 'reminders') continue; // restored off, by design
        if (table == 'achievements') continue; // checked below
        expect(after[table], before[table], reason: table);
      }
      expect(after['achievements'], [
        for (final row in before['achievements']!)
          if (!row.contains('from_the_future')) row,
      ]);
      final unlocks = await target.achievementStore.unlocks(1);
      expect(
        unlocks.map((u) => u.key),
        containsAll([
          AchievementKey.noJunk7,
          AchievementKey.streak14,
          AchievementKey.day14,
        ]),
      );
      final today = await target.tracking.today();
      final hair = today.record.entryFor('hair_care')!;
      expect(hair.habit.title, 'Hair Care');
      expect(hair.habit.iconKey, 'hair_care');
      expect(today.record.entryFor('reading')!.target, 15);
      expect((await target.achievements.backfillCatalog()).isEmpty, isTrue);
    });
  });
}
