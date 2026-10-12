import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/features/achievements/achievements_screen.dart';
import 'package:nextrep/features/achievements/widgets/achievement_card.dart';
import 'package:nextrep/features/achievements/widgets/achievement_detail_sheet.dart';
import 'package:nextrep/features/achievements/widgets/trophy_button.dart';
import 'package:nextrep/features/celebration/celebration_cards.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';
import 'package:nextrep/shared/widgets/habit_icon.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/share_fixtures.dart';
import '../support/ui.dart';

/// Phase 10C: the grouped achievement collection, sharing the new
/// achievements, the combined backfill celebration, and the new templates
/// in the setup picker.
Widget _app(AppDatabase db, FakeClock clock, FakeShareGateway gateway) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        ambientMotionProvider.overrideWithValue(false),
        shareGatewayProvider.overrideWithValue(gateway),
      ],
      retry: (_, _) => null,
      child: const NextRepApp(),
    );

void _setSize(WidgetTester tester, {double logicalHeight = 800}) {
  tester.view.physicalSize = Size(1080, logicalHeight * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _textScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the collection until [finder] is on screen.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder _card(String title) => find.widgetWithText(AchievementCard, title);

const _headings = [
  'PROGRESS',
  'CONSISTENCY',
  'RESILIENCE',
  'HABIT MASTERY',
  'REFLECTION',
  'JOURNEY',
];

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TestApp app;
  late FakeShareGateway gateway;

  /// A rolling arc from 1 Oct: No Junk Food done on Days 1-14, now Day 15.
  /// Unlocked: First Rep, Snowball, Cold Front, Clean Week (Day 7), Two
  /// Weeks Strong and First Chapter (Day 14).
  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    app = TestApp(db, clock);
    gateway = FakeShareGateway();
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
    for (var day = 1; day <= 14; day++) {
      clock.current = DateTime(2026, 10, day, 9);
      await completeHabit(app, 'no_junk_food');
      await app.achievements.reconcile();
    }
    clock.current = DateTime(2026, 10, 15, 9);
    await app.achievements.reconcile();
  });
  tearDown(() => db.close());

  Future<void> openCollection(WidgetTester tester) async {
    await tester.pumpWidget(_app(db, clock, gateway));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    await _tap(tester, find.byType(TrophyButton));
    await clearCelebrations(tester);
    expect(find.byType(AchievementsScreen), findsOneWidget);
  }

  testWidgets('the collection is grouped under six category headings, each '
      'achievement under its own', (tester) async {
    // Tall enough for the whole collection to be laid out at once.
    _setSize(tester, logicalHeight: 8000);
    await openCollection(tester);
    expect(find.text('6 of 32 unlocked'), findsOneWidget);
    expect(
      find.bySemanticsLabel('6 of 32 achievements unlocked'),
      findsOneWidget,
    );
    expect(find.byType(AchievementCard), findsNWidgets(32));

    double top(Finder f) => tester.getTopLeft(f).dy;
    final headingTops = [for (final h in _headings) top(find.text(h))];
    expect(headingTops, [...headingTops]..sort(), reason: 'category order');
    for (final definition in AchievementCatalog.all) {
      final index = definition.category.index;
      final y = top(_card(definition.title));
      expect(y, greaterThan(headingTops[index]), reason: definition.title);
      if (index + 1 < headingTops.length) {
        expect(y, lessThan(headingTops[index + 1]), reason: definition.title);
      }
    }

    // Headings are real text headers that say how much is unlocked.
    for (final (label, count) in const [
      ('Progress, 1 of 4 unlocked', 1),
      ('Consistency, 3 of 9 unlocked', 1),
      ('Resilience, 0 of 3 unlocked', 1),
      ('Habit Mastery, 1 of 7 unlocked', 1),
      ('Reflection, 0 of 4 unlocked', 1),
      ('Journey, 1 of 5 unlocked', 1),
    ]) {
      final heading = find.bySemanticsLabel(label);
      expect(heading, findsNWidgets(count));
      final data = tester.getSemantics(heading).getSemanticsData();
      expect(data.flagsCollection.isHeader, isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isFalse, reason: label);
    }

    // Locked and unlocked states, with their criteria.
    expect(
      find.bySemanticsLabel(
        'Clean Week. Unlocked, Day 7 · 7 Oct. '
        'Reach a 7-day No Junk Food streak.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Two Weeks Strong. Unlocked, Day 14 · 14 Oct. '
        'Reach a 14-day streak on any habit.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Iron Winter. Locked. Reach a 50-day streak on any habit.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Hydration Rhythm. Locked. '
        'Meet your own Water Intake goal on 30 days in total.',
      ),
      findsOneWidget,
    );
    await _shutDown(tester);
  });

  testWidgets('a new unlocked achievement opens its details and shares '
      'through the Phase 10B preview; a locked new one does not', (
    tester,
  ) async {
    _setSize(tester);
    await openCollection(tester);
    final before = await dumpOf(db);

    // Locked: no tap action, nothing opens.
    await _scrollTo(tester, find.text('Iron Winter'));
    final iron = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^Iron Winter\.')),
    );
    expect(iron.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    await _tap(tester, find.text('Iron Winter'));
    expect(find.byType(AchievementDetailSheet), findsNothing);

    await _scrollTo(tester, find.text('Clean Week'));
    await _tap(tester, find.text('Clean Week'));
    expect(find.byType(AchievementDetailSheet), findsOneWidget);
    expect(find.text('Unlocked on Day 7'), findsOneWidget);
    await tester.ensureVisible(find.text('Share Clean Week'));
    await _tap(tester, find.text('Share Clean Week'));
    expect(find.text('Share Achievement'), findsOneWidget);
    expect(find.text('CLEAN WEEK'), findsOneWidget);
    expect(find.text('UNLOCKED · DAY 7'), findsOneWidget);

    await tester.ensureVisible(find.text('Share'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share'), warnIfMissed: false);
      for (var i = 0; i < 200 && gateway.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(gateway.lastFile.name, 'nextrep-achievement-clean-week.png');
    expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));
    expect(
      gateway.requests.single.text,
      'Achievement unlocked: Clean Week — NextRep',
    );
    await _tap(tester, find.byTooltip('Close'));
    expect(find.byType(AchievementDetailSheet), findsNothing);
    // Sharing writes nothing.
    expect(await dumpOf(db), before);
    await _shutDown(tester);
  });

  testWidgets('at 2x text: no overflow, headings and descriptions readable, '
      'Journey reachable, details and Share reachable', (tester) async {
    _setSize(tester);
    _textScale(tester, 2);
    await openCollection(tester);
    for (final heading in _headings) {
      await _scrollTo(tester, find.text(heading));
      expect(tester.takeException(), isNull, reason: heading);
    }
    await _scrollTo(tester, find.text('Summit'));
    expect(find.text('Complete the 92-day Winter Arc.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Two Weeks Strong'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Two Weeks Strong'));
    expect(find.byType(AchievementDetailSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Share Two Weeks Strong'));
    await tester.pumpAndSettle();
    expect(find.text('Share Two Weeks Strong').hitTestable(), findsOneWidget);
    await _tap(tester, find.text('Share Two Weeks Strong'));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share').hitTestable(), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('upgrading shows the backfilled achievements as one card', (
    tester,
  ) async {
    // The state v1.0 left: it didn't know the Phase 10C achievements.
    await (db.delete(db.achievementUnlocks)..where(
          (a) => a.achievementKey.isIn(['no_junk_7', 'streak_14', 'day_14']),
        ))
        .go();
    _setSize(tester);
    await tester.pumpWidget(_app(db, clock, gateway));
    await tester.pumpAndSettle();

    expect(find.byType(CelebrationCard), findsOneWidget);
    expect(find.text('3 ACHIEVEMENTS UNLOCKED'), findsOneWidget);
    expect(
      find.text('Two Weeks Strong · Clean Week · First Chapter'),
      findsOneWidget,
    );
    await clearCelebrations(tester);
    expect(find.byType(CelebrationCard), findsNothing);
    final rows = {
      for (final r in await db.select(db.achievementUnlocks).get())
        r.achievementKey: r.unlockedOn.toIsoString(),
    };
    expect(rows['no_junk_7'], '2026-10-07');
    expect(rows['streak_14'], '2026-10-14');
    expect(rows['day_14'], '2026-10-14');
    await _shutDown(tester);
  });

  group('templates in setup', () {
    late AppDatabase setupDb;

    setUp(() async {
      setupDb = memoryDatabase();
      await TestApp(setupDb, clock).winterArc.beginSetup();
    });
    tearDown(() => setupDb.close());

    Future<void> openAddHabit(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Add Habit'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Add Habit'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Add Habit'));
    }

    Future<void> revealInSheet(
      WidgetTester tester,
      Finder finder, {
      double delta = 150,
    }) async {
      await tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the picker offers the six new templates with their icons; '
        'Hair Care is added once', (tester) async {
      _setSize(tester);
      await tester.pumpWidget(_app(setupDb, clock, gateway));
      await tester.pumpAndSettle();
      // Not seeded.
      expect(find.widgetWithText(HabitToggleTile, 'Hair Care'), findsNothing);

      await openAddHabit(tester);
      for (final (title, detail, icon) in const [
        ('Hair Care', 'Done / not done · Daily', Icons.content_cut_rounded),
        (
          'Skin Care',
          'Done / not done · Daily',
          Icons.face_retouching_natural_rounded,
        ),
        ('Eat Fruit', 'Done / not done · Daily', Icons.eco_rounded),
        ('Nuts / Seeds', 'Done / not done · Daily', Icons.grain_rounded),
        (
          'Stretch / Mobility',
          'Minutes · Goal 10 min · Minimum 5 min',
          Icons.accessibility_new_rounded,
        ),
        (
          'Reading',
          'Minutes · Goal 15 min · Minimum 5 min',
          Icons.auto_stories_rounded,
        ),
      ]) {
        final template = find.bySemanticsLabel(
          RegExp('^${RegExp.escape(title)} template'),
        );
        await revealInSheet(tester, template);
        expect(template, findsOneWidget, reason: title);
        expect(
          find.bySemanticsLabel(
            RegExp('^${RegExp.escape(title)} template.*already added'),
          ),
          findsNothing,
        );
        final row = find
            .ancestor(of: find.text(title), matching: find.byType(Row))
            .first;
        expect(
          find.descendant(of: row, matching: find.text(detail)),
          findsOneWidget,
          reason: title,
        );
        expect(
          find.descendant(
            of: find.descendant(of: row, matching: find.byType(HabitIcon)),
            matching: find.byIcon(icon),
          ),
          findsOneWidget,
          reason: title,
        );
      }

      final hair = find.bySemanticsLabel(RegExp(r'^Hair Care template'));
      await revealInSheet(tester, hair, delta: -150);
      await _tap(tester, hair);
      expect(find.text('Hair Care added'), findsOneWidget);
      final habits = await TestApp(setupDb, clock).winterArc.setupHabits();
      final added = habits.singleWhere((h) => h.id == 'hair_care');
      expect(added.enabled, isTrue);

      // Offered again as already added: can't be added twice.
      await openAddHabit(tester);
      final again = find.bySemanticsLabel(
        RegExp(r'^Hair Care template.*already added'),
      );
      await revealInSheet(tester, again);
      expect(again, findsOneWidget);
      await tester.tap(find.text('Hair Care').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        (await TestApp(
          setupDb,
          clock,
        ).winterArc.setupHabits()).where((h) => h.id == 'hair_care'),
        hasLength(1),
      );
      await _shutDown(tester);
    });
  });
}
