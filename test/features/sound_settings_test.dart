import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/data/drift_feedback_preferences_repository.dart';
import 'package:nextrep/domain/backup/backup_codec.dart';
import 'package:nextrep/domain/feedback/completion_sound.dart';
import 'package:nextrep/domain/feedback/feedback_preferences.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/habit_setup/saved_setup_screen.dart';
import 'package:nextrep/features/history/arc_history_screen.dart';
import 'package:nextrep/features/onboarding/onboarding_screen.dart';
import 'package:nextrep/features/sound/sound_settings_screen.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/pause_support.dart';
import '../support/restart_support.dart';
import '../support/sound_app.dart';
import '../support/sound_fakes.dart';
import '../support/ui.dart';

/// Sound & Feedback (`/settings/sound`, spec § 8.4, § 9.12, N2, N7;
/// addendum § L5 "R"): the switch, the three sets and their previews, a
/// failed write, persistence across relaunch, Restart and restore, every
/// entry point, accessibility and layouts.
void main() {
  late FakeSoundPlayer player;
  late FakeMonotonic monotonic;

  setUp(() {
    player = FakeSoundPlayer();
    monotonic = FakeMonotonic();
  });

  Finder sw() => find.byKey(const ValueKey('sound-switch'));
  Finder set(SoundTheme t) => find.byKey(ValueKey('sound-${t.name}'));
  Finder preview(SoundTheme t) => find.byKey(ValueKey('preview-${t.name}'));

  Future<FeedbackPreferences> stored(TestApp app) =>
      DriftFeedbackPreferencesRepository(app.db).load();

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openFromToday(WidgetTester tester) async {
    await clearCelebrations(tester);
    await tester.tap(find.byTooltip(SoundCopy.title));
    await tester.pumpAndSettle();
    expect(find.byType(SoundSettingsScreen), findsOneWidget);
  }

  bool switchOn(WidgetTester tester) =>
      tester.widget<SwitchListTile>(sw()).value;

  SoundTheme? selected(WidgetTester tester) => tester
      .widget<RadioGroup<SoundTheme>>(find.byType(RadioGroup<SoundTheme>))
      .groupValue;

  Future<TestApp> activeArc() async {
    final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 4, 9)));
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
    return app;
  }

  testWidgets('defaults, the wording of § 9.12, and previews', (tester) async {
    await phoneSize(tester);
    final app = await activeArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);

    expect(find.text('Sound & Feedback'), findsOneWidget);
    expect(find.text('Completion sounds'), findsOneWidget);
    expect(
      find.text('A short sound when you complete a habit.'),
      findsOneWidget,
    );
    expect(find.text('SOUND'), findsOneWidget);
    for (final name in ['Ice Crystal', 'Summit Spark', 'Warm Ember']) {
      expect(find.text(name), findsOneWidget);
      expect(find.byTooltip('Play $name'), findsOneWidget);
    }
    expect(
      find.text(
        "Sounds follow your phone's sound settings. They stay quiet on "
        'silent and Do Not Disturb.',
      ),
      findsOneWidget,
    );
    expect(find.text('Turn on sounds to choose one.'), findsNothing);
    expect(
      find.textContaining('olume'),
      findsNothing,
      reason: 'no volume slider',
    );
    expect(
      find.textContaining('aptic'),
      findsNothing,
      reason: 'no haptics switch',
    );
    expect(switchOn(tester), isTrue);
    expect(selected(tester), SoundTheme.iceCrystal);
    // Opening writes nothing and plays nothing.
    expect(await app.db.select(app.db.feedbackPrefs).get(), isEmpty);
    expect(player.plays, isEmpty);

    // A preview plays that set's habit sound and selects nothing.
    monotonic.advance(const Duration(seconds: 4));
    await tap(tester, preview(SoundTheme.warmEmber));
    expect(player.plays, [(SoundTheme.warmEmber, CompletionSound.habit)]);
    expect(selected(tester), SoundTheme.iceCrystal);
    expect(await app.db.select(app.db.feedbackPrefs).get(), isEmpty);

    // A failing preview is silent and changes nothing.
    player.failPlay = true;
    monotonic.advance(const Duration(seconds: 4));
    await tap(tester, preview(SoundTheme.summitSpark));
    expect(tester.takeException(), isNull);
    expect(find.text(SoundCopy.saveFailed), findsNothing);
    expect(await stored(app), FeedbackPreferences.defaults);
    await shutDown(tester);
  });

  testWidgets('choosing a set stores it at once and previews it', (
    tester,
  ) async {
    await phoneSize(tester);
    final app = await activeArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);

    monotonic.advance(const Duration(seconds: 4));
    await tap(tester, set(SoundTheme.summitSpark));
    expect(selected(tester), SoundTheme.summitSpark);
    expect(
      await stored(app),
      const FeedbackPreferences(
        soundsEnabled: true,
        soundTheme: SoundTheme.summitSpark,
      ),
    );
    expect(player.plays, [(SoundTheme.summitSpark, CompletionSound.habit)]);
    await shutDown(tester);
  });

  testWidgets('switching sounds off disables the list and previews, with a '
      'reason, and nothing ever plays', (tester) async {
    await phoneSize(tester);
    final app = await activeArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);

    await tap(tester, sw());
    expect(switchOn(tester), isFalse);
    expect((await stored(app)).soundsEnabled, isFalse);
    expect(find.text('Turn on sounds to choose one.'), findsOneWidget);
    for (final t in SoundTheme.values) {
      expect(tester.widget<RadioListTile<SoundTheme>>(set(t)).enabled, isFalse);
      expect(tester.widget<IconButton>(preview(t)).onPressed, isNull);
    }
    // The disabled preview is still announced, as disabled.
    final semantics = tester.getSemantics(preview(SoundTheme.iceCrystal));
    expect(semantics.label, contains('Play Ice Crystal'));
    expect(semantics.flagsCollection.isEnabled.toString(), contains('isFalse'));
    // Taps on the dimmed controls change and play nothing.
    monotonic.advance(const Duration(seconds: 4));
    await tester.tap(set(SoundTheme.warmEmber), warnIfMissed: false);
    await tester.tap(preview(SoundTheme.warmEmber), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(selected(tester), SoundTheme.iceCrystal);
    expect(player.plays, isEmpty);

    // On again: the list returns, the stored set unchanged.
    await tap(tester, sw());
    expect((await stored(app)).soundsEnabled, isTrue);
    expect(find.text('Turn on sounds to choose one.'), findsNothing);
    expect(player.plays, isEmpty, reason: 'turning on is silent');
    await shutDown(tester);
  });

  testWidgets('a failed write shows "Couldn\'t save." and the stored value', (
    tester,
  ) async {
    await phoneSize(tester);
    final app = await activeArc();
    addTearDown(app.db.close);
    final failing = FakeFeedbackPreferences(
      const FeedbackPreferences(
        soundsEnabled: true,
        soundTheme: SoundTheme.warmEmber,
      ),
    )..failSave = true;
    await tester.pumpWidget(
      soundApp(
        app,
        player: player,
        monotonic: monotonic,
        extra: [
          feedbackPreferencesRepositoryProvider.overrideWithValue(failing),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);
    expect(selected(tester), SoundTheme.warmEmber);

    await tap(tester, sw());
    expect(find.text("Couldn't save."), findsOneWidget);
    expect(switchOn(tester), isTrue);

    monotonic.advance(const Duration(seconds: 4));
    await tap(tester, set(SoundTheme.iceCrystal));
    expect(selected(tester), SoundTheme.warmEmber);
    expect(find.text("Couldn't save."), findsOneWidget);
    expect(player.plays, isEmpty, reason: 'no preview of an unsaved choice');
    expect(failing.saves, 0);
    await shutDown(tester);
  });

  testWidgets('the setting survives a relaunch and an Arc Restart', (
    tester,
  ) async {
    await phoneSize(tester);
    final app = await activeArc();
    addTearDown(app.db.close);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);
    monotonic.advance(const Duration(seconds: 4));
    await tap(tester, set(SoundTheme.warmEmber));
    await tap(tester, sw());
    await shutDown(tester);

    // Relaunch (a new app over the same storage).
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);
    expect(switchOn(tester), isFalse);
    expect(selected(tester), SoundTheme.warmEmber);
    await shutDown(tester);

    // Restart: a new Arc, the same app-level setting.
    final old = (await app.tracking.today()).session;
    app.clock.current = DateTime(2026, 10, 6, 9);
    await restartNow(app, old.id);
    await tester.pumpWidget(
      soundApp(app, player: player, monotonic: monotonic),
    );
    await tester.pumpAndSettle();
    await openFromToday(tester);
    expect(switchOn(tester), isFalse);
    expect(selected(tester), SoundTheme.warmEmber);
    expect(player.plays, hasLength(1)); // the one preview, nothing since
    await shutDown(tester);
  });

  group('restore', () {
    Uint8List asFormat(Uint8List v4, int version) {
      final json = jsonDecode(utf8.decode(v4)) as Map<String, dynamic>;
      json['formatVersion'] = version;
      final data = json['data'] as Map<String, dynamic>..remove('feedback');
      for (final arc in data['arcs'] as List) {
        (arc as Map<String, dynamic>)
          ..remove('closedOn')
          ..remove('freezes');
      }
      final body = {...json}..remove('checksum');
      json['checksum'] = {
        'algorithm': 'sha256',
        'value': BackupCodec.checksumOf(body),
      };
      return Uint8List.fromList(utf8.encode(jsonEncode(json)));
    }

    Future<void> restore(
      WidgetTester tester,
      Uint8List bytes,
      TestApp app,
    ) async {
      await tester.pumpWidget(
        soundApp(
          app,
          player: player,
          monotonic: monotonic,
          extra: [
            backupFilesProvider.overrideWithValue(
              FakeBackupFiles(toPick: bytes),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Data & Backup'));
      await tester.pumpAndSettle();
      Finder button(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      await tester.tap(find.text('Restore Backup'));
      await tester.pumpAndSettle();
      await tester.tap(button('Restore'));
      await tester.pumpAndSettle();
      await tester.tap(button('Replace Data'));
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    }

    testWidgets('a format-4 backup restores the stored setting and plays '
        'nothing, even over completed habits', (tester) async {
      await phoneSize(tester);
      final source = await activeArc();
      addTearDown(source.db.close);
      await completeAll(source); // a Perfect Day in the backup
      await DriftFeedbackPreferencesRepository(source.db).save(
        const FeedbackPreferences(
          soundsEnabled: false,
          soundTheme: SoundTheme.summitSpark,
        ),
        at: source.clock.now(),
      );
      final bytes = (await source.backup.export()).bytes;
      expect(jsonDecode(utf8.decode(bytes))['formatVersion'], 4);

      final target = await activeArc();
      addTearDown(target.db.close);
      await restore(tester, bytes, target);
      expect(
        await stored(target),
        const FeedbackPreferences(
          soundsEnabled: false,
          soundTheme: SoundTheme.summitSpark,
        ),
      );
      expect(player.plays, isEmpty);
      await openFromToday(tester);
      expect(switchOn(tester), isFalse);
      expect(selected(tester), SoundTheme.summitSpark);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    /// The older files: Phase 5's genuine format-1 fixture, v1.1's genuine
    /// format-2 fixture, and this device's own export rewritten as format 3
    /// (as v1.2 wrote it; no genuine format-3 file is committed).
    Future<Uint8List> older(int version) async {
      switch (version) {
        case 1:
          return File('test/fixtures/phase5_backup_v1.nextrep')
              .readAsBytesSync();
        case 2:
          return File('test/fixtures/v1_1_backup_v2.nextrep').readAsBytesSync();
        default:
          final source = await activeArc();
          await completeAll(source);
          final bytes = asFormat((await source.backup.export()).bytes, 3);
          await source.db.close();
          return bytes;
      }
    }

    for (final version in [1, 2, 3]) {
      testWidgets("a format-$version backup keeps this device's setting and "
          'plays nothing', (tester) async {
        await phoneSize(tester);
        final bytes = await older(version);
        final target = await activeArc();
        addTearDown(target.db.close);
        const mine = FeedbackPreferences(
          soundsEnabled: false,
          soundTheme: SoundTheme.warmEmber,
        );
        await DriftFeedbackPreferencesRepository(target.db)
            .save(mine, at: target.clock.now());
        await restore(tester, bytes, target);
        expect(await stored(target), mine);
        expect(player.plays, isEmpty);
        await shutDown(tester);
      });
    }
  });

  group('entry points, in every state', () {
    Future<void> openAndBack(WidgetTester tester, Type from) async {
      expect(find.byType(SoundSettingsScreen), findsOneWidget);
      expect(find.text('Completion sounds'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(from), findsOneWidget);
    }

    testWidgets('active Arc: Today, beside Reminders; the History tab', (
      tester,
    ) async {
      await phoneSize(tester);
      final app = await activeArc();
      addTearDown(app.db.close);
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      // Beside Reminders in the header.
      final reminders = tester.getCenter(find.byTooltip('Reminders'));
      final sound = tester.getCenter(find.byTooltip(SoundCopy.title));
      expect(sound.dy, reminders.dy);
      expect((sound.dx - reminders.dx).abs(), lessThanOrEqualTo(56));
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      await openAndBack(tester, TodayScreen);

      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      await openAndBack(tester, ArcHistoryScreen);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('paused Arc: Today, beside Reminders', (tester) async {
      await phoneSize(tester);
      final app = await activeArc();
      addTearDown(app.db.close);
      final arc = (await app.tracking.today()).session;
      await pauseServiceOf(app)
          .pause(sessionId: arc.id, frozenFrom: app.clock.today().addDays(1));
      app.clock.current = DateTime(2026, 10, 5, 9);
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsNothing);
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      await openAndBack(tester, TodayScreen);
      await shutDown(tester);
    });

    testWidgets('saved setup: the hub', (tester) async {
      await phoneSize(tester);
      final app = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 10, 4, 9)),
      );
      addTearDown(app.db.close);
      await app.winterArc.beginSetup();
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SavedSetupScreen), findsOneWidget);
      await tapShown(tester, find.text('Sound & Feedback'));
      await openAndBack(tester, SavedSetupScreen);
      await shutDown(tester);
    });

    testWidgets('completed history: Arc History, and About from the summary', (
      tester,
    ) async {
      await phoneSize(tester);
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await runFirstArc(app);
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);
      await tapShown(tester, find.text('Arc History'));
      expect(find.byType(ArcHistoryScreen), findsOneWidget);
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      await openAndBack(tester, ArcHistoryScreen);
      await tester.tap(find.byTooltip('About NextRep'));
      await tester.pumpAndSettle();
      await tapShown(tester, find.text('Sound & Feedback'));
      await openAndBack(tester, AboutScreen);
      expect(player.plays, isEmpty);
      await shutDown(tester);
    });

    testWidgets('no Arc: About from onboarding', (tester) async {
      await phoneSize(tester);
      final app = TestApp(
        memoryDatabase(),
        FakeClock(DateTime(2026, 10, 4, 9)),
      );
      addTearDown(app.db.close);
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await tapShown(tester, find.text('About NextRep'));
      await tapShown(tester, find.text('Sound & Feedback'));
      expect(find.byType(SoundSettingsScreen), findsOneWidget);
      // Works without an Arc: change and store.
      await tap(tester, sw());
      expect((await stored(app)).soundsEnabled, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      await shutDown(tester);
    });
  });

  group('accessibility and layout', () {
    Future<void> pumpAt(
      WidgetTester tester,
      TestApp app,
      Size size,
      double textScale,
    ) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        soundApp(app, player: player, monotonic: monotonic),
      );
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      await tester.tap(find.byTooltip(SoundCopy.title));
      await tester.pumpAndSettle();
      expect(find.byType(SoundSettingsScreen), findsOneWidget);
    }

    final layouts = <String, (Size, double)>{
      '360×800 at 1×': (const Size(360, 800), 1),
      '360×800 at 2×': (const Size(360, 800), 2),
      '320×568 at 1.5×': (const Size(320, 568), 1.5),
      'landscape 800×360 at 1.3×': (const Size(800, 360), 1.3),
      'landscape 568×320 at 1×': (const Size(568, 320), 1),
      'tablet 1280×800 at 1×': (const Size(1280, 800), 1),
    };
    for (final MapEntry(key: name, value: (size, scale)) in layouts.entries) {
      testWidgets('$name: no overflow, nothing wider than 600 dp, every '
          'control reachable', (tester) async {
        final app = await activeArc();
        addTearDown(app.db.close);
        await pumpAt(tester, app, size, scale);
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(RadioGroup<SoundTheme>));
        expect(card.width, lessThanOrEqualTo(600));
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(size.width));
        for (final t in SoundTheme.values) {
          await tester.ensureVisible(preview(t));
          await tester.pumpAndSettle();
          final button = tester.getRect(preview(t));
          expect(button.right, lessThanOrEqualTo(size.width));
          final title = tester.getRect(find.text(SoundCopy.name(t)));
          if (scale > 1.3) {
            expect(
              button.top,
              greaterThanOrEqualTo(title.bottom - 1),
              reason: 'above 1.3× the preview moves under the name',
            );
          } else {
            expect(
              button.center.dy,
              closeTo(title.center.dy, 24),
              reason: 'beside the name',
            );
          }
        }
        await tester.ensureVisible(find.textContaining('Sounds follow'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await shutDown(tester);
      });
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('guidelines at ${scale}x: 48 dp targets, labels, contrast; '
          'switch and radio group labelled; previews named', (tester) async {
        final app = await activeArc();
        addTearDown(app.db.close);
        final handle = tester.ensureSemantics();
        await pumpAt(tester, app, const Size(360, 800), scale);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(
          find.bySemanticsLabel(RegExp('^Completion sounds')),
          findsOneWidget,
        );
        for (final t in SoundTheme.values) {
          expect(
            find.bySemanticsLabel('Play ${SoundCopy.name(t)}'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel(SoundCopy.name(t)), findsOneWidget);
        }
        final group = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == SoundCopy.heading,
        );
        expect(group, findsOneWidget);
        // Sounds off: the reason is on screen, and the dimmed controls are
        // marked disabled (exempt from contrast, still announced).
        await tester.tap(sw());
        await tester.pumpAndSettle();
        expect(find.text('Turn on sounds to choose one.'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await shutDown(tester);
      });
    }
  });
}
