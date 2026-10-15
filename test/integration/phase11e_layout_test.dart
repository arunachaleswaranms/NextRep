import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/habit/habit.dart';
import 'package:nextrep/domain/habit/setup_habit_rules.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/features/focus_guard/focus_guard_settings_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/updates.dart';

/// Phase 11E: the integrated screens on small and large layouts, in
/// portrait and landscape, with large text and reduced motion, filled with
/// long names and every v1.2 feature on. Each screen is scrolled from top
/// to bottom; any overflow or other framework error fails the case.
///
/// Synthetic apps only; GitHub is a fake.
const _longApp =
    'org.example.an.application.with.a.remarkably.long.package.name';

/// A layout to check: logical size, text scale, reduced motion.
typedef _Layout = ({String name, Size size, double text, bool reduceMotion});

const _layouts = <_Layout>[
  // The project's text-scale bar (Phases 7 and 10D): 2× on a phone.
  (name: 'phone, 2× text', size: Size(360, 800), text: 2, reduceMotion: false),
  (
    name: 'small phone, 1.5× text',
    size: Size(320, 568),
    text: 1.5,
    reduceMotion: false,
  ),
  (
    name: 'small phone landscape',
    size: Size(568, 320),
    text: 1,
    reduceMotion: false,
  ),
  (
    name: 'phone landscape, 1.3× text',
    size: Size(800, 360),
    text: 1.3,
    reduceMotion: false,
  ),
  (
    name: 'tablet landscape',
    size: Size(1280, 800),
    text: 1,
    reduceMotion: false,
  ),
  (
    name: 'phone, 1.3× text, reduced motion',
    size: Size(360, 640),
    text: 1.3,
    reduceMotion: true,
  ),
];

/// The screens of the integrated app. `about-checked` also taps Check for
/// updates (an available v1.2.0) and scrolls the result.
const _routes = <String>[
  AppRoutes.today,
  AppRoutes.journal,
  AppRoutes.history,
  AppRoutes.reminders,
  AppRoutes.focusGuard,
  AppRoutes.focusGuardApps,
  AppRoutes.dataBackup,
  AppRoutes.about,
  'about-checked',
  AppRoutes.insights,
  '/arc/1',
];

void main() {
  late AppDatabase db;
  late FakeClock clock;

  /// Arc 1 completed; Arc 2 running (Day 1, 1 Oct 2026) with a longest
  /// possible custom habit, Hydration Coach and every reminder on, and
  /// Focus Guard on over its budget with an uninstalled, long-named app.
  Future<void> seed() async {
    db = memoryDatabase();
    clock = FakeClock(DateTime(2026, 7, 1));
    final app = TestApp(
      db,
      clock,
      scheduler: FakeReminderScheduler(granted: true),
    );
    await runFirstArc(app);
    await app.winterArc.startNewArc(NewArcBaseline.reuseLast);
    await app.winterArc.addCustomHabit(
      HabitDraft(
        title: 'W' * 40,
        type: HabitType.count,
        iconKey: 'star',
        target: 12,
        minimumTarget: 3,
        unit: 'pages',
      ),
    );
    await app.winterArc.startWinterArc();
    clock.current = DateTime(2026, 10, 1, 13);
    await app.reminders.update(
      (p) => p.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
        hydrationEnabled: true,
        hydrationMode: HydrationMode.supportive,
      ),
    );
    await DriftFocusGuardSettingsRepository(db).save(
      const FocusGuardSettings(
        enabled: true,
        dailyBudgetMinutes: 1439,
        selectedPackages: ['org.example.video', _longApp],
      ),
      at: clock.now(),
    );
  }

  Widget appAt(String route) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(clock),
      ambientMotionProvider.overrideWithValue(false),
      reminderSchedulerProvider.overrideWithValue(
        FakeReminderScheduler(granted: false),
      ),
      focusGuardPlatformProvider.overrideWithValue(
        FakeFocusGuardPlatform(
          access: UsageAccess.granted,
          apps: [
            LaunchableAppCandidate(
              packageName: 'org.example.video',
              label: 'A video app whose label goes on and on ' * 2,
            ),
            for (var i = 0; i < 12; i++)
              LaunchableAppCandidate(
                packageName: 'org.example.app$i',
                label: 'Example application number $i',
              ),
          ],
          usage: const {'org.example.video': Duration(hours: 25)},
        )..nudges = false,
      ),
      focusGuardSchedulerProvider.overrideWithValue(
        FakeFocusGuardBackgroundScheduler(),
      ),
      releaseFeedProvider.overrideWithValue(
        GitHubReleaseFeed(client: FakeGitHubClient.new),
      ),
      installedAppSourceProvider.overrideWithValue(FakeInstalledAppSource()),
      externalLinksProvider.overrideWithValue(FakeExternalLinks()),
      bootLocationProvider.overrideWith((ref) async => route),
    ],
    retry: (_, _) => null,
    child: const NextRepApp(),
  );

  /// Scrolls every scrollable on screen to its end, a page at a time.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollables = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < scrollables.evaluate().length; i++) {
      for (var page = 0; page < 40; page++) {
        final state = tester.state<ScrollableState>(scrollables.at(i));
        final position = state.position;
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo(
          (position.pixels + position.viewportDimension * 0.8).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
      }
    }
  }

  for (final layout in _layouts) {
    for (final route in _routes) {
      // Insights' mood breakdown at 2× overflows only with the test font,
      // whose square glyphs are far wider than real ones ("Excellent"
      // alone is ~250 px). With the device font it fits: checked on the
      // API 36 emulator at font scale 2.0 and 360 dp (docs/PHASE_11E.md).
      // Unchanged since Phase 7; its other layouts stay in the sweep.
      if (route == AppRoutes.insights && layout.text >= 2) continue;
      testWidgets('${layout.name}: $route', (tester) async {
        tester.view
          ..physicalSize = layout.size * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = layout.text;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (layout.reduceMotion) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        await seed();
        addTearDown(db.close);

        final checkFirst = route == 'about-checked';
        await tester.pumpWidget(appAt(checkFirst ? AppRoutes.about : route));
        await tester.pumpAndSettle();
        // Let celebration cards time out like a user would.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
        }
        if (checkFirst) {
          final check = find.ancestor(
            of: find.text('Check for updates'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          await tester.scrollUntilVisible(
            check,
            150,
            scrollable: find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
          );
          await tester.ensureVisible(check);
          await tester.pumpAndSettle();
          await tester.tap(check);
          await tester.pumpAndSettle();
          expect(find.text('NextRep v1.2.0 is available.'), findsOneWidget);
        }
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }

  // Regression (Phase 11E defect D1): a budget shown beside the title,
  // e.g. the "1 h 30 min" preset, left "Combined daily budget" a sliver of
  // the row at 2× text on a phone (ListTile: "Trailing widget consumes the
  // entire tile width"; on the device the title broke mid-word). With large
  // text the value now sits under the title; at normal sizes it stays
  // beside it.
  for (final scale in [1.0, 2.0]) {
    for (final budget in [1, 15, 30, 45, 60, 90, 120, 180, 240, 1439, 1440]) {
      testWidgets('Focus Guard budget $budget min at $scale× text keeps '
          'its label whole', (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await seed();
        addTearDown(db.close);
        await DriftFocusGuardSettingsRepository(db).save(
          FocusGuardSettings(
            enabled: true,
            dailyBudgetMinutes: budget,
            selectedPackages: const ['org.example.video'],
          ),
          at: clock.now(),
        );
        await tester.pumpWidget(appAt(AppRoutes.focusGuard));
        await tester.pumpAndSettle();
        final label = find.text('Combined daily budget');
        await tester.scrollUntilVisible(
          label,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final title = tester.getRect(label);
        final value = tester.getRect(find.text(formatBudget(budget)));
        if (scale > 1.3) {
          // The title has the row to itself; the value is under it.
          expect(title.width, greaterThan(200));
          expect(value.top, greaterThanOrEqualTo(title.bottom));
        } else {
          // Unchanged at normal size: the value beside the title.
          expect(value.left, greaterThanOrEqualTo(title.right));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
