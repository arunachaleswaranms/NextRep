import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/app/app.dart';
import 'package:nextrep/app/dependencies.dart';
import 'package:nextrep/core/database/app_database.dart';
import 'package:nextrep/core/errors/app_failure.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/data/drift_progress_repository.dart';
import 'package:nextrep/domain/progress/arc_history.dart';
import 'package:nextrep/domain/progress/daily_habit_progress.dart';
import 'package:nextrep/domain/progress/progress_repository.dart';
import 'package:nextrep/features/habit_setup/widgets/habit_toggle_tile.dart';

import '../support/fakes.dart';
import '../support/ui.dart';

Widget _app(AppDatabase db, FakeClock clock, {List overrides = const []}) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        ambientMotionProvider.overrideWithValue(false),
        ...overrides,
      ],
      retry: (_, _) => null,
      child: const NextRepApp(),
    );

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Unmounts the app and lets pending snackbar timers expire.
Future<void> _shutDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> _onboardAndStart(WidgetTester tester) async {
  await tester.tap(find.text("Let's Begin"));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rolling 92-Day Arc'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start Winter Arc'));
  await tester.pumpAndSettle();
}

void main() {
  final clock = FakeClock(DateTime(2026, 10, 1, 9));

  testWidgets('Day 1: onboarding → setup → today → complete → relaunch', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final dir = Directory.systemTemp.createTempSync('nextrep_widget_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/nextrep.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();

    // Onboarding
    expect(find.text('WINTER ARC'), findsOneWidget);
    expect(find.text('92 days to a better you.'), findsOneWidget);
    await tester.tap(find.text("Let's Begin"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rolling 92-Day Arc'));
    await tester.pumpAndSettle();

    // Habit setup: turn off Learning, turn on English Practice.
    expect(find.text('Choose your habits'), findsOneWidget);
    expect(find.text('4 habits selected'), findsOneWidget);
    Finder switchOf(String title) => find.descendant(
      of: find.widgetWithText(HabitToggleTile, title),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(switchOf('Learning / Skills'), 100);
    await tester.ensureVisible(switchOf('Learning / Skills'));
    await tester.pumpAndSettle();
    await tester.tap(switchOf('Learning / Skills'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(switchOf('English Practice'), 100);
    await tester.ensureVisible(switchOf('English Practice'));
    await tester.pumpAndSettle();
    await tester.tap(switchOf('English Practice'));
    await tester.pumpAndSettle();
    expect(find.text('4 habits selected'), findsOneWidget);

    await tester.tap(find.text('Start Winter Arc'));
    await tester.pumpAndSettle();

    // Today
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('Thursday, 1 October'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 of 4 done'), findsOneWidget);
    expect(find.text('Learning / Skills'), findsNothing);
    expect(find.text('English Practice'), findsOneWidget);

    // Complete a binary habit; double tap must not double count.
    // Both taps hit the same widget before any rebuild.
    final complete = find.byTooltip('Complete No Junk Food');
    await reveal(tester, complete);
    await tester.tap(complete);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('1 of 4 done'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    expect(find.text('No Junk Food complete · +15 XP'), findsOneWidget);

    // Rapid increments on a count habit are each applied once.
    final addWater = find.byTooltip('Add to Water Intake');
    await reveal(tester, addWater); // after the First Rep card times out
    await tester.tap(addWater);
    await tester.tap(addWater);
    await tester.tap(addWater);
    await tester.pumpAndSettle();
    expect(find.text('3 / 8 glasses'), findsOneWidget);

    // Relaunch: new connection on the same file, fresh provider container.
    await _shutDown(tester);
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();

    expect(find.text("Let's Begin"), findsNothing);
    expect(find.text('Day 1 of 92'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    await reveal(tester, find.byTooltip('Undo No Junk Food'));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('3 / 8 glasses'), findsOneWidget);
    expect(find.text('15 XP'), findsOneWidget);
    expect(find.byTooltip('Undo No Junk Food'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('snackbar Undo reverts the completion and its XP', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(_app(db, clock));
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();
    expect(find.text('15 XP'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 XP'), findsOneWidget);
    expect(find.byTooltip('Complete No Junk Food'), findsOneWidget);
    await _shutDown(tester);
  });

  testWidgets('a storage failure is shown and nothing changes', (tester) async {
    await _setPhoneSize(tester);
    final db = memoryDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      _app(
        db,
        clock,
        overrides: [
          progressRepositoryProvider.overrideWithValue(
            _FailingWrites(DriftProgressRepository(db, clock)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _onboardAndStart(tester);

    await reveal(tester, find.byTooltip('Complete No Junk Food'));
    await tester.tap(find.byTooltip('Complete No Junk Food'));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't save or load your progress. Please try again."),
      findsOneWidget,
    );
    expect(find.text('0%'), findsOneWidget);
    expect(find.byTooltip('Complete No Junk Food'), findsOneWidget);
    await _shutDown(tester);
  });
}

/// Reads work; every write fails like a full or corrupted disk would.
final class _FailingWrites implements ProgressRepository {
  _FailingWrites(this._inner);

  final ProgressRepository _inner;

  @override
  Future<List<DailyHabitProgress>> progressOn(int sessionId, LocalDate date) =>
      _inner.progressOn(sessionId, date);

  @override
  Future<int> totalXp(int sessionId) => _inner.totalXp(sessionId);

  @override
  Future<ArcRecords> loadArc(int sessionId) => _inner.loadArc(sessionId);

  @override
  Future<DayCommit<T>> commitDay<T>({
    required int sessionId,
    required LocalDate date,
    required DayCommitBuilder<T> build,
  }) async => throw const PersistenceFailure('disk I/O error (simulated)');
}
