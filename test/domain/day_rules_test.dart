import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/domain/progress/day_rules.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/builders.dart';

final _now = DateTime(2026, 10, 1, 20);
final _water = habit('water', target: 8, minimum: 3, sortOrder: 0);
final _junk = habit('junk', binary: true, sortOrder: 1);

DayContext _day({
  DayMode mode = DayMode.normal,
  List<HabitRevision> revisions = const [],
  Map<String, int> values = const {},
  Iterable<String> ledgerKeys = const [],
}) => DayContext(
  date: day1,
  habits: HabitHistory(habits: [_water, _junk], revisions: revisions),
  mode: mode,
  progress: [
    for (final MapEntry(:key, :value) in values.entries)
      progress(
        key,
        day1,
        value,
        completed: value >= (key == 'water' ? (mode.isMinimum ? 3 : 8) : 1),
      ),
  ],
  ledger: [for (final key in ledgerKeys) _entryFor(key)],
);

XpLedgerEntry _entryFor(String key) => key.startsWith('perfect_day')
    ? XpLedgerEntry(
        sourceKey: key,
        reason: XpReason.perfectDay,
        amount: XpRules.perfectDayBonus,
      )
    : XpLedgerEntry(
        sourceKey: key,
        reason: XpReason.habitCompleted,
        amount: XpRules.habitCompletion,
      );

final _waterKey = XpRules.habitCompletionKey('water', day1);
final _junkKey = XpRules.habitCompletionKey('junk', day1);
final _perfectKey = XpRules.perfectDayKey(day1);

Set<String> _keys(Iterable<XpAward> awards) => {
  for (final a in awards) a.sourceKey,
};

void main() {
  group('Perfect Day', () {
    test('all enabled habits complete on a normal day is perfect', () {
      final s = DayRules.settle(
        _day(values: {'water': 7}, ledgerKeys: [_waterKey]),
        DayChange(progress: [progress('water', day1, 8)]),
        now: _now,
      );
      expect(s.record.isPerfect, isFalse); // junk still open
      final done = DayRules.settle(
        _day(values: {'water': 8, 'junk': 0}, ledgerKeys: [_waterKey]),
        DayChange(progress: [progress('junk', day1, 1)]),
        now: _now,
      );
      expect(done.record.isPerfect, isTrue);
      expect(_keys(done.ledger.granted), {_junkKey, _perfectKey});
      expect(done.ledger.perfectDayGranted, isTrue);
      final bonus = done.ledger.granted.firstWhere(
        (a) => a.sourceKey == _perfectKey,
      );
      expect(bonus.amount, XpRules.perfectDayBonus);
      expect(bonus.reason, XpReason.perfectDay);
    });

    test('one incomplete habit is not perfect and earns no bonus', () {
      final s = DayRules.settle(
        _day(),
        DayChange(progress: [progress('junk', day1, 1)]),
        now: _now,
      );
      expect(s.record.isPerfect, isFalse);
      expect(_keys(s.ledger.granted), {_junkKey});
    });

    test('a Minimum Day is never perfect, even fully complete', () {
      final s = DayRules.settle(
        _day(mode: DayMode.minimum, values: {'water': 3}),
        DayChange(progress: [progress('junk', day1, 1)]),
        now: _now,
      );
      expect(s.record.isMinimumComplete, isTrue);
      expect(s.record.isPerfect, isFalse);
      expect(s.ledger.perfectDayGranted, isFalse);
    });

    test('undoing a habit on a perfect day revokes the bonus', () {
      final s = DayRules.settle(
        _day(
          values: {'water': 8, 'junk': 1},
          ledgerKeys: [_waterKey, _junkKey, _perfectKey],
        ),
        DayChange(progress: [progress('junk', day1, 0)]),
        now: _now,
      );
      expect(s.ledger.granted, isEmpty);
      expect(s.ledger.revoked.map((x) => x.sourceKey).toSet(), {
        _junkKey,
        _perfectKey,
      });
      expect(s.ledger.perfectDayRevoked, isTrue);
    });

    test('a day with no enabled habits is not perfect', () {
      final s = DayRules.settle(
        _day(
          revisions: [
            revision('water', day1, target: 8, enabled: false),
            HabitRevision(
              habitId: 'junk',
              effectiveFrom: day1,
              config: const HabitConfig(
                target: 1,
                minimumTarget: 1,
                enabled: false,
              ),
              createdAt: _now,
            ),
          ],
        ),
        const DayChange(),
        now: _now,
      );
      expect(s.record.entries, isEmpty);
      expect(s.record.isPerfect, isFalse);
      expect(s.ledger.isEmpty, isTrue);
    });
  });

  group('idempotency', () {
    test('settling an unchanged day writes nothing', () {
      final s = DayRules.settle(
        _day(
          values: {'water': 8, 'junk': 1},
          ledgerKeys: [_waterKey, _junkKey, _perfectKey],
        ),
        const DayChange(),
        now: _now,
      );
      expect(s.hasWrites, isFalse);
    });

    test('a requested row identical to the stored one is not rewritten', () {
      final day = _day(values: {'junk': 1}, ledgerKeys: [_junkKey]);
      final s = DayRules.settle(
        day,
        DayChange(progress: [day.progress['junk']!]),
        now: _now,
      );
      expect(s.hasWrites, isFalse);
    });

    test('a missing award for stored completion is repaired', () {
      final s = DayRules.settle(
        _day(values: {'junk': 1}),
        const DayChange(),
        now: _now,
      );
      expect(_keys(s.ledger.granted), {_junkKey});
    });
  });

  group('Minimum Day reconciliation', () {
    test('switching keeps values and completes habits meeting the minimum', () {
      final s = DayRules.settle(
        _day(values: {'water': 4}),
        const DayChange(mode: DayMode.minimum),
        now: _now,
      );
      expect(s.mode, DayMode.minimum);
      final [water] = s.progress;
      expect(water.currentValue, 4); // never reduced
      expect(water.completed, isTrue);
      expect(water.completedAt, _now);
      expect(s.record.entryFor('water')!.target, 3);
      expect(_keys(s.ledger.granted), {_waterKey});
    });

    test('progress below the minimum stays incomplete', () {
      final s = DayRules.settle(
        _day(values: {'water': 2}),
        const DayChange(mode: DayMode.minimum),
        now: _now,
      );
      expect(s.progress, isEmpty);
      expect(s.ledger.isEmpty, isTrue);
    });
  });

  group('same-day habit edits', () {
    test('raising a target above progress un-completes and revokes XP', () {
      final s = DayRules.settle(
        _day(values: {'water': 8}, ledgerKeys: [_waterKey]),
        DayChange(revision: revision('water', day1, target: 10, minimum: 3)),
        now: _now,
      );
      final [water] = s.progress;
      expect(water.currentValue, 8);
      expect(water.completed, isFalse);
      expect(water.completedAt, isNull);
      expect(s.ledger.revoked.single.sourceKey, _waterKey);
    });

    test('lowering a target to meet progress completes and grants XP', () {
      final s = DayRules.settle(
        _day(values: {'water': 6}),
        DayChange(revision: revision('water', day1, target: 6, minimum: 3)),
        now: _now,
      );
      expect(s.progress.single.completed, isTrue);
      expect(_keys(s.ledger.granted), {_waterKey});
    });

    test('disabling a habit removes its XP for the day, keeps progress', () {
      final s = DayRules.settle(
        _day(values: {'water': 8}, ledgerKeys: [_waterKey]),
        DayChange(revision: revision('water', day1, target: 8, enabled: false)),
        now: _now,
      );
      expect(s.progress, isEmpty); // progress row untouched
      expect(s.record.entryFor('water'), isNull);
      expect(s.ledger.revoked.single.sourceKey, _waterKey);
    });

    test('renaming changes nothing but the title', () {
      final s = DayRules.settle(
        _day(values: {'water': 8}, ledgerKeys: [_waterKey]),
        const DayChange(rename: HabitRename('water', 'Hydrate')),
        now: _now,
      );
      expect(s.rename!.title, 'Hydrate');
      expect(s.record.entryFor('water')!.habit.title, 'Hydrate');
      expect(s.progress, isEmpty);
      expect(s.ledger.isEmpty, isTrue);
    });
  });
}
