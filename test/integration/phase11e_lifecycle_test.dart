import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/day_change.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_focus_guard_settings_repository.dart';
import 'package:nextrep/data/github_release_feed.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_platform.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_service.dart';
import 'package:nextrep/domain/focus_guard/focus_guard_settings.dart';
import 'package:nextrep/domain/focus_guard/today_usage.dart';
import 'package:nextrep/domain/progress/habit_progress_rules.dart';
import 'package:nextrep/domain/reminder/hydration_planner.dart';
import 'package:nextrep/domain/reminder/reminder_plan.dart';
import 'package:nextrep/domain/reminder/reminder_preferences.dart';
import 'package:nextrep/features/about/about_screen.dart';
import 'package:nextrep/features/backup/data_backup_screen.dart';
import 'package:nextrep/features/focus_guard/focus_guard_card.dart';
import 'package:nextrep/features/summary/summary_screen.dart';
import 'package:nextrep/features/today/today_screen.dart';

import '../support/arcs.dart';
import '../support/fakes.dart';
import '../support/ui.dart';
import '../support/updates.dart';

/// Phase 11E: dates, midnight and the app lifecycle with every v1.2
/// feature on at once: the daily and evening reminders, Hydration Coach,
/// Focus Guard, and an About screen whose update check is wired to a
/// counting fake GitHub. The whole app runs over the real services and
/// Drift; only the platform (notifications, Usage Access, WorkManager,
/// GitHub, files) is faked.
const _video = 'org.example.video';
const _chat = 'org.example.chat';

/// A stream that knows how many listeners it has right now, to prove the
/// app never keeps a second tap handler (e.g. after a restore restarts it).
final class _CountedStream<T> extends Stream<T> {
  _CountedStream(this._source);

  final Stream<T> _source;
  int active = 0;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    active++;
    return _CountedSubscription(
      _source.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      () => active--,
    );
  }
}

final class _CountedSubscription<T> implements StreamSubscription<T> {
  _CountedSubscription(this._inner, this._onCancel);

  final StreamSubscription<T> _inner;
  final void Function() _onCancel;
  var _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
    return _inner.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

final class _Harness {
  _Harness(this.db, this.clock);

  final AppDatabase db;
  final FakeClock clock;
  late final app = TestApp(db, clock, scheduler: scheduler);
  final scheduler = FakeReminderScheduler(granted: true);
  final platform = FakeFocusGuardPlatform(
    access: UsageAccess.granted,
    apps: const [
      LaunchableAppCandidate(packageName: _video, label: 'Video Stream'),
      LaunchableAppCandidate(packageName: _chat, label: 'Chat Hub'),
    ],
  );
  final background = FakeFocusGuardBackgroundScheduler();
  final github = FakeGitHubClient(
    () async => githubResponse(200, json: releaseJson(tag: 'v1.1.0')),
  );
  final taps = StreamController<String?>.broadcast();
  late final countedTaps = _CountedStream(taps.stream);
  final files = FakeBackupFiles();

  Widget appWidget() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(clock),
      ambientMotionProvider.overrideWithValue(false),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      reminderTapsProvider.overrideWithValue(countedTaps),
      focusGuardPlatformProvider.overrideWithValue(platform),
      focusGuardSchedulerProvider.overrideWithValue(background),
      releaseFeedProvider.overrideWithValue(
        GitHubReleaseFeed(client: () => github),
      ),
      installedAppSourceProvider.overrideWithValue(FakeInstalledAppSource()),
      externalLinksProvider.overrideWithValue(FakeExternalLinks()),
      backupFilesProvider.overrideWithValue(files),
    ],
    retry: (_, _) => null,
    child: const NextRepApp(),
  );

  /// An active rolling Arc started on [start] (09:00) with the starter
  /// habits, and every reminder family and Focus Guard on.
  Future<void> seed(DateTime start) async {
    clock.current = DateTime(start.year, start.month, start.day, 9);
    await app.winterArc.beginSetup();
    await app.winterArc.startWinterArc();
    await app.reminders.update(
      (p) => p.copyWith(
        dailyEnabled: true,
        reflectionEnabled: true,
        hydrationEnabled: true,
      ),
    );
    await DriftFocusGuardSettingsRepository(db).save(
      const FocusGuardSettings(
        enabled: true,
        dailyBudgetMinutes: 60,
        selectedPackages: [_video, _chat],
      ),
      at: clock.now(),
    );
  }

  List<PlannedReminder> get hydration => [
    for (final r in scheduler.pending)
      if (r.kind == ReminderKind.hydration) r,
  ];

  /// Every pending reminder belongs to [today] or later, and each id is
  /// used once.
  void expectPlannedFrom(LocalDate today) {
    final ids = [for (final r in scheduler.pending) r.id];
    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate ids');
    for (final r in scheduler.pending) {
      expect(
        LocalDate.fromDateTime(r.at).isBefore(today),
        isFalse,
        reason: '$r is before $today',
      );
      expect(r.at.isAfter(clock.now()), isTrue, reason: '$r already passed');
    }
    // Today's hydration nudges are 300..304, tomorrow's 310..314, …
    for (final r in hydration) {
      final offset = today.daysUntil(LocalDate.fromDateTime(r.at));
      expect(r.id ~/ 10, 30 + offset, reason: '$r');
    }
  }
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await clearCelebrations(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pause(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) => _tap(
  tester,
  find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
);

void main() {
  late _Harness h;

  setUp(() {
    final db = memoryDatabase();
    addTearDown(db.close);
    h = _Harness(db, FakeClock(DateTime(2026, 10, 1)));
    addTearDown(h.taps.close);
  });

  testWidgets('local midnight with the app open: Today, Hydration Coach, '
      'the reminders, Focus Guard and the Journal all move to the new day; '
      'nothing reaches the network', (tester) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    await h.app.tracking.perform(
      habitId: 'water',
      action: HabitAction.increment,
      date: h.clock.today(),
    );
    h.platform.usage = const {_video: Duration(minutes: 70)};
    h.clock.current = DateTime(2026, 10, 1, 23, 59, 50);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    h.expectPlannedFrom(LocalDate(2026, 10, 1));
    expect(h.hydration.where((r) => r.id < 310), isEmpty, reason: 'past 20:00');
    final day1Rows = await snapshotOf(h.db, 1);
    final reconcilesBefore = h.scheduler.scheduleCalls;

    // Midnight passes while NextRep stays on screen.
    h.platform.usage = const {};
    h.clock.current = DateTime(2026, 10, 2, 0, 0, 2);
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);

    expect(find.text('Day 2 of 92'), findsOneWidget);
    expect(h.scheduler.scheduleCalls, greaterThan(reconcilesBefore));
    h.expectPlannedFrom(LocalDate(2026, 10, 2));
    // Day 2's hydration plan starts from no Water: all four nudges, ids
    // 300..303 now meaning 2 Oct.
    expect(
      [
        for (final r in h.hydration)
          if (LocalDate.fromDateTime(r.at) == LocalDate(2026, 10, 2)) r.id,
      ],
      [300, 301, 302, 303],
    );
    final daily = h.scheduler.pending.firstWhere((r) => r.id == 100);
    expect(daily.title, 'Winter Arc · Day 2');
    // Focus Guard measures the new day from its local midnight.
    await reveal(tester, find.byType(FocusGuardCard));
    expect(h.platform.queries.last.from, DateTime(2026, 10, 2));
    expect(find.textContaining('0 / 60 min'), findsOneWidget);
    // The rollover itself writes nothing: Day 1 is as it was.
    expect(await snapshotOf(h.db, 1), day1Rows);

    await _openTab(tester, 'Journal');
    expect(find.text('TODAY · DAY 2'), findsOneWidget);
    expect(h.github.requests, isEmpty);
    await _shutDown(tester);
  });

  testWidgets('a day change while backgrounded, then process death: the '
      'resume and the relaunch plan the new day once, without duplicates, '
      'and keep a single tap handler', (tester) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    h.clock.current = DateTime(2026, 10, 1, 21);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(h.countedTaps.active, 1);

    await _pause(tester);
    h.clock.current = DateTime(2026, 10, 2, 9, 30);
    final checks = h.background.scheduleCalls;
    final reconciles = h.scheduler.scheduleCalls;
    await _resume(tester);
    await clearCelebrations(tester);
    expect(find.text('Day 2 of 92'), findsOneWidget);
    h.expectPlannedFrom(LocalDate(2026, 10, 2));
    expect(h.scheduler.scheduleCalls, reconciles + 1, reason: 'one re-plan');
    expect(h.background.scheduleCalls, checks + 1, reason: 'KEEP: one call');
    final afterResume = h.scheduler.pending;

    // The process dies and NextRep is opened again later the same day.
    await _shutDown(tester);
    expect(h.countedTaps.active, 0);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 2 of 92'), findsOneWidget);
    expect(h.countedTaps.active, 1);
    expect(
      [for (final r in h.scheduler.pending) (r.id, r.at, r.title)],
      [for (final r in afterResume) (r.id, r.at, r.title)],
    );
    expect(h.background.scheduled, isTrue);
    expect(h.github.requests, isEmpty);
    await _shutDown(tester);
  });

  testWidgets('Day 92 → Day 93 at midnight with everything on: the Arc '
      'closes, its reminders stop, Focus Guard stays on, stale taps land on '
      'the summary, and About still works offline until tapped', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    h.clock.current = DateTime(2026, 12, 31, 20, 30);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 92 of 92'), findsOneWidget);
    // Only Day 92's evening reflection is still ahead; nothing is planned
    // past the Arc's last day.
    expect(
      [for (final r in h.scheduler.pending) (r.id, r.title)],
      [(200, 'How did today go?')],
    );

    h.clock.current = DateTime(2027, 1, 1, 0, 0, 2);
    await tester.pump(const Duration(hours: 4));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);

    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);
    expect(h.scheduler.pending, isEmpty, reason: 'nothing after Day 92');
    final arc = (await h.app.sessions.sessionById(1))!;
    expect(arc.status.name, 'completed');
    // Focus Guard is app-level: still on and still checking.
    expect(
      (await DriftFocusGuardSettingsRepository(h.db).load()).enabled,
      isTrue,
    );
    expect(h.background.scheduled, isTrue);

    // Stale taps from before the close: the read-only summary, never a
    // writable Today.
    for (final payload in ['hydration', focusGuardTapPayload, 'journal']) {
      h.taps.add(payload);
      await tester.pumpAndSettle();
      await clearCelebrations(tester);
      expect(find.byType(SummaryScreen), findsOneWidget, reason: payload);
      expect(find.byType(TodayScreen), findsNothing, reason: payload);
    }

    await reveal(tester, find.text('About NextRep'));
    await _tap(tester, find.text('About NextRep'));
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Version 1.1.0'), findsOneWidget);
    expect(h.github.requests, isEmpty);
    await _tap(tester, find.text('Check for updates'));
    expect(h.github.requests, hasLength(1));
    expect(
      find.text("You're using the latest published version."),
      findsOneWidget,
    );
    await _shutDown(tester);
  });

  testWidgets('the clock moved back a day while away: Today shows that day, '
      'the later day keeps its data, plans start from the new today, and '
      'nothing breaks', (tester) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    h.clock.current = DateTime(2026, 10, 2, 10);
    for (var i = 0; i < 2; i++) {
      await h.app.tracking.perform(
        habitId: 'water',
        action: HabitAction.increment,
        date: h.clock.today(),
      );
    }
    final before = await snapshotOf(h.db, 1);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.text('Day 2 of 92'), findsOneWidget);

    await _pause(tester);
    h.clock.current = DateTime(2026, 10, 1, 10);
    await _resume(tester);
    await clearCelebrations(tester);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(await snapshotOf(h.db, 1), before, reason: 'nothing rewritten');
    h.expectPlannedFrom(LocalDate(2026, 10, 1));
    expect(h.github.requests, isEmpty);
    await _shutDown(tester);
  });

  testWidgets('a restore from the running app restarts it once: one tap '
      'handler, one reconciliation per resume, opt-in features off, and no '
      'network', (tester) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    h.clock.current = DateTime(2026, 10, 1, 12);
    h.files.toPick = (await h.app.backup.export()).bytes;
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(h.background.scheduled, isTrue);

    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('Data & Backup'));
    expect(find.byType(DataBackupScreen), findsOneWidget);
    await _tap(tester, find.text('Restore Backup'));
    await _tap(
      tester,
      find.ancestor(
        of: find.text('Restore'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    await _tap(tester, find.text('Replace Data'));
    await tester.pumpAndSettle();
    await clearCelebrations(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.textContaining('Backup restored.'), findsOneWidget);

    expect(h.countedTaps.active, 1, reason: 'the old handler was cancelled');
    expect((await h.app.reminderStore.load()).anyEnabled, isFalse);
    expect(h.scheduler.pending, isEmpty);
    expect(
      (await DriftFocusGuardSettingsRepository(h.db).load()).enabled,
      isFalse,
    );
    expect(h.background.scheduled, isFalse);

    // Exactly one reconciliation of each per resume after the restart.
    final reminderCalls = h.scheduler.scheduleCalls + h.scheduler.cancelCalls;
    final focusGuardCalls = h.background.cancelCalls;
    await _pause(tester);
    await _resume(tester);
    expect(
      h.scheduler.scheduleCalls + h.scheduler.cancelCalls,
      reminderCalls + 1,
    );
    expect(h.background.cancelCalls, focusGuardCalls + 1);

    // One tap is handled once.
    h.taps.add('journal');
    await tester.pumpAndSettle();
    expect(find.text('TODAY · DAY 1'), findsOneWidget);
    expect(h.github.requests, isEmpty);
    await _shutDown(tester);
  });

  testWidgets('About open across midnight and a resume: still idle, no '
      'request; one tap sends exactly one', (tester) async {
    await _setPhoneSize(tester);
    await h.seed(DateTime(2026, 10, 1));
    h.clock.current = DateTime(2026, 10, 1, 23, 59, 50);
    await tester.pumpWidget(h.appWidget());
    await tester.pumpAndSettle();
    await _openTab(tester, 'History');
    await _tap(tester, find.byTooltip('About NextRep'));
    expect(find.byType(AboutScreen), findsOneWidget);

    h.clock.current = DateTime(2026, 10, 2, 0, 0, 2);
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    await _pause(tester);
    h.clock.advance(const Duration(hours: 8));
    await _resume(tester);
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Only checks GitHub when you tap.'), findsOneWidget);
    expect(h.github.requests, isEmpty);

    await _tap(tester, find.text('Check for updates'));
    expect(h.github.requests, hasLength(1));
    await _shutDown(tester);
  });

  test('DST and time-zone sensitive dates: Hydration Coach keeps its wall-'
      'clock checkpoints, the midnight ticker and Focus Guard\'s day window '
      'follow the local calendar day (meaningful when run under a DST '
      'zone, e.g. TZ=America/New_York; valid in any zone)', () {
    // Days whose length isn't 24 h in this zone, plus fixed edge dates.
    final dates = <LocalDate>{
      LocalDate(2026, 2, 28),
      LocalDate(2026, 12, 31),
      LocalDate(2028, 2, 29),
    };
    for (
      var d = DateTime(2026, 1, 1);
      d.year < 2028;
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final next = DateTime(d.year, d.month, d.day + 1);
      if (next.difference(d) != const Duration(days: 1)) {
        dates.add(LocalDate.fromDateTime(d));
      }
    }
    for (final date in dates) {
      final midnight = DateTime(date.year, date.month, date.day);
      final nextMidnight = DateTime(date.year, date.month, date.day + 1);

      // Focus Guard's window starts at this local midnight.
      final window = LocalDayWindow.endingAt(
        midnight.add(const Duration(hours: 13)),
      );
      expect(window.start, midnight, reason: '$date');
      expect(window.day, date, reason: '$date');

      // The ticker aims one second past the next local midnight.
      final eve = nextMidnight.subtract(const Duration(seconds: 10));
      expect(
        eve.add(DayChangeTicker.untilNextDay(eve)),
        nextMidnight.add(const Duration(seconds: 1)),
        reason: '$date',
      );

      // Every checkpoint is on that date, inside the window, in order.
      final checkpoints = HydrationPlanner.checkpointsFor(
        date: date,
        target: 8,
        mode: HydrationMode.supportive,
        window: HydrationWindow.defaults,
      );
      expect(
        [for (final c in checkpoints) c.at],
        [
          for (final c in HydrationPlanner.checkpointsFor(
            date: date,
            target: 8,
            mode: HydrationMode.supportive,
            window: HydrationWindow.defaults,
          ))
            c.at,
        ],
        reason: 'deterministic on $date',
      );
      expect(checkpoints, hasLength(5), reason: '$date');
      for (final c in checkpoints) {
        expect(LocalDate.fromDateTime(c.at), date, reason: '$date $c');
        expect(c.at.hour, inInclusiveRange(8, 19), reason: '$date $c');
      }
      for (var i = 1; i < checkpoints.length; i++) {
        expect(
          checkpoints[i].at.isAfter(checkpoints[i - 1].at),
          isTrue,
          reason: '$date',
        );
      }
    }
  });
}
