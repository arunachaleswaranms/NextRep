import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/app/router/app_router.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/winter_arc/current_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_service.dart';
import 'package:nextrep/domain/winter_arc/winter_arc_session.dart';

import '../support/fakes.dart';

WinterArcSession _arc(int id, WinterArcStatus status) => WinterArcSession(
  id: id,
  kind: ArcKind.rolling92,
  participationStartDate: status == WinterArcStatus.setup
      ? null
      : LocalDate(2026, 10, 1),
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

    test('a Hydration Coach nudge opens Today of the active arc', () {
      expect(AppRoutes.forReminder('hydration', active), AppRoutes.today);
      expect(AppRoutes.forReminder('hydration', completed), AppRoutes.arc(1));
      expect(
        AppRoutes.forReminder('hydration', setupOnly),
        AppRoutes.savedSetup,
      );
    });

    test('a Focus Guard nudge opens Today, or home without an active arc; '
        'Focus Guard settings are reachable in every state', () {
      expect(
        AppRoutes.forReminder(focusGuardTapPayload, active),
        AppRoutes.today,
      );
      expect(
        AppRoutes.forReminder(focusGuardTapPayload, completed),
        AppRoutes.arc(1),
      );
      expect(
        AppRoutes.forReminder(focusGuardTapPayload, setupOnly),
        AppRoutes.savedSetup,
      );
      expect(
        AppRoutes.forReminder(focusGuardTapPayload, none),
        AppRoutes.onboarding,
      );
      for (final resolution in [active, completed, setupOnly, none]) {
        expect(AppRoutes.redirect(resolution, AppRoutes.focusGuard), isNull);
        expect(
          AppRoutes.redirect(resolution, AppRoutes.focusGuardApps),
          isNull,
        );
      }
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
      expect(AppRoutes.forReminder('today', setupOnly), AppRoutes.savedSetup);
      expect(
        AppRoutes.forReminder('journal', completedPlusSetup),
        AppRoutes.savedSetup,
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
          AppRoutes.savedSetup,
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
        AppRoutes.savedSetup,
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

  group('Weekly Review (Phase 12B)', () {
    test('locations always carry the week', () {
      expect(AppRoutes.activeReview(3), '/journey/review?week=3');
      expect(AppRoutes.arcReview(7, 13), '/arc/7/review?week=13');
    });

    test(
      'the active review needs an active arc; existing guards unchanged',
      () {
        final review = AppRoutes.activeReview(2);
        expect(AppRoutes.redirect(active, review), isNull);
        expect(AppRoutes.redirect(completed, review), AppRoutes.arc(1));
        expect(
          AppRoutes.redirect(completedPlusSetup, review),
          AppRoutes.savedSetup,
        );
        expect(AppRoutes.redirect(setupOnly, review), AppRoutes.savedSetup);
        expect(AppRoutes.redirect(none, review), AppRoutes.onboarding);
      },
    );

    test('a finished arc\'s review is history bound to its id; the current '
        'arc is never shown as history', () {
      expect(AppRoutes.redirect(active, AppRoutes.arcReview(1, 13)), isNull);
      expect(AppRoutes.redirect(completed, AppRoutes.arcReview(1, 13)), isNull);
      expect(
        AppRoutes.redirect(active, AppRoutes.arcReview(2, 1)),
        AppRoutes.today,
      );
      expect(
        AppRoutes.redirect(completedPlusSetup, AppRoutes.arcReview(2, 1)),
        AppRoutes.savedSetup,
      );
      final ended = ArcResolution(
        latestCompleted: _arc(1, WinterArcStatus.ended),
      );
      expect(AppRoutes.redirect(ended, AppRoutes.arcReview(1, 2)), isNull);
      expect(
        AppRoutes.redirect(completed, '/arc/oops/review?week=1'),
        AppRoutes.arc(1),
      );
    });

    test('the week query: digits only, one or two of them; anything else is '
        'missing (the review then picks its default)', () {
      int? week(String query) =>
          AppRoutes.reviewWeekOf(Uri.parse('/journey/review$query'));
      expect(week('?week=1'), 1);
      expect(week('?week=13'), 13);
      expect(week('?week=01'), 1);
      expect(week('?week=0'), 0); // out of range: settled by the review
      expect(week('?week=99'), 99);
      for (final bad in [
        '',
        '?week=',
        '?week=abc',
        '?week=-1',
        '?week=+1',
        '?week=1.0',
        '?week=0x1',
        '?week=123',
        '?week=%20',
        '?week=%201',
        "?week=1'%20OR%201=1",
        '?week=99999999999999999999',
        '?other=3',
      ]) {
        expect(week(bad), isNull, reason: bad);
      }
      expect(
        AppRoutes.reviewWeekOf(Uri(path: '/journey/review', query: 'week=%zz')),
        isNull,
      );
    });
  });

  group('About', () {
    test('is reachable in every state and never redirected', () {
      for (final resolution in [
        none,
        setupOnly,
        active,
        completed,
        completedPlusSetup,
      ]) {
        expect(AppRoutes.redirect(resolution, AppRoutes.about), isNull);
      }
      expect(AppRoutes.redirect(null, AppRoutes.about), isNull);
      expect(AppRoutes.about, '/settings/about');
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
      expect(await boot(app, 'journal'), AppRoutes.savedSetup);
    });
  });

  group('saved setup (Phase 12D)', () {
    final endedPlusSetup = ArcResolution(
      current: _arc(2, WinterArcStatus.setup),
      latestCompleted: _arc(1, WinterArcStatus.ended),
    );
    const setupRoutes = [
      AppRoutes.savedSetup,
      AppRoutes.reviewSetup,
      AppRoutes.confirmStart,
    ];

    test('a setup opens the hub, with or without finished history', () {
      for (final r in [setupOnly, completedPlusSetup, endedPlusSetup]) {
        expect(AppRoutes.home(r), AppRoutes.savedSetup);
        expect(AppRoutes.forSession(r.current), AppRoutes.savedSetup);
      }
      expect(AppRoutes.home(none), AppRoutes.onboarding);
      expect(AppRoutes.home(active), AppRoutes.today);
      expect(AppRoutes.home(completed), AppRoutes.arc(1));
    });

    test('with a setup, every setup screen stays where it is (no loop '
        'between the editor and the hub)', () {
      for (final r in [setupOnly, completedPlusSetup, endedPlusSetup]) {
        for (final location in [AppRoutes.habitSetup, ...setupRoutes]) {
          expect(AppRoutes.redirect(r, location), isNull, reason: location);
        }
        // Settings and history stay reachable from the hub.
        for (final location in [
          AppRoutes.reminders,
          AppRoutes.dataBackup,
          AppRoutes.focusGuard,
          AppRoutes.about,
          AppRoutes.arcs,
        ]) {
          expect(AppRoutes.redirect(r, location), isNull, reason: location);
        }
      }
    });

    test('choosing an Arc still opens the editor, not the hub', () {
      expect(
        AppRoutes.redirect(setupOnly, AppRoutes.newArc),
        AppRoutes.habitSetup,
      );
      expect(
        AppRoutes.redirect(setupOnly, AppRoutes.onboarding),
        AppRoutes.habitSetup,
      );
    });

    test('an active arc leaves every setup screen for Today', () {
      for (final location in [AppRoutes.habitSetup, ...setupRoutes]) {
        expect(AppRoutes.redirect(active, location), AppRoutes.today);
      }
    });

    test('without a setup, the hub, Review and Confirm go home', () {
      for (final location in setupRoutes) {
        expect(AppRoutes.redirect(none, location), AppRoutes.onboarding);
        expect(AppRoutes.redirect(completed, location), AppRoutes.arc(1));
      }
      // The redirect target never redirects again.
      for (final r in [
        none,
        completed,
        active,
        setupOnly,
        completedPlusSetup,
      ]) {
        final home = AppRoutes.home(r);
        expect(AppRoutes.redirect(r, home), isNull, reason: home);
      }
    });

    test('a stale reminder with a setup opens the hub, never Today', () {
      for (final payload in ['today', 'journal', 'hydration', null]) {
        expect(AppRoutes.forReminder(payload, setupOnly), AppRoutes.savedSetup);
      }
      expect(AppRoutes.reviewFromEditor, '/setup/review?from=editor');
    });
  });
}
