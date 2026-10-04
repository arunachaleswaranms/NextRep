import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app_restart.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/app_info.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';

WinterArcSession _arc(int id, WinterArcStatus status) => WinterArcSession(
  id: id,
  startDate: LocalDate(2026, 10, 1),
  endDate: LocalDate(2026, 12, 31),
  status: status,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  final states = {
    'no arc': const ArcResolution(),
    'setup': ArcResolution(current: _arc(1, WinterArcStatus.setup)),
    'active': ArcResolution(
      current: _arc(2, WinterArcStatus.active),
      latestCompleted: _arc(1, WinterArcStatus.completed),
    ),
    'completed': ArcResolution(
      latestCompleted: _arc(1, WinterArcStatus.completed),
    ),
  };

  test('Data & Backup and Insights are reachable in every state', () {
    for (final MapEntry(key: name, value: resolution) in states.entries) {
      expect(
        AppRoutes.redirect(resolution, AppRoutes.dataBackup),
        isNull,
        reason: name,
      );
      expect(
        AppRoutes.redirect(resolution, AppRoutes.insights),
        isNull,
        reason: name,
      );
    }
  });

  test('the reminder that cold-started the app is not reused after a '
      'restart', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 10, 4, 9));
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        reminderLaunchPayloadProvider.overrideWithValue('journal'),
      ],
    );
    addTearDown(container.dispose);
    final services = TestApp(db, clock);
    await services.winterArc.beginSetup();
    await services.winterArc.startWinterArc();

    final sub = container.listen(bootLocationProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      await container.read(bootLocationProvider.future),
      AppRoutes.journal,
    );
    container.read(appEpochProvider.notifier).restart();
    expect(await container.read(bootLocationProvider.future), AppRoutes.today);
  });

  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
