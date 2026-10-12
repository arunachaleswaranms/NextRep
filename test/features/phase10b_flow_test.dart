import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/share_gateway.dart';
import 'package:nextrep/domain/habit/habit_config.dart';
import 'package:nextrep/domain/habit/habit_template_catalog.dart';
import 'package:nextrep/domain/progress/day_record.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reflection/daily_reflection.dart';
import 'package:nextrep/features/achievements/achievements_screen.dart';
import 'package:nextrep/features/achievements/widgets/achievement_detail_sheet.dart';
import 'package:nextrep/features/achievements/widgets/trophy_button.dart';
import 'package:nextrep/features/share/share_card_data.dart';
import 'package:nextrep/features/share/share_choice_sheet.dart';
import 'package:nextrep/features/share/share_preview_screen.dart';
import 'package:nextrep/features/share/widgets/share_cards.dart';
import 'package:nextrep/features/today/widgets/habit_progress_tile.dart';

import '../support/arcs.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/share_fixtures.dart';
import '../support/ui.dart';

/// Phase 10B: sharing Today's Progress, My Arc and achievements through the
/// system share sheet (a fake here), and the new reduced-motion-safe
/// transitions.
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

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _textScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void _reducedMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _shareButton => find.text('Share');

/// Taps Share [times] in a row and lets the real PNG capture finish (it
/// runs on the engine, outside fake time).
Future<void> _tapShare(
  WidgetTester tester,
  FakeShareGateway gateway, {
  int times = 1,
}) async {
  final before = gateway.requests.length;
  await tester.runAsync(() async {
    for (var i = 0; i < times; i++) {
      await tester.tap(_shareButton, warnIfMissed: false);
    }
    for (var i = 0; i < 200 && gateway.requests.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

Future<void> _openTodayPreview(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Share progress'));
  expect(find.byType(ShareChoiceSheet), findsOneWidget);
  await _tap(tester, find.text("Today's Progress"));
  expect(find.byType(SharePreviewScreen), findsOneWidget);
}

Future<void> _openArcPreview(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Share progress'));
  // At large text the sheet scrolls.
  await tester.ensureVisible(find.text('My Arc'));
  await _tap(tester, find.text('My Arc'));
  expect(find.byType(SharePreviewScreen), findsOneWidget);
}

/// The card's own repaint boundary: what gets exported.
Finder _exportBoundary(Type card) => find
    .ancestor(of: find.byType(card), matching: find.byType(RepaintBoundary))
    .first;

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TestApp app;
  late FakeShareGateway gateway;

  Future<void> act(String habitId, HabitAction action, int times) async {
    for (var i = 0; i < times; i++) {
      await app.tracking.perform(
        habitId: habitId,
        action: action,
        date: clock.today(),
      );
    }
  }

  /// A rolling arc on 1 Oct with the default habits: water complete,
  /// workout half done, and a private reflection for today.
  setUp(() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    app = TestApp(db, clock);
    gateway = FakeShareGateway();
    final arc = await app.winterArc.beginSetup().then(
      (_) => app.winterArc.startWinterArc(),
    );
    await act('water', HabitAction.increment, 8);
    await act('workout', HabitAction.increment, 3);
    await app.reflections.save(
      sessionId: arc.id,
      date: clock.today(),
      draft: const ReflectionDraft(
        mood: Mood.rough,
        win: privateNote,
        improvement: 'PRIVATE-IMPROVEMENT',
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> launch(WidgetTester tester) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(_app(db, clock, gateway));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
  }

  void expectNothingPrivateOnScreen() {
    for (final secret in [privateNote, 'PRIVATE-IMPROVEMENT']) {
      expect(find.textContaining(secret), findsNothing);
      expect(find.bySemanticsLabel(RegExp(secret)), findsNothing);
    }
  }

  group("Today's Progress", () {
    testWidgets('Share asks which card first, then previews and shares one '
        'PNG through the system sheet, writing nothing', (tester) async {
      await launch(tester);
      final before = await dumpOf(db);

      // The entry point never opens the system sheet directly.
      await _tap(tester, find.byTooltip('Share progress'));
      expect(find.text('Share your Arc'), findsOneWidget);
      expect(gateway.requests, isEmpty);

      await _tap(tester, find.text("Today's Progress"));
      expect(find.text("Share Today's Progress"), findsOneWidget);
      expect(find.byType(TodayShareCard), findsOneWidget);
      expect(find.text('Water Intake'), findsWidgets);
      expectNothingPrivateOnScreen();

      // Only the card is exported, never the preview's controls or app
      // chrome.
      final boundary = _exportBoundary(TodayShareCard);
      for (final control in [Switch, FilledButton, AppBar, NavigationBar]) {
        expect(
          find.descendant(of: boundary, matching: find.byType(control)),
          findsNothing,
        );
      }

      await _tapShare(tester, gateway);
      expect(gateway.requests, hasLength(1));
      final file = gateway.lastFile;
      expect(file.mimeType, 'image/png');
      expect(file.name, 'nextrep-day-1.png');
      expect(pngSize(file.bytes), (width: 1080, height: 1350));
      expect(gateway.requests.single.origin, isNotNull);
      final text = gateway.requests.single.text;
      expect(
        text,
        'My Winter Arc · Day 1/92 — NextRep\n'
        'https://github.com/arunachaleswaranms/NextRep',
      );
      for (final secret in ['Water', 'Workout', privateNote, 'XP', '?']) {
        expect(text, isNot(contains(secret)));
      }
      // Shared: no message, no XP, no achievement, and the preview stays.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(SharePreviewScreen), findsOneWidget);
      expect(await dumpOf(db), before);
      await _shutDown(tester);
    });

    testWidgets('privacy switches change exactly what is exported and are '
        'not remembered', (tester) async {
      await launch(tester);
      await _openTodayPreview(tester);
      expect(find.text('LEVEL'), findsOneWidget);
      expect(
        find.text('Best active habit streak'.toUpperCase()),
        findsOneWidget,
      );

      await _tap(tester, find.text('Show habit names'));
      await _tap(tester, find.text('Show XP & level'));
      await tester.ensureVisible(find.text('Show streak'));
      await _tap(tester, find.text('Show streak'));

      final card = find.byType(TodayShareCard);
      for (final title in ['Water Intake', 'Workout', 'Learning / Skills']) {
        expect(
          find.descendant(of: card, matching: find.text(title)),
          findsNothing,
        );
      }
      expect(find.text('1 of 4 habits complete'), findsOneWidget);
      expect(find.text('LEVEL'), findsNothing);
      expect(find.textContaining('STREAK'), findsNothing);
      // Nor in what a screen reader hears.
      final label = tester
          .getSemantics(
            find.ancestor(of: card, matching: find.byType(Semantics)).first,
          )
          .label;
      expect(label, contains('1 of 4 habits complete'));
      expect(label, isNot(contains('Water')));
      expect(label, isNot(contains('XP')));
      expect(label, isNot(contains('streak')));

      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      expect(gateway.requests, hasLength(1));
      expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));

      // A new preview starts with everything shown again.
      await _tap(tester, find.byTooltip('Close'));
      await _openTodayPreview(tester);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        isTrue,
      );
      expect(find.text('LEVEL'), findsOneWidget);
      await _shutDown(tester);
    });

    testWidgets('rapid taps open one share sheet', (tester) async {
      await launch(tester);
      await _openTodayPreview(tester);
      await tester.ensureVisible(_shareButton);
      gateway.hold = Completer<void>();

      await _tapShare(tester, gateway, times: 3);
      expect(gateway.requests, hasLength(1));
      // While the sheet is open, Share is disabled.
      await tester.tap(_shareButton, warnIfMissed: false);
      await tester.pump();
      expect(gateway.requests, hasLength(1));

      await tester.runAsync(() async {
        gateway.hold!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      gateway.hold = null;
      await tester.pump();
      await _tapShare(tester, gateway);
      expect(gateway.requests, hasLength(2));
      await _shutDown(tester);
    });

    testWidgets('closing the sheet without sharing is not an error', (
      tester,
    ) async {
      gateway.outcome = ShareOutcome.dismissed;
      await launch(tester);
      final before = await dumpOf(db);
      await _openTodayPreview(tester);
      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      expect(gateway.requests, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(SharePreviewScreen), findsOneWidget);
      expect(await dumpOf(db), before);
      await _shutDown(tester);
    });

    testWidgets('a platform failure shows a message once, without retrying', (
      tester,
    ) async {
      gateway.error = PlatformException(code: 'no_activity');
      await launch(tester);
      final before = await dumpOf(db);
      await _openTodayPreview(tester);
      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      await tester.pump();
      expect(find.text("Couldn't open the share sheet."), findsOneWidget);
      expect(gateway.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(gateway.requests, hasLength(1));
      // Share works again afterwards.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: _shareButton,
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(await dumpOf(db), before);
      await _shutDown(tester);
    });

    testWidgets('a Minimum Day card says Minimum Day, not Perfect Day', (
      tester,
    ) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      await launch(tester);
      await _openTodayPreview(tester);
      expect(find.text('MINIMUM DAY'), findsOneWidget);
      expect(find.text('PERFECT DAY'), findsNothing);
      await _shutDown(tester);
    });
  });

  group('My Arc', () {
    testWidgets('shares the full goals of the current arc', (tester) async {
      await app.tracking.activateMinimumDay(date: clock.today());
      await launch(tester);
      final before = await dumpOf(db);
      await _openArcPreview(tester);
      expect(find.text('Share My Arc'), findsOneWidget);
      expect(find.text('MY 92-DAY WINTER ARC'), findsOneWidget);
      // Full targets even on a Minimum Day.
      expect(find.text('8 glasses'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('3 glasses'), findsNothing);
      // No privacy switches: the card is about goals, not today.
      expect(find.byType(SwitchListTile), findsNothing);
      expectNothingPrivateOnScreen();

      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      expect(gateway.lastFile.name, 'nextrep-my-arc.png');
      expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));
      expect(gateway.requests.single.text, isNot(contains('glasses')));
      expect(await dumpOf(db), before);
      await _shutDown(tester);
    });
  });

  group('Achievements', () {
    testWidgets('an unlocked achievement opens details with "Share <title>"; '
        'a locked one has no share action', (tester) async {
      await launch(tester);
      await _tap(tester, find.byType(TrophyButton));
      await clearCelebrations(tester);
      final before = await dumpOf(db);

      // Locked: not a button, nothing opens.
      await reveal(tester, find.text('Summit'));
      final summit = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^Summit\.')),
      );
      expect(summit.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      await _tap(tester, find.text('Summit'));
      expect(find.byType(AchievementDetailSheet), findsNothing);

      // Unlocked: a labelled button that opens the details.
      await tester.scrollUntilVisible(
        find.text('First Rep'),
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final firstRep = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^First Rep\.')),
      );
      expect(
        firstRep.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      await _tap(tester, find.text('First Rep'));
      expect(find.byType(AchievementDetailSheet), findsOneWidget);
      expect(find.text('Unlocked on Day 1'), findsOneWidget);

      await _tap(tester, find.text('Share First Rep'));
      expect(find.text('Share Achievement'), findsOneWidget);
      expect(find.text('FIRST REP'), findsOneWidget);
      expect(find.text('UNLOCKED · DAY 1'), findsOneWidget);
      expectNothingPrivateOnScreen();

      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      expect(gateway.lastFile.name, 'nextrep-achievement-first-rep.png');
      expect(gateway.lastFile.mimeType, 'image/png');
      expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));
      expect(
        gateway.requests.single.text,
        'Achievement unlocked: First Rep — NextRep\n'
        'https://github.com/arunachaleswaranms/NextRep',
      );

      // Closing the preview also closes the details sheet.
      await _tap(tester, find.byTooltip('Close'));
      expect(find.byType(AchievementDetailSheet), findsNothing);
      expect(find.byType(AchievementsScreen), findsOneWidget);
      expect(await dumpOf(db), before);
      await _shutDown(tester);
    });
  });

  group('accessibility at 2x text', () {
    testWidgets('the Today share entry and the choice sheet', (tester) async {
      _textScale(tester, 2);
      await launch(tester);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Share progress'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await _tap(tester, find.byTooltip('Share progress'));
      expect(tester.takeException(), isNull);
      // The sheet grows with the text and scrolls; each choice can be
      // reached and tapped.
      for (final choice in ["Today's Progress", 'My Arc']) {
        await tester.ensureVisible(find.text(choice));
        await tester.pumpAndSettle();
        expect(find.text(choice).hitTestable(), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      await _shutDown(tester);
    });

    testWidgets("the Today's Progress preview keeps its switches and Share "
        'reachable', (tester) async {
      _textScale(tester, 2);
      await launch(tester);
      await _openTodayPreview(tester);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Show habit names',
        'Show XP & level',
        'Show streak',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(_shareButton);
      await tester.pumpAndSettle();
      expect(_shareButton.hitTestable(), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await _tapShare(tester, gateway);
      expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));
      await _shutDown(tester);
    });

    testWidgets('the My Arc preview', (tester) async {
      _textScale(tester, 2);
      await launch(tester);
      await _openArcPreview(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_shareButton);
      await tester.pumpAndSettle();
      expect(_shareButton.hitTestable(), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await _shutDown(tester);
    });

    testWidgets('the achievement details and share preview', (tester) async {
      _textScale(tester, 2);
      await launch(tester);
      await _tap(tester, find.byType(TrophyButton));
      await clearCelebrations(tester);
      await tester.ensureVisible(find.text('First Rep'));
      await _tap(tester, find.text('First Rep'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Share First Rep'));
      await tester.pumpAndSettle();
      expect(find.text('Share First Rep').hitTestable(), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await _tap(tester, find.text('Share First Rep'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_shareButton);
      await tester.pumpAndSettle();
      expect(_shareButton.hitTestable(), findsOneWidget);
      await _shutDown(tester);
    });
  });

  group('motion', () {
    // One theme instance, so MaterialApp has no theme change to animate.
    final theme = buildWinterTheme();
    final water = HabitTemplateCatalog.all
        .firstWhere((t) => t.id == 'water')
        .toHabit(sortOrder: 0, createdAt: DateTime(2026, 10, 1));

    Widget tile({
      required int target,
      required int value,
      bool minimum = false,
    }) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: HabitProgressTile(
          entry: HabitDayEntry(
            habit: water,
            config: const HabitConfig(
              target: 8,
              minimumTarget: 3,
              enabled: true,
            ),
            target: target,
            progress: progress(
              'water',
              day1,
              value,
              completed: value >= target,
            ),
          ),
          minimum: minimum,
          onAction: (_) {},
        ),
      ),
    );

    /// The transition around [label] inside the tile's target switcher.
    FadeTransition incoming(WidgetTester tester, String label) =>
        tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(FadeTransition),
              )
              .first,
        );

    testWidgets('Normal → Minimum eases the target over', (tester) async {
      await tester.pumpWidget(tile(target: 8, value: 4));
      await tester.pumpWidget(tile(target: 3, value: 4, minimum: true));
      await tester.pump(const Duration(milliseconds: 120));
      // Mid-transition both labels are there, the new one fading in.
      expect(find.text('4 / 8 glasses'), findsOneWidget);
      expect(find.text('4 / 3 glasses'), findsOneWidget);
      final opacity = incoming(tester, '4 / 3 glasses').opacity.value;
      expect(opacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('4 / 8 glasses'), findsNothing);
      expect(find.text('4 / 3 glasses'), findsOneWidget);
      expect(find.text('MINIMUM'), findsOneWidget);
    });

    testWidgets('Minimum → Normal eases it back', (tester) async {
      await tester.pumpWidget(tile(target: 3, value: 4, minimum: true));
      await tester.pumpWidget(tile(target: 8, value: 4));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('4 / 3 glasses'), findsOneWidget);
      expect(find.text('4 / 8 glasses'), findsOneWidget);
      expect(
        incoming(tester, '4 / 8 glasses').opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('4 / 3 glasses'), findsNothing);
      expect(find.text('MINIMUM'), findsNothing);
    });

    testWidgets('an ordinary + updates the label in place', (tester) async {
      await tester.pumpWidget(tile(target: 8, value: 4));
      await tester.pumpWidget(tile(target: 8, value: 5));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('4 / 8 glasses'), findsNothing);
      expect(find.text('5 / 8 glasses'), findsOneWidget);
      expect(incoming(tester, '5 / 8 glasses').opacity.value, 1);
    });

    testWidgets('under reduced motion the target changes at once', (
      tester,
    ) async {
      _reducedMotion(tester);
      // 2 glasses stays incomplete either way, so only the target changes.
      await tester.pumpWidget(tile(target: 8, value: 2));
      await tester.pumpWidget(tile(target: 3, value: 2, minimum: true));
      await tester.pump();
      expect(find.text('2 / 8 glasses'), findsNothing);
      expect(find.text('2 / 3 glasses'), findsOneWidget);
      expect(find.text('MINIMUM'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    Widget preview() => ProviderScope(
      overrides: [shareGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        theme: theme,
        home: SharePreviewScreen(
          title: 'Share My Arc',
          content: (_) => ShareCardContent.arc(
            ArcShareCardData.fromSummary(
              shareSummary(habits: catalogHabits(count: 8)),
            ),
          ),
        ),
      ),
    );

    Opacity reveal(WidgetTester tester) => tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byType(ArcShareCard),
            matching: find.byType(Opacity),
          )
          .first,
    );

    testWidgets('the share preview reveals its card once', (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(preview());
      expect(reveal(tester).opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(reveal(tester).opacity, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(reveal(tester).opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('under reduced motion the preview is complete on its first '
        'frame and stays accessible', (tester) async {
      _reducedMotion(tester);
      await _setPhoneSize(tester);
      await tester.pumpWidget(preview());
      expect(reveal(tester).opacity, 1);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.bySemanticsLabel(RegExp('^My Arc card')), findsOneWidget);
      await tester.ensureVisible(_shareButton);
      await _tapShare(tester, gateway);
      expect(pngSize(gateway.lastFile.bytes), (width: 1080, height: 1350));
    });
  });
}
