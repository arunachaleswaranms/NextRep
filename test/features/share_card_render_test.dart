import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/theme/winter_theme.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_catalog.dart';
import 'package:nextrep/domain/progress/day_mode.dart';
import 'package:nextrep/features/share/share_card_capture.dart';
import 'package:nextrep/features/share/share_card_data.dart';
import 'package:nextrep/features/share/widgets/share_cards.dart';

import '../support/share_fixtures.dart';

/// Phase 10B: every share card renders to a valid 1080 x 1350 PNG without
/// overflow, whatever the device, and the PNG is the card alone.

final _longTitle = 'An extremely long custom habit title ${'x' * 3}';

/// Pumps [card] the way the preview does (scaled into the screen) and
/// returns its PNG.
Future<Uint8List> _render(
  WidgetTester tester,
  Widget card, {
  bool banner = true,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWinterTheme(),
      debugShowCheckedModeBanner: banner,
      home: Scaffold(
        appBar: AppBar(title: const Text('Preview chrome')),
        body: Center(
          child: SizedBox(
            width: 200,
            height: 250,
            child: FittedBox(
              child: RepaintBoundary(key: key, child: card),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull, reason: 'no overflow');
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  expect(boundary.size, ShareCardCapture.canvas);
  return (await tester.runAsync(() => ShareCardCapture.png(boundary)))!;
}

void _expect1080x1350(Uint8List png) {
  expect(pngSize(png), (width: 1080, height: 1350));
}

Widget _today({
  int count = 7,
  String? customTitle,
  DayMode mode = DayMode.normal,
  SharePrivacyOptions privacy = const SharePrivacyOptions(),
  bool seasonal = false,
}) {
  final habits = catalogHabits(count: count, customTitle: customTitle);
  return TodayShareCard(
    data: TodayShareCardData.fromSummary(
      shareSummary(
        habits: habits,
        done: {for (final h in habits.take(count ~/ 2)) h.id},
        mode: mode,
        xp: 1080,
        streakDays: 3,
        session: seasonal ? seasonalSession(joinDay: 15) : null,
        today: seasonal ? 30 : 24,
      ),
      privacy: privacy,
    ),
  );
}

Widget _arc({int count = 8, String? customTitle, bool seasonal = false}) =>
    ArcShareCard(
      data: ArcShareCardData.fromSummary(
        shareSummary(
          habits: catalogHabits(count: count, customTitle: customTitle),
          session: seasonal ? seasonalSession(joinDay: 15) : null,
          today: seasonal ? 30 : 24,
        ),
      ),
    );

void main() {
  final cases = <String, Widget Function()>{
    "Today's Progress, 12 habits": () => _today(count: 12),
    "Today's Progress, 12 long names": () =>
        _today(count: 12, customTitle: _longTitle),
    "Today's Progress, one habit": () => _today(count: 1),
    "Today's Progress, Minimum Day": () => _today(mode: DayMode.minimum),
    "Today's Progress, seasonal": () => _today(seasonal: true),
    "Today's Progress, everything hidden": () => _today(
      count: 12,
      privacy: const SharePrivacyOptions(
        habitNames: false,
        xpAndLevel: false,
        streak: false,
      ),
    ),
    'My Arc, rolling': _arc,
    'My Arc, seasonal joined late': () => _arc(seasonal: true),
    'My Arc, 12 long names': () => _arc(count: 12, customTitle: _longTitle),
    'My Arc, one habit': () => _arc(count: 1),
  };
  for (final MapEntry(key: name, value: card) in cases.entries) {
    testWidgets('$name renders a 1080 x 1350 PNG', (tester) async {
      _expect1080x1350(await _render(tester, card()));
    });
  }

  testWidgets('every achievement renders a 1080 x 1350 PNG', (tester) async {
    for (final definition in AchievementCatalog.all) {
      final png = await _render(
        tester,
        AchievementShareCard(
          data: AchievementShareCardData(
            key: definition.key,
            title: definition.title,
            description: definition.description,
            dayNumber: 92,
          ),
        ),
      );
      _expect1080x1350(png);
    }
  });

  testWidgets('the export is independent of screen size, pixel density, '
      'text scale and app chrome', (tester) async {
    final card = _today(count: 12, customTitle: _longTitle);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final phone = await _render(tester, card);

    tester.view.physicalSize = const Size(1600, 2560);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tablet = await _render(tester, card, banner: false);

    _expect1080x1350(phone);
    expect(tablet, phone, reason: 'byte-identical images');
  });

  testWidgets('the card shows the habit names and nothing private', (
    tester,
  ) async {
    await _render(tester, _today(count: 6));
    expect(find.text('Sleep Before Target'), findsOneWidget);
    expect(find.textContaining(loggedBedtime.hhmm), findsNothing);
    expect(find.textContaining('23:30'), findsNothing);
    expect(find.text('github.com/arunachaleswaranms/NextRep'), findsOneWidget);
    expect(find.text('Made with NextRep'), findsOneWidget);
  });

  testWidgets('with habit names hidden, no habit title is rendered', (
    tester,
  ) async {
    await _render(
      tester,
      _today(count: 12, privacy: const SharePrivacyOptions(habitNames: false)),
    );
    for (final habit in catalogHabits(count: 12)) {
      expect(find.textContaining(habit.title), findsNothing);
    }
    expect(find.text('6 of 12 habits complete'), findsOneWidget);
  });

  testWidgets('a Minimum Day says so and never says Perfect Day', (
    tester,
  ) async {
    final habits = catalogHabits(count: 4);
    await _render(
      tester,
      TodayShareCard(
        data: TodayShareCardData.fromSummary(
          shareSummary(
            habits: habits,
            done: {for (final h in habits) h.id},
            mode: DayMode.minimum,
          ),
        ),
      ),
    );
    expect(find.text('MINIMUM DAY'), findsOneWidget);
    expect(find.text('PERFECT DAY'), findsNothing);
  });

  testWidgets('My Arc never shows Minimum Day targets', (tester) async {
    await _render(
      tester,
      ArcShareCard(
        data: ArcShareCardData.fromSummary(
          shareSummary(habits: catalogHabits(count: 2), mode: DayMode.minimum),
        ),
      ),
    );
    expect(find.text('8 glasses'), findsOneWidget);
    expect(find.text('3 glasses'), findsNothing);
    expect(find.text('DAY 1'), findsOneWidget);
  });

  testWidgets('the achievement card shows its unlock day, not a date', (
    tester,
  ) async {
    await _render(
      tester,
      AchievementShareCard(
        data: AchievementShareCardData(
          key: AchievementKey.streak7,
          title: 'Cold Front',
          description: 'Reach a 7-day streak on any habit.',
          dayNumber: 12,
        ),
      ),
    );
    expect(find.text('COLD FRONT'), findsOneWidget);
    expect(find.text('UNLOCKED · DAY 12'), findsOneWidget);
  });
}
