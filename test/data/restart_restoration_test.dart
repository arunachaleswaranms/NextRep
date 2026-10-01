import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';
import 'package:nextrep/domain/xp/xp.dart';

import '../support/fakes.dart';

/// Simulates app termination and relaunch by closing the database file and
/// opening a brand-new connection, repositories and services on it.
void main() {
  late Directory dir;
  late File file;
  final clock = FakeClock(DateTime(2026, 10, 1, 8));

  TestApp launch() => TestApp(AppDatabase(NativeDatabase(file)), clock);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nextrep_restart_');
    file = File('${dir.path}/nextrep.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('boot location follows persisted state across restarts', () async {
    var app = launch();
    expect(
      AppRoutes.forSession(await app.winterArc.currentSession()),
      AppRoutes.onboarding,
    );
    await app.winterArc.beginSetup();
    await app.db.close();

    app = launch();
    expect(
      AppRoutes.forSession(await app.winterArc.currentSession()),
      AppRoutes.habitSetup,
    );
    await app.winterArc.startWinterArc();
    await app.db.close();

    app = launch();
    expect(
      AppRoutes.forSession(await app.winterArc.currentSession()),
      AppRoutes.today,
    );
    await app.db.close();
  });

  test(
    'selection, session and completion are restored after restart',
    () async {
      var app = launch();
      await app.winterArc.beginSetup();
      await app.winterArc.setHabitEnabled('english', enabled: true);
      await app.winterArc.setHabitEnabled('learning', enabled: false);
      await app.winterArc.startWinterArc();
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: clock.today(),
      );
      for (var i = 0; i < 3; i++) {
        await app.tracking.perform(
          habitId: 'water',
          action: HabitAction.increment,
          date: clock.today(),
        );
      }
      await app.db.close();

      clock.advance(const Duration(hours: 6)); // relaunch later the same day
      app = launch();
      addTearDown(app.db.close);

      final session = (await app.winterArc.currentSession())!;
      expect(session.status, WinterArcStatus.active);
      expect(session.startDate, LocalDate(2026, 10, 1));
      expect(session.endDate, LocalDate(2026, 12, 31));

      final today = await app.tracking.today();
      final byId = {for (final e in today.entries) e.habit.id: e};
      expect(byId.keys, containsAll(['english', 'no_junk_food', 'water']));
      expect(byId.containsKey('learning'), isFalse);
      expect(byId['no_junk_food']!.progress.completed, isTrue);
      expect(byId['water']!.progress.currentValue, 3);
      expect(today.completion.completed, 1);
      expect(today.totalXp, XpRules.habitCompletion);

      // Completing again after restart is still idempotent.
      await app.tracking.perform(
        habitId: 'no_junk_food',
        action: HabitAction.complete,
        date: clock.today(),
      );
      expect((await app.tracking.today()).totalXp, XpRules.habitCompletion);
    },
  );
}
