import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextrep/core/time/local_date.dart';
import 'package:nextrep/domain/achievement/achievement.dart';
import 'package:nextrep/domain/achievement/achievement_repository.dart';
import 'package:nextrep/features/journey/journey_screen.dart';
import 'package:nextrep/features/journey/widgets/arc_calendar_view.dart';

/// Phase 12C test helpers for the Arc Consistency Calendar in the real
/// app. All data synthetic.

/// Counts every achievement read and write, delegating to the real store.
final class CountingAchievementRepository implements AchievementRepository {
  CountingAchievementRepository(this._inner);

  final AchievementRepository _inner;

  int reads = 0;
  int writes = 0;

  @override
  Future<List<AchievementUnlock>> unlocks(int sessionId) {
    reads++;
    return _inner.unlocks(sessionId);
  }

  @override
  Future<UnlockChanges> reconcileUnlocks(
    int sessionId,
    List<EarnedAchievement> earned, {
    required LocalDate today,
    required DateTime at,
  }) {
    writes++;
    return _inner.reconcileUnlocks(sessionId, earned, today: today, at: at);
  }
}

/// The Path | Calendar switch's segment labelled [label].
Finder segment(String label) => find.descendant(
  of: find.byType(SegmentedButton<JourneyView>),
  matching: find.text(label),
);

/// Switches the Journey on screen to [label] ("Path" or "Calendar").
Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(segment(label));
  await tester.pumpAndSettle();
}

/// The view the switch shows as selected.
JourneyView selectedView(WidgetTester tester) => tester
    .widget<SegmentedButton<JourneyView>>(
      find.byType(SegmentedButton<JourneyView>),
    )
    .selected
    .single;

/// The calendar's vertical scrollable.
Finder calendarScrollable() => find
    .descendant(
      of: find.byType(ArcCalendarView),
      matching: find.byType(Scrollable),
    )
    .first;

/// A calendar cell (or any day) by its announced day number.
Finder dayCell(int day) => find.bySemanticsLabel(RegExp('^Day $day[,.]'));

/// A calendar week heading by its announced week number.
Finder weekHeading(int week) =>
    find.bySemanticsLabel(RegExp('^Week $week of 13,'));

/// Scrolls the calendar to its top, then down until [target] is on screen.
Future<void> reveal(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 20; i++) {
    final position = tester
        .state<ScrollableState>(calendarScrollable())
        .position;
    if (position.pixels <= position.minScrollExtent) break;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: calendarScrollable(),
  );
  await tester.pumpAndSettle();
}
