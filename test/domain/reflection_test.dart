import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_reflection_repository.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/domain/reflection/reflection_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';

Matcher _failsWith(DomainRule rule) =>
    throwsA(isA<DomainFailure>().having((f) => f.rule, 'rule', rule));

void main() {
  group('ReflectionRules', () {
    test('trims answers and treats whitespace as empty', () {
      final content = ReflectionRules.validate(
        const ReflectionDraft(win: '  Ran 5 km \n', improvement: '   '),
      );
      expect(content.win, 'Ran 5 km');
      expect(content.improvement, isNull);
      expect(content.mood, isNull);
    });

    test('rejects an empty reflection', () {
      for (final draft in const [
        ReflectionDraft(),
        ReflectionDraft(win: '   ', improvement: '\n\t'),
      ]) {
        expect(
          () => ReflectionRules.validate(draft),
          _failsWith(DomainRule.reflectionEmpty),
        );
      }
    });

    test('a mood alone or text alone is enough', () {
      expect(
        ReflectionRules.validate(const ReflectionDraft(mood: Mood.okay)).mood,
        Mood.okay,
      );
      expect(
        ReflectionRules.validate(const ReflectionDraft(improvement: 'Sleep')),
        isA<ReflectionContent>(),
      );
    });

    test('limits each answer to 240 characters, counting emoji once', () {
      final limit = 'a' * ReflectionRules.maxTextLength;
      expect(
        ReflectionRules.validate(ReflectionDraft(win: '  $limit  ')).win,
        limit,
      );
      expect(
        () => ReflectionRules.validate(ReflectionDraft(win: '${limit}b')),
        _failsWith(DomainRule.reflectionTooLong),
      );
      expect(
        () =>
            ReflectionRules.validate(ReflectionDraft(improvement: '${limit}b')),
        _failsWith(DomainRule.reflectionTooLong),
      );
      // 240 family emoji (several code points each) are 240 characters.
      final emoji = '👨‍👩‍👧' * ReflectionRules.maxTextLength;
      expect(ReflectionRules.validate(ReflectionDraft(win: emoji)).win, emoji);
    });

    test('moods are stored by stable keys; unknown keys read as none', () {
      expect(Mood.values.map((m) => m.key), [
        'rough',
        'okay',
        'good',
        'excellent',
      ]);
      expect(Mood.fromKey('good'), Mood.good);
      expect(Mood.fromKey('Good'), isNull);
      expect(Mood.fromKey('furious'), isNull);
      expect(Mood.fromKey(null), isNull);
    });
  });

  group('ReflectionService', () {
    late TestApp app;
    late WinterArcSession arc;
    final oct1 = LocalDate(2026, 10, 1);

    setUp(() async {
      app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1, 21)));
      await app.winterArc.beginSetup();
      arc = await app.winterArc.startWinterArc();
    });
    tearDown(() => app.db.close());

    Future<ReflectionSave> save(
      ReflectionDraft draft, {
      LocalDate? date,
      int? sessionId,
    }) => app.reflections.save(
      sessionId: sessionId ?? arc.id,
      date: date ?? app.clock.today(),
      draft: draft,
    );

    test('saves today and it persists', () async {
      final saved = await save(
        const ReflectionDraft(
          mood: Mood.good,
          win: ' Finished my workout ',
          improvement: 'Sleep earlier',
        ),
      );
      expect(saved.created, isTrue);
      expect(saved.reflection.date, oct1);
      expect(saved.reflection.win, 'Finished my workout');

      // Read back through a fresh repository over the same database.
      final stored = await DriftReflectionRepository(app.db)
          .reflectionOn(arc.id, oct1);
      expect(stored!.mood, Mood.good);
      expect(stored.improvement, 'Sleep earlier');
      expect(stored.createdAt, DateTime(2026, 10, 1, 21));
      final journal = await app.reflections.journal();
      expect(journal.todayEntry!.win, 'Finished my workout');
      expect(journal.canWriteToday, isTrue);
    });

    test('a second save updates instead of adding another', () async {
      await save(const ReflectionDraft(mood: Mood.okay));
      app.clock.current = DateTime(2026, 10, 1, 22, 30);
      final second = await save(
        const ReflectionDraft(mood: Mood.excellent, win: 'Late walk'),
      );
      expect(second.created, isFalse);
      expect(second.reflection.mood, Mood.excellent);
      expect(second.reflection.createdAt, DateTime(2026, 10, 1, 21));
      expect(second.reflection.updatedAt, DateTime(2026, 10, 1, 22, 30));
      expect(await app.db.select(app.db.dailyReflections).get(), hasLength(1));
    });

    test('an empty or invalid reflection is rejected and nothing is '
        'stored', () async {
      await expectLater(
        save(const ReflectionDraft(win: '  ')),
        _failsWith(DomainRule.reflectionEmpty),
      );
      await expectLater(
        save(ReflectionDraft(win: 'x' * 241)),
        _failsWith(DomainRule.reflectionTooLong),
      );
      expect(await app.db.select(app.db.dailyReflections).get(), isEmpty);
    });

    test('past dates are read-only, future dates unavailable', () async {
      await save(const ReflectionDraft(mood: Mood.good));
      app.clock.current = DateTime(2026, 10, 2, 21);
      await expectLater(
        save(const ReflectionDraft(mood: Mood.rough), date: oct1),
        _failsWith(DomainRule.reflectionReadOnly),
      );
      await expectLater(
        save(
          const ReflectionDraft(mood: Mood.rough),
          date: LocalDate(2026, 10, 3),
        ),
        _failsWith(DomainRule.reflectionNotAvailable),
      );
      final journal = await app.reflections.journal();
      expect(journal.todayEntry, isNull);
      expect(journal.past.single.mood, Mood.good);
    });

    test('a completed arc is read-only', () async {
      await save(const ReflectionDraft(mood: Mood.good));
      app.clock.current = DateTime(2027, 1, 1, 9); // Day 93
      await app.lifecycle.reconcile();
      await expectLater(
        save(const ReflectionDraft(mood: Mood.rough)),
        _failsWith(DomainRule.arcCompleted),
      );
      final journal = await app.reflections.journalFor(arc.id);
      expect(journal.canWriteToday, isFalse);
      expect(journal.todayEntry, isNull);
      expect(journal.past.single.date, oct1);
    });

    test('a save for an arc that is not the active one is rejected', () async {
      await expectLater(
        save(const ReflectionDraft(mood: Mood.good), sessionId: arc.id + 1),
        _failsWith(DomainRule.arcCompleted),
      );
    });

    test('reflections stay with their own arc', () async {
      final other = TestApp(memoryDatabase(), FakeClock(DateTime(2026)));
      addTearDown(other.db.close);
      final arc1 = await runFirstArc(other);
      await other.winterArc.startNewArc(NewArcBaseline.fresh);
      other.clock.current = DateTime(2026, 10, 2, 21);
      final arc2 = await other.winterArc.startWinterArc();
      await other.reflections.save(
        sessionId: arc2.id,
        date: other.clock.today(),
        draft: const ReflectionDraft(mood: Mood.excellent),
      );
      final journal1 = await other.reflections.journalFor(arc1.id);
      final journal2 = await other.reflections.journalFor(arc2.id);
      expect(journal1.past.map((r) => r.mood), [Mood.good]);
      expect(journal2.todayEntry!.mood, Mood.excellent);
      expect(journal2.past, isEmpty);
      expect(await other.reflectionStore.countFor(arc1.id), 1);
      expect(await other.reflectionStore.countFor(arc2.id), 1);
    });

    test('past entries are newest first with no invented days', () async {
      for (final (day, mood) in [
        (1, Mood.okay),
        (2, Mood.good),
        (4, Mood.rough),
        (5, Mood.excellent),
      ]) {
        app.clock.current = DateTime(2026, 10, day, 21);
        await save(ReflectionDraft(mood: mood));
      }
      final journal = await app.reflections.journal();
      expect(journal.todayEntry!.mood, Mood.excellent);
      expect(journal.past.map((r) => journal.dayNumberOf(r.date)), [4, 2, 1]);
      expect(journal.count, 4);
    });
  });

  test('a storage failure never carries reflection text', () async {
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1)));
    await app.winterArc.beginSetup();
    final arc = await app.winterArc.startWinterArc();
    await app.db.close(); // every query now fails
    const secret = 'my very private words';
    final failure = await app.reflectionStore
        .save(
          sessionId: arc.id,
          date: LocalDate(2026, 10, 1),
          content: ReflectionRules.validate(const ReflectionDraft(win: secret)),
          at: DateTime(2026, 10, 1),
        )
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(failure, isA<PersistenceFailure>());
    expect(failure.toString(), isNot(contains(secret)));
    expect(
      (failure! as PersistenceFailure).cause.toString(),
      isNot(contains(secret)),
    );
  });
}
