import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/habit/night_time.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/review_db.dart';

/// Phase 12D, addendum § L2 (R): `HabitRepository.reorderSetupHabits` on a
/// real in-memory Drift database. A valid order writes `sort_order =
/// 0..n−1` and nothing else; every invalid one, and a failure part-way
/// through, writes nothing at all. All data is synthetic.

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

/// Every table, with `habits.sort_order` blanked: what a reorder must
/// leave identical.
Future<DbSnapshot> _withoutOrder(AppDatabase db) async {
  final all = await snapshotAll(db);
  return {
    for (final MapEntry(:key, :value) in all.entries)
      key: key == 'habits'
          ? [
              for (final row in value) {...row, 'sort_order': null},
            ]
          : value,
  };
}

Future<List<(String, int)>> _orderOf(AppDatabase db, int sessionId) async {
  final rows =
      await (db.select(db.habits)
            ..where((h) => h.sessionId.equals(sessionId))
            ..orderBy([(h) => OrderingTerm.asc(h.sortOrder)]))
          .get();
  return [for (final r in rows) (r.id, r.sortOrder)];
}

/// Fails the update of [habitId]'s sort order, after any earlier rows of
/// the same transaction were written.
Future<void> _failUpdateOf(AppDatabase db, String habitId) =>
    db.customStatement(
      'CREATE TRIGGER fail_reorder BEFORE UPDATE OF sort_order ON habits '
      "WHEN NEW.id = '$habitId' BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );

int _ids = 0;

HabitDraft _custom(String title, {HabitType type = HabitType.count}) =>
    switch (type) {
      HabitType.timeBefore => HabitDraft(
        title: title,
        type: type,
        iconKey: 'sleep',
        target: NightTime(22, 30).value,
      ),
      HabitType.binary => HabitDraft(
        title: title,
        type: type,
        iconKey: 'star',
        target: 1,
      ),
      _ => HabitDraft(
        title: title,
        type: type,
        iconKey: 'star',
        target: 20,
        minimumTarget: 5,
        unit: type == HabitType.duration ? 'min' : 'pages',
      ),
    };

final class _Ids implements HabitIdGenerator {
  @override
  String next() => 'custom_${(++_ids).toRadixString(16).padLeft(32, '0')}';
}

void main() {
  late TestApp app;
  late WinterArcService service;

  setUp(() {
    app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 11, 2, 9)));
    service = WinterArcService(
      sessions: app.sessions,
      habits: app.habits,
      clock: app.clock,
      ids: _Ids(),
    );
  });
  tearDown(() => app.db.close());

  Future<int> setupWith(int count) async {
    final session = await service.beginSetup();
    final ids = [for (final h in await service.setupHabits()) h.id];
    // Trim or extend the seven starter habits to [count].
    for (final id in ids.skip(count)) {
      await service.deleteSetupHabit(id);
    }
    for (var i = ids.length; i < count; i++) {
      await service.addCustomHabit(_custom('Custom $i'));
    }
    expect(await service.setupHabits(), hasLength(count));
    return session.id;
  }

  Future<List<String>> idsOf(int sessionId) async => [
    for (final (id, _) in await _orderOf(app.db, sessionId)) id,
  ];

  /// Reorders to [order] and checks: the stored order is exactly [order]
  /// with `sort_order = 0..n−1`, and nothing else in the database changed.
  Future<void> expectReorder(int sessionId, List<String> order) async {
    final before = await _withoutOrder(app.db);
    await app.habits.reorderSetupHabits(sessionId, order);
    expect(await _orderOf(app.db, sessionId), [
      for (final (i, id) in order.indexed) (id, i),
    ]);
    expect(await _withoutOrder(app.db), before, reason: 'only sort_order');
  }

  /// [body] must throw [rule] and leave every row of every table as it
  /// was.
  Future<void> expectRefused(
    Future<void> Function() body,
    DomainRule rule,
  ) async {
    final before = await snapshotAll(app.db);
    await expectLater(body(), _failsWith(rule));
    expect(await snapshotAll(app.db), before, reason: 'nothing written');
  }

  group('valid orders write 0..n−1 and nothing else', () {
    for (final count in [0, 1, 2, 8, 12]) {
      test('$count habits: reversed, then back', () async {
        final id = await setupWith(count);
        final ids = await idsOf(id);
        await expectReorder(id, ids.reversed.toList());
        await expectReorder(id, ids);
      });
    }

    test('the same order is accepted and rewrites nothing', () async {
      final id = await setupWith(8);
      final before = await snapshotAll(app.db);
      await app.habits.reorderSetupHabits(id, await idsOf(id));
      expect(await snapshotAll(app.db), before);
    });

    test('adjacent, first to last, last to first', () async {
      final id = await setupWith(8);
      final ids = await idsOf(id);
      await expectReorder(id, [ids[1], ids[0], ...ids.skip(2)]);
      final now = await idsOf(id);
      await expectReorder(id, [...now.skip(1), now.first]);
      final again = await idsOf(id);
      await expectReorder(id, [again.last, ...again.take(again.length - 1)]);
    });

    test('disabled, custom and mixed-type habits move like any other; '
        'on / off, goals, ids and titles are kept', () async {
      final id = await setupWith(3);
      final time = await service.addCustomHabit(
        _custom('Lights Out', type: HabitType.timeBefore),
      );
      final binary = await service.addCustomHabit(
        _custom('Stretch', type: HabitType.binary),
      );
      final minutes = await service.addCustomHabit(
        _custom('Piano', type: HabitType.duration),
      );
      await service.setHabitEnabled('water', enabled: false);
      await service.setHabitEnabled(binary.id, enabled: false);
      final before = {for (final h in await service.setupHabits()) h.id: h};
      final order = [
        binary.id,
        'water',
        minutes.id,
        ...(await idsOf(id))
            .where((h) => h != binary.id && h != 'water' && h != minutes.id),
      ];
      await expectReorder(id, order);
      final after = await service.setupHabits();
      expect([for (final h in after) h.id], order);
      for (final (i, h) in after.indexed) {
        final old = before[h.id]!;
        expect(h.sortOrder, i);
        expect(
          (h.title, h.type, h.unit, h.iconKey, h.target, h.minimumTarget),
          (
            old.title,
            old.type,
            old.unit,
            old.iconKey,
            old.target,
            old.minimumTarget,
          ),
        );
        expect(h.enabled, old.enabled);
        expect(h.createdAt, old.createdAt);
      }
      expect(
        after.firstWhere((h) => h.id == time.id).type,
        HabitType.timeBefore,
      );
    });

    test('no revision, XP, progress or unlock is written', () async {
      final id = await setupWith(12);
      await expectReorder(id, (await idsOf(id)).reversed.toList());
      final all = await snapshotAll(app.db);
      for (final table in [
        'habit_revisions',
        'xp_transactions',
        'daily_habit_progress_entries',
        'achievement_unlocks',
        'day_modes',
      ]) {
        expect(all[table], isEmpty, reason: table);
      }
    });

    test('gaps left by a removal are closed by the next reorder', () async {
      final id = await setupWith(8);
      final ids = await idsOf(id);
      await service.deleteSetupHabit(ids[3]);
      expect(
        [for (final (_, o) in await _orderOf(app.db, id)) o],
        [
          0, 1, 2, 4, 5, 6, 7, //
        ],
      );
      final left = await idsOf(id);
      await expectReorder(id, left.reversed.toList());
      await expectReorder(id, left);
    });
  });

  group('an invalid order writes nothing', () {
    late int id;
    late List<String> ids;

    setUp(() async {
      id = await setupWith(8);
      ids = await idsOf(id);
    });

    test('a duplicate id', () async {
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, [ids[0], ...ids.take(7)]),
        DomainRule.invalidHabitOrder,
      );
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, [...ids, ids[0]]),
        DomainRule.invalidHabitOrder,
      );
    });

    test('a missing id', () async {
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, ids.skip(1).toList()),
        DomainRule.invalidHabitOrder,
      );
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, const []),
        DomainRule.invalidHabitOrder,
      );
    });

    test('an extra id', () async {
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, [...ids, 'reading']),
        DomainRule.invalidHabitOrder,
      );
    });

    test('a stale order naming a habit deleted meanwhile', () async {
      await service.deleteSetupHabit(ids[2]);
      await expectRefused(
        () => app.habits.reorderSetupHabits(id, ids.reversed.toList()),
        DomainRule.invalidHabitOrder,
      );
      await expectRefused(
        () => service.reorderSetupHabits(ids.reversed.toList()),
        DomainRule.invalidHabitOrder,
      );
    });

    test('a missing session', () async {
      await expectRefused(
        () => app.habits.reorderSetupHabits(id + 40, ids),
        DomainRule.sessionNotFound,
      );
    });
  });

  group('only an arc in setup can be reordered (O5)', () {
    test('an active arc', () async {
      await service.beginSetup();
      final arc = await service.startWinterArc();
      final ids = await idsOf(arc.id);
      await expectRefused(
        () => app.habits.reorderSetupHabits(arc.id, ids.reversed.toList()),
        DomainRule.sessionNotInSetup,
      );
      await expectRefused(
        () => service.reorderSetupHabits(ids.reversed.toList()),
        DomainRule.sessionNotInSetup,
      );
    });

    test('a completed arc, and an ended arc; the setup beside them is the '
        'only one that changes', () async {
      final done = await runFirstArc(app);
      final setupId = (await app.winterArc.startNewArc(
        NewArcBaseline.reuseLast,
      )).id;
      final doneIds = await idsOf(done.id);
      await expectRefused(
        () => app.habits.reorderSetupHabits(done.id, doneIds.reversed.toList()),
        DomainRule.sessionNotInSetup,
      );
      await (app.db.update(
        app.db.winterArcSessions,
      )..where((s) => s.id.equals(done.id))).write(
        WinterArcSessionsCompanion(
          status: const Value(WinterArcStatus.ended),
          closedOn: Value(done.endDate),
        ),
      );
      await expectRefused(
        () => app.habits.reorderSetupHabits(done.id, doneIds.reversed.toList()),
        DomainRule.sessionNotInSetup,
      );
      // A foreign (finished arc's) id can't be slipped into the setup.
      final setupIds = await idsOf(setupId);
      await expectRefused(
        () => app.habits.reorderSetupHabits(setupId, [
          ...setupIds.take(setupIds.length - 1),
          'reading',
        ]),
        DomainRule.invalidHabitOrder,
      );
      // The setup itself moves; the finished arc's rows don't.
      final finished = await snapshotOf(app.db, done.id);
      await expectReorder(setupId, setupIds.reversed.toList());
      expect(await snapshotOf(app.db, done.id), finished);
    });

    test("another session's custom habit id is refused", () async {
      // A finished arc with a custom habit the new setup doesn't have.
      await service.beginSetup();
      final custom = await service.addCustomHabit(_custom('Gone Later'));
      final first = await service.startWinterArc();
      app.clock.current = DateTime(2027, 2, 2, 9);
      await app.lifecycle.reconcile();
      expect(
        (await app.sessions.sessionById(first.id))!.status,
        WinterArcStatus.completed,
      );
      final setup = await service.startNewArc(NewArcBaseline.fresh);
      final ids = await idsOf(setup.id);
      await expectRefused(
        () => app.habits.reorderSetupHabits(setup.id, [
          ...ids.skip(1),
          custom.id,
        ]),
        DomainRule.invalidHabitOrder,
      );
    });
  });

  group('a failure part-way rolls every row back', () {
    test('the third row fails: the first two moves are undone', () async {
      final id = await setupWith(8);
      final ids = await idsOf(id);
      final reversed = ids.reversed.toList();
      await _failUpdateOf(app.db, reversed[2]);
      final before = await snapshotAll(app.db);
      await expectLater(
        app.habits.reorderSetupHabits(id, reversed),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await snapshotAll(app.db), before);
      expect(await idsOf(id), ids);
    });

    test('through the service, the error is a storage failure, and the '
        'next valid reorder still works', () async {
      final id = await setupWith(4);
      final ids = await idsOf(id);
      await _failUpdateOf(app.db, ids.first);
      await expectLater(
        service.reorderSetupHabits(ids.reversed.toList()),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await idsOf(id), ids);
      await app.db.customStatement('DROP TRIGGER fail_reorder');
      await service.reorderSetupHabits(ids.reversed.toList());
      expect(await idsOf(id), ids.reversed.toList());
    });
  });

  group('concurrent setup changes never leave a stale order', () {
    test(
      'a reorder racing a removal: one wins, the other writes nothing',
      () async {
        final id = await setupWith(6);
        final ids = await idsOf(id);
        final results = await Future.wait([
          service.deleteSetupHabit(ids[1]).then<Object>((_) => 'deleted'),
          service
              .reorderSetupHabits(ids.reversed.toList())
              .then<Object>(
                (_) => 'reordered',
                onError: (Object e) => e is DomainFailure ? e.rule : e,
              ),
        ]);
        expect(results.first, 'deleted');
        expect(results.last, DomainRule.invalidHabitOrder);
        final left = await _orderOf(app.db, id);
        expect(
          [for (final (h, _) in left) h],
          [
            for (final h in ids)
              if (h != ids[1]) h,
          ],
        );
      },
    );

    test('reorder, edit, reorder, add, remove, toggle: the order is the '
        "user's at every step", () async {
      final id = await setupWith(5);
      var expected = (await idsOf(id)).reversed.toList();
      await service.reorderSetupHabits(expected);
      await service.editSetupHabit(
        'water',
        const HabitDraft(
          title: 'Water',
          type: HabitType.count,
          iconKey: 'water',
          target: 10,
          minimumTarget: 3,
          unit: 'glasses',
        ),
      );
      expect(await idsOf(id), expected, reason: 'an edit keeps its place');
      expected = [expected.last, ...expected.take(expected.length - 1)];
      await service.reorderSetupHabits(expected);
      final added = await service.addTemplateHabit('reading');
      final custom = await service.addCustomHabit(_custom('Sketch'));
      expected = [...expected, added.id, custom.id];
      expect(await idsOf(id), expected, reason: 'new habits go last');
      await service.deleteSetupHabit(expected[1]);
      expected.removeAt(1);
      expect(await idsOf(id), expected);
      expected = [expected[2], ...expected.where((h) => h != expected[2])];
      await service.reorderSetupHabits(expected);
      await service.setHabitEnabled(expected.first, enabled: false);
      await service.setHabitEnabled(expected.first, enabled: true);
      expect(await _orderOf(app.db, id), [
        for (final (i, h) in expected.indexed) (h, i),
      ]);
    });
  });

  test('a seasonal setup reorders like a rolling one', () async {
    app.clock.current = DateTime(2026, 9, 12, 9);
    final setup = await service.beginSetup(kind: ArcKind.seasonalWinter);
    expect(setup.startDate, LocalDate(2026, 10, 1));
    await expectReorder(setup.id, (await idsOf(setup.id)).reversed.toList());
  });
}
