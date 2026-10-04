import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
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
  final none = const ArcResolution();
  final setupOnly = ArcResolution(current: _arc(1, WinterArcStatus.setup));
  final active = ArcResolution(
    current: _arc(2, WinterArcStatus.active),
    latestCompleted: _arc(1, WinterArcStatus.completed),
  );
  final completed = ArcResolution(
    latestCompleted: _arc(1, WinterArcStatus.completed),
  );
  final completedPlusSetup = ArcResolution(
    current: _arc(2, WinterArcStatus.setup),
    latestCompleted: _arc(1, WinterArcStatus.completed),
  );

  group('reminder deep links', () {
    test('the daily reminder opens Today of the active arc', () {
      expect(AppRoutes.forReminder('today', active), AppRoutes.today);
    });

    test('the reflection reminder opens the Journal', () {
      expect(AppRoutes.forReminder('journal', active), AppRoutes.journal);
    });

    test('an unknown payload falls back to Today', () {
      expect(AppRoutes.forReminder('nope', active), AppRoutes.today);
      expect(AppRoutes.forReminder(null, active), AppRoutes.today);
    });

    test('a stale reminder after the arc completed opens its summary', () {
      expect(AppRoutes.forReminder('today', completed), AppRoutes.arc(1));
      expect(AppRoutes.forReminder('journal', completed), AppRoutes.arc(1));
    });

    test('a setup arc never opens a writable Today', () {
      expect(AppRoutes.forReminder('today', setupOnly), AppRoutes.habitSetup);
      expect(
        AppRoutes.forReminder('journal', completedPlusSetup),
        AppRoutes.habitSetup,
      );
    });

    test('with no arc at all it opens onboarding', () {
      expect(AppRoutes.forReminder('today', none), AppRoutes.onboarding);
    });
  });

  group('redirect', () {
    test('active-arc screens need an active arc', () {
      for (final location in [
        AppRoutes.today,
        AppRoutes.habits,
        AppRoutes.journey,
        AppRoutes.journal,
        AppRoutes.history,
        AppRoutes.achievements,
      ]) {
        expect(AppRoutes.redirect(completed, location), AppRoutes.arc(1));
        expect(
          AppRoutes.redirect(completedPlusSetup, location),
          AppRoutes.habitSetup,
        );
        expect(AppRoutes.redirect(active, location), isNull);
      }
    });

    test('setup, onboarding and New Arc are closed while an arc runs', () {
      for (final location in [
        AppRoutes.onboarding,
        AppRoutes.habitSetup,
        AppRoutes.newArc,
      ]) {
        expect(AppRoutes.redirect(active, location), AppRoutes.today);
      }
      expect(AppRoutes.redirect(active, AppRoutes.arcs), AppRoutes.history);
    });

    test('a completed arc stays browsable by id, the current one never is', () {
      expect(AppRoutes.redirect(active, AppRoutes.arc(1)), isNull);
      expect(AppRoutes.redirect(active, AppRoutes.arcJournal(1)), isNull);
      expect(AppRoutes.redirect(active, AppRoutes.arc(2)), AppRoutes.today);
      expect(
        AppRoutes.redirect(active, AppRoutes.arcJourney(2)),
        AppRoutes.today,
      );
      expect(
        AppRoutes.redirect(completedPlusSetup, AppRoutes.arc(2)),
        AppRoutes.habitSetup,
      );
      expect(AppRoutes.redirect(completed, '/arc/oops'), AppRoutes.arc(1));
    });

    test('returning users skip onboarding; New Arc becomes setup', () {
      expect(
        AppRoutes.redirect(completed, AppRoutes.onboarding),
        AppRoutes.arc(1),
      );
      expect(
        AppRoutes.redirect(completed, AppRoutes.habitSetup),
        AppRoutes.arc(1),
      );
      expect(AppRoutes.redirect(completed, AppRoutes.newArc), isNull);
      expect(
        AppRoutes.redirect(completedPlusSetup, AppRoutes.newArc),
        AppRoutes.habitSetup,
      );
      expect(AppRoutes.redirect(none, AppRoutes.onboarding), isNull);
      expect(AppRoutes.redirect(null, AppRoutes.today), isNull);
    });
  });

  group('cold launch from a reminder', () {
    Future<String> boot(TestApp app, String? payload) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(app.db),
          clockProvider.overrideWithValue(app.clock),
          reminderLaunchPayloadProvider.overrideWithValue(payload),
        ],
      );
      addTearDown(container.dispose);
      return container.read(bootLocationProvider.future);
    }

    test('opens the reminder destination for an active arc', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 10, 1)));
      addTearDown(app.db.close);
      await app.winterArc.beginSetup();
      await app.winterArc.startWinterArc();
      expect(await boot(app, 'journal'), AppRoutes.journal);
      expect(await boot(app, 'today'), AppRoutes.today);
      expect(await boot(app, null), AppRoutes.today);
    });

    test('closes out an arc that ended first, then resolves safely', () async {
      final app = TestApp(memoryDatabase(), FakeClock(DateTime(2026, 7, 1)));
      addTearDown(app.db.close);
      await app.winterArc.beginSetup();
      final arc = await app.winterArc.startWinterArc();
      // A daily reminder from Day 92 is tapped on Day 93.
      app.clock.current = DateTime(2026, 10, 1, 8);
      expect(await boot(app, 'today'), AppRoutes.arc(arc.id));
      expect(
        (await app.sessions.sessionById(arc.id))!.status,
        WinterArcStatus.completed,
      );

      await app.winterArc.startNewArc(NewArcBaseline.fresh);
      expect(await boot(app, 'journal'), AppRoutes.habitSetup);
    });
  });
}
